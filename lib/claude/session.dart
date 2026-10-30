import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../l10n.dart';
import 'chat_items.dart';
import 'locate.dart';

part 'codex_session.dart';

/// dormant = opened from history, no process yet (it starts on the first message).
enum SessionStatus { dormant, starting, idle, busy, exited, notFound }

class ModelInfo {
  ModelInfo(this.value, this.displayName, this.description, this.effortLevels, {this.resolvedModel});
  final String value, displayName, description;
  final String? resolvedModel;
  final List<String> effortLevels;
}

class SlashCommand {
  SlashCommand(this.name, this.description, this.argumentHint);
  final String name, description, argumentHint;
}

/// One conversation = one Claude Code process speaking stream-json over stdio.
/// The protocol is the one the official SDKs and the VS Code extension use.
class ChatSession extends ChangeNotifier {
  ChatSession({required this.cwd, this.resumeId, String? model, String? permissionMode, String? effort})
      : _model = model,
        _permissionMode = permissionMode,
        _effort = effort,
        sessionId = resumeId,
        status = resumeId != null ? SessionStatus.dormant : SessionStatus.starting;

  final String cwd;
  String? resumeId;
  int tabId = 0;

  /// Which agent this tab talks to.
  String get agent => 'claude';
  String get agentName => 'Claude';

  final List<ChatItem> items = [];
  SessionStatus status;
  String? statusText;
  String? sessionId;
  String? title;
  DateTime? busySince;
  DateTime? lastTurnStarted;
  String? claudeVersion;
  Map<String, dynamic>? account;
  List<ModelInfo> _models = [];
  List<ModelInfo> get models => _models.isNotEmpty ? _models : knownModels;
  set models(List<ModelInfo> v) => _models = v;

  /// Model list from any tab's start-up, so tabs without a process (opened from history)
  /// can still show and change the model.
  static List<ModelInfo> knownModels = [];
  List<SlashCommand> commands = [];
  double? contextPercent;
  double totalCost = 0;
  Map<String, dynamic>? rateLimit;

  String? _model; // alias the user picked ("default", "opus", …) or null = CLI default
  String? _effort;
  String? _permissionMode;
  String? get model => _model;
  String? get effort => _effort;
  String get permissionMode => _permissionMode ?? 'default';
  String? resolvedModel; // from system/init

  /// Human name of the model in use ("Opus 5.5"), resolving the "default" alias.
  String get modelDisplayName {
    final v = _model ?? 'default';
    final picked = models.where((m) => m.value == v).toList();
    final target = resolvedModel ?? (picked.isNotEmpty ? picked.first.resolvedModel : null);
    if (target != null) {
      final named = models.where((m) => m.value != 'default' && m.resolvedModel == target).toList();
      if (named.isNotEmpty) return named.first.displayName;
    }
    if (picked.isNotEmpty) return picked.first.displayName.replaceAll(RegExp(r'\s*\(.*\)$'), '');
    return target ?? v;
  }

  /// Called when a request starts waiting for the user (for notifications).
  void Function(ChatSession, RequestItem)? onNeedsUser;
  /// Called when a turn finishes.
  void Function(ChatSession)? onTurnDone;

  Process? _proc;
  bool _killedOnPurpose = false;
  bool _initialized = false;
  bool _interruptRequested = false;
  final List<Map<String, dynamic>> _pendingWrites = [];
  final Map<String, Completer<Map<String, dynamic>?>> _pending = {};
  final Map<String, ToolItem> _tools = {};
  final Map<String, RequestItem> _requests = {};
  final Map<String, Map<int, ChatItem>> _blocks = {}; // "<parent>|<msgId>" → index → item
  final Map<String, String> _currentMsg = {}; // parent → current message id
  final Set<int> _finalized = {};
  final StringBuffer _stderr = StringBuffer();
  int _reqCounter = 0;
  Timer? _notifyTimer;

  bool get isBusy => status == SessionStatus.busy;
  bool get isAlive => _proc != null;
  List<RequestItem> get pendingRequests =>
      _requests.values.where((r) => r.state == RequestState.pending).toList();

  // ---------------------------------------------------------------- lifecycle

  Future<void> start() async {
    final launcher = locateClaude();
    if (launcher == null) {
      status = SessionStatus.notFound;
      _notify(now: true);
      return;
    }
    // A message may already be queued (send() before start): keep showing "working".
    if (status != SessionStatus.busy) {
      status = SessionStatus.starting;
      statusText = S.starting;
    }
    _killedOnPurpose = false;
    _initialized = false;
    _notify(now: true);

    final args = <String>[
      ...launcher.prefixArgs,
      '--output-format', 'stream-json',
      '--verbose',
      '--input-format', 'stream-json',
      '--permission-prompt-tool=stdio',
      '--setting-sources=user,project,local',
      '--include-partial-messages',
      if (_permissionMode != null) '--permission-mode=$_permissionMode',
      if (_model != null && _model != 'default') ...['--model', _model!],
      if (_effort != null) ...['--effort', _effort!],
      if (resumeId != null) ...['--resume', resumeId!],
    ];
    try {
      _proc = await Process.start(
        launcher.executable,
        args,
        workingDirectory: cwd,
      );
    } catch (e) {
      status = SessionStatus.exited;
      items.add(NoticeItem(S.processExited(-1), kind: NoticeKind.error, detail: '$e'));
      _notify(now: true);
      return;
    }
    final proc = _proc!;
    proc.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(_onLine, onError: (_) {});
    proc.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen((s) {
      _stderr.write(s);
      if (_stderr.length > 8000) {
        final t = _stderr.toString();
        _stderr
          ..clear()
          ..write(t.substring(t.length - 4000));
      }
    });
    proc.exitCode.then((code) {
      if (!identical(_proc, proc)) return;
      _proc = null;
      for (final r in pendingRequests) {
        r.state = RequestState.cancelled;
        r.touch();
      }
      for (final c in _pending.values) {
        if (!c.isCompleted) c.complete(null);
      }
      _pending.clear();
      status = SessionStatus.exited;
      statusText = null;
      if (!_killedOnPurpose) {
        final tail = _stderr.toString().trim();
        items.add(NoticeItem(S.processExited(code),
            kind: NoticeKind.error, detail: tail.isEmpty ? null : _lastLines(tail, 12)));
      }
      _notify(now: true);
    });

    final init = await _request({'subtype': 'initialize'}, beforeInit: true);
    _initialized = true;
    if (init != null) _applyInit(init);
    if (status == SessionStatus.starting) {
      status = SessionStatus.idle;
      statusText = null;
    }
    for (final w in List.of(_pendingWrites)) {
      _write(w);
    }
    _pendingWrites.clear();
    _notify(now: true);
  }

  /// Puts a past conversation (from the transcript) in front of the live timeline.
  void loadHistory(List<ChatItem> past) {
    items.insertAll(0, past);
    for (final it in past) {
      if (it is ToolItem) _tools[it.toolUseId] = it;
    }
    _notify(now: true);
  }

  Future<void> restart() async {
    resumeId = sessionId ?? resumeId;
    await _kill();
    await start();
  }

  Future<void> _kill() async {
    final p = _proc;
    if (p == null) return;
    _killedOnPurpose = true;
    _proc = null;
    try {
      await p.stdin.close();
    } catch (_) {}
    p.kill();
  }

  @override
  void dispose() {
    _notifyTimer?.cancel();
    _kill();
    super.dispose();
  }

  void _applyInit(Map<String, dynamic> r) {
    claudeVersion = r['claude_code_version'] as String?;
    account = (r['account'] as Map?)?.cast<String, dynamic>();
    final mode = r['current_permission_mode'];
    if (mode is String) _permissionMode = mode;
    models = [
      for (final m in (r['models'] as List? ?? []))
        if (m is Map)
          ModelInfo(
            '${m['value']}',
            '${m['displayName'] ?? m['value']}',
            '${m['description'] ?? ''}',
            [for (final e in (m['supportedEffortLevels'] as List? ?? [])) '$e'],
            resolvedModel: m['resolvedModel'] as String?,
          )
    ];
    if (models.isNotEmpty) knownModels = models;
    commands = [
      for (final c in (r['commands'] as List? ?? []))
        if (c is Map)
          SlashCommand('${c['name']}', '${c['description'] ?? ''}', '${c['argumentHint'] ?? ''}')
    ];
  }

  // ---------------------------------------------------------------- sending

  void send(String text, {List<ImageAttachment> images = const []}) {
    if (text.trim().isEmpty && images.isEmpty) return;
    items.add(UserItem(text, images: images));
    title ??= _titleFrom(text);
    final content = <Map<String, dynamic>>[
      for (final img in images)
        {
          'type': 'image',
          'source': {'type': 'base64', 'media_type': img.mediaType, 'data': img.base64Data},
        },
      if (text.isNotEmpty) {'type': 'text', 'text': text},
    ];
    final msg = {
      'type': 'user',
      'session_id': '',
      'parent_tool_use_id': null,
      'message': {'role': 'user', 'content': content},
    };
    if (_proc == null && status != SessionStatus.starting) {
      _pendingWrites.add(msg);
      restart();
    } else {
      _write(msg);
    }
    status = SessionStatus.busy;
    busySince = DateTime.now();
    lastTurnStarted = busySince;
    statusText = S.working;
    _interruptRequested = false;
    _notify(now: true);
  }

  void interrupt() {
    if (_proc == null) return;
    _interruptRequested = true;
    for (final r in pendingRequests) {
      _respond(r.requestId, {
        'behavior': 'deny',
        'message': 'Interrupted by user',
        'interrupt': true,
        if (r.toolUseId != null) 'toolUseID': r.toolUseId,
      });
      r.state = RequestState.cancelled;
      r.touch();
    }
    _request({'subtype': 'interrupt'});
    _notify(now: true);
  }

  Future<void> setPermissionMode(String mode) async {
    final old = _permissionMode;
    _permissionMode = mode;
    _notify(now: true);
    if (_proc == null) return;
    final r = await _request({'subtype': 'set_permission_mode', 'mode': mode});
    if (r == null) {
      _permissionMode = old;
      _notify(now: true);
    }
  }

  Future<void> setModel(String model) async {
    _model = model;
    resolvedModel = null;
    _notify(now: true);
    if (_proc != null) await _request({'subtype': 'set_model', 'model': model});
  }

  /// Effort is a start-up flag, so changing it restarts the process on the same session.
  Future<void> setEffort(String? effort) async {
    _effort = effort;
    _notify(now: true);
    if (_proc != null && !isBusy) await restart();
  }

  Future<Map<String, dynamic>?> refreshContextUsage() async {
    final r = await _request({'subtype': 'get_context_usage'});
    if (r != null) {
      final total = (r['totalTokens'] as num?)?.toDouble();
      final max = (r['maxTokens'] as num?)?.toDouble();
      if (total != null && max != null && max > 0) contextPercent = total / max * 100;
      _notify();
    }
    return r;
  }

  // ------------------------------------------------------- answering requests

  void allow(RequestItem r, {Map<String, dynamic>? updatedInput, List<dynamic>? permissions, String? summary}) {
    _respond(r.requestId, {
      'behavior': 'allow',
      'updatedInput': updatedInput ?? r.input,
      if (permissions != null && permissions.isNotEmpty) 'updatedPermissions': permissions,
      if (r.toolUseId != null) 'toolUseID': r.toolUseId,
    });
    r.state = RequestState.allowed;
    r.summary = summary;
    r.touch();
    for (final p in permissions ?? const []) {
      if (p is Map && p['type'] == 'setMode' && p['mode'] is String) _permissionMode = p['mode'] as String;
    }
    _notify(now: true);
  }

  void deny(RequestItem r, {String? feedback}) {
    final hasFeedback = feedback != null && feedback.trim().isNotEmpty;
    _respond(r.requestId, {
      'behavior': 'deny',
      'message': hasFeedback ? feedback.trim() : 'The user denied this action.',
      'interrupt': !hasFeedback,
      if (r.toolUseId != null) 'toolUseID': r.toolUseId,
    });
    r.state = RequestState.denied;
    r.summary = hasFeedback ? feedback.trim() : null;
    r.touch();
    _notify(now: true);
  }

  void _respond(String requestId, Map<String, dynamic> response) {
    _write({
      'type': 'control_response',
      'response': {'subtype': 'success', 'request_id': requestId, 'response': response},
    });
  }

  // ---------------------------------------------------------------- protocol

  Future<Map<String, dynamic>?> _request(Map<String, dynamic> request, {bool beforeInit = false}) {
    final id = 'feather_${++_reqCounter}';
    final c = Completer<Map<String, dynamic>?>();
    _pending[id] = c;
    final msg = {'type': 'control_request', 'request_id': id, 'request': request};
    if (_proc == null) {
      c.complete(null);
      _pending.remove(id);
      return c.future;
    }
    _write(msg, force: beforeInit);
    return c.future.timeout(const Duration(seconds: 60), onTimeout: () {
      _pending.remove(id);
      return null;
    });
  }

  void _write(Map<String, dynamic> msg, {bool force = false}) {
    final p = _proc;
    if (p == null || (!_initialized && !force && msg['type'] == 'user')) {
      _pendingWrites.add(msg);
      return;
    }
    final line = jsonEncode(msg);
    _log('>> $line');
    try {
      p.stdin.add(utf8.encode('$line\n'));
    } catch (_) {}
  }

  /// Protocol trace for bug reports: set FEATHER_LOG=C:\path\feather.log before starting.
  static final IOSink? _logSink = () {
    final path = Platform.environment['FEATHER_LOG'];
    if (path == null || path.isEmpty) return null;
    try {
      return File(path).openWrite(mode: FileMode.append);
    } catch (_) {
      return null;
    }
  }();

  void _log(String s) => debugLog(s);
  static void debugLog(String s) => _logSink?.writeln('${DateTime.now().toIso8601String()} $s');

  void _onLine(String line) {
    _log('<< $line');
    if (line.isEmpty || line.codeUnitAt(0) != 0x7B) return; // not JSON
    Map<String, dynamic> m;
    try {
      m = (jsonDecode(line) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    switch (m['type']) {
      case 'control_response':
        final resp = (m['response'] as Map?)?.cast<String, dynamic>() ?? {};
        final c = _pending.remove(resp['request_id']);
        if (c != null && !c.isCompleted) {
          c.complete(resp['subtype'] == 'success'
              ? ((resp['response'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{})
              : null);
        }
      case 'control_request':
        _onControlRequest(m);
      case 'control_cancel_request':
        final r = _requests[m['request_id']];
        if (r != null && r.state == RequestState.pending) {
          r.state = RequestState.cancelled;
          r.touch();
          _notify();
        }
      case 'system':
        _onSystem(m);
      case 'stream_event':
        _onStreamEvent(m);
      case 'assistant':
        _onAssistant(m);
      case 'user':
        _onUser(m);
      case 'result':
        _onResult(m);
      case 'rate_limit_event':
        rateLimit = (m['rate_limit_info'] as Map?)?.cast<String, dynamic>();
    }
  }

  void _onControlRequest(Map<String, dynamic> m) {
    final id = '${m['request_id']}';
    final req = (m['request'] as Map?)?.cast<String, dynamic>() ?? {};
    switch (req['subtype']) {
      case 'can_use_tool':
        final tool = '${req['tool_name']}';
        final kind = tool == 'AskUserQuestion'
            ? RequestKind.question
            : tool == 'ExitPlanMode'
                ? RequestKind.plan
                : RequestKind.permission;
        final r = RequestItem(
          requestId: id,
          kind: kind,
          toolName: tool,
          input: (req['input'] as Map?)?.cast<String, dynamic>() ?? {},
          toolUseId: req['tool_use_id'] as String?,
          suggestions: (req['permission_suggestions'] as List?) ?? const [],
          decisionReason: req['decision_reason'] is String ? req['decision_reason'] as String : null,
          blockedPath: req['blocked_path'] as String?,
        );
        _requests[id] = r;
        items.add(r);
        _notify(now: true);
        onNeedsUser?.call(this, r);
      case 'elicitation':
        _respond(id, {'action': 'decline'});
      default:
        _write({
          'type': 'control_response',
          'response': {'subtype': 'error', 'request_id': id, 'error': 'Not supported by this client'},
        });
    }
  }

  void _onSystem(Map<String, dynamic> m) {
    switch (m['subtype']) {
      case 'init':
        sessionId = m['session_id'] as String? ?? sessionId;
        resolvedModel = m['model'] as String?;
        final mode = m['permissionMode'];
        if (mode is String) _permissionMode = mode;
        _notify();
      case 'status':
        final s = m['status'];
        statusText = s == 'compacting' ? S.compacting : (isBusy ? S.working : null);
        _notify();
      case 'compact_boundary':
        items.add(NoticeItem('Conversation compacted', kind: NoticeKind.compact));
        _notify();
    }
  }

  List<ChatItem> _listFor(String? parent) {
    if (parent == null) return items;
    return _tools[parent]?.children ?? items;
  }

  void _onStreamEvent(Map<String, dynamic> m) {
    final parent = m['parent_tool_use_id'] as String?;
    final ev = (m['event'] as Map?)?.cast<String, dynamic>() ?? {};
    final key = parent ?? '';
    switch (ev['type']) {
      case 'message_start':
        final id = (ev['message'] as Map?)?['id'] as String?;
        if (id != null) _currentMsg[key] = id;
      case 'content_block_start':
        final msgId = (m['api_message_id'] as String?) ?? _currentMsg[key] ?? '';
        final index = (ev['index'] as num?)?.toInt() ?? 0;
        final block = (ev['content_block'] as Map?)?.cast<String, dynamic>() ?? {};
        ChatItem? item;
        switch (block['type']) {
          case 'text':
            item = TextItem(text: '${block['text'] ?? ''}', streaming: true, messageId: msgId);
          case 'thinking':
            item = ThinkingItem(text: '${block['thinking'] ?? ''}', streaming: true, messageId: msgId);
          case 'tool_use':
          case 'server_tool_use':
          case 'mcp_tool_use':
            final id = '${block['id']}';
            final t = _tools[id] ??
                ToolItem(toolUseId: id, name: '${block['name']}', messageId: msgId);
            _tools[id] = t;
            item = t;
        }
        if (item != null) {
          (_blocks['$key|$msgId'] ??= {})[index] = item;
          final list = _listFor(parent);
          if (!list.contains(item)) list.add(item);
          _parentTouch(parent);
          _notify();
        }
      case 'content_block_delta':
        final msgId = (m['api_message_id'] as String?) ?? _currentMsg[key] ?? '';
        final index = (ev['index'] as num?)?.toInt() ?? 0;
        final item = _blocks['$key|$msgId']?[index];
        final delta = (ev['delta'] as Map?)?.cast<String, dynamic>() ?? {};
        if (item is TextItem && delta['type'] == 'text_delta') {
          item.text += '${delta['text'] ?? ''}';
          item.touch();
        } else if (item is ThinkingItem && delta['type'] == 'thinking_delta') {
          item.text += '${delta['thinking'] ?? ''}';
          item.touch();
        } else if (item is ToolItem && delta['type'] == 'input_json_delta') {
          item.partialJson += '${delta['partial_json'] ?? ''}';
          item.touch();
        }
        _parentTouch(parent);
        _notify();
      case 'content_block_stop':
        final msgId = (m['api_message_id'] as String?) ?? _currentMsg[key] ?? '';
        final index = (ev['index'] as num?)?.toInt() ?? 0;
        final item = _blocks['$key|$msgId']?[index];
        if (item is TextItem) item.streaming = false;
        if (item is ThinkingItem) {
          item.streaming = false;
          item.took = DateTime.now().difference(item.started);
        }
        if (item is ToolItem && !item.inputComplete && item.partialJson.isNotEmpty) {
          try {
            item.input = (jsonDecode(item.partialJson) as Map).cast<String, dynamic>();
            item.inputComplete = true;
          } catch (_) {}
        }
        item?.touch();
        _notify();
    }
  }

  void _onAssistant(Map<String, dynamic> m) {
    final parent = m['parent_tool_use_id'] as String?;
    final msg = (m['message'] as Map?)?.cast<String, dynamic>() ?? {};
    final msgId = '${msg['id'] ?? ''}';
    final list = _listFor(parent);
    final content = msg['content'];
    if (content is! List) return;
    for (final raw in content) {
      if (raw is! Map) continue;
      final block = raw.cast<String, dynamic>();
      switch (block['type']) {
        case 'text':
          final text = '${block['text'] ?? ''}';
          final existing = list.whereType<TextItem>().where(
              (t) => t.messageId == msgId && !_finalized.contains(t.uid));
          final t = existing.isNotEmpty ? existing.first : null;
          if (t != null) {
            t.text = text;
            t.streaming = false;
            t.touch();
            _finalized.add(t.uid);
          } else if (text.trim().isNotEmpty) {
            final n = TextItem(text: text, messageId: msgId);
            _finalized.add(n.uid);
            list.add(n);
          }
        case 'thinking':
          final text = '${block['thinking'] ?? ''}';
          final existing = list.whereType<ThinkingItem>().where(
              (t) => t.messageId == msgId && !_finalized.contains(t.uid));
          final t = existing.isNotEmpty ? existing.first : null;
          if (t != null) {
            if (text.isNotEmpty) t.text = text;
            t.streaming = false;
            t.took ??= DateTime.now().difference(t.started);
            t.touch();
            _finalized.add(t.uid);
          } else if (text.isNotEmpty) {
            final n = ThinkingItem(text: text, messageId: msgId)..took = Duration.zero;
            _finalized.add(n.uid);
            list.add(n);
          }
        case 'tool_use':
        case 'server_tool_use':
        case 'mcp_tool_use':
          final id = '${block['id']}';
          final input = (block['input'] as Map?)?.cast<String, dynamic>() ?? {};
          final t = _tools[id];
          if (t != null) {
            t.input = input;
            t.inputComplete = true;
            t.touch();
            if (!list.contains(t)) list.add(t);
          } else {
            final n = ToolItem(toolUseId: id, name: '${block['name']}', input: input, messageId: msgId)
              ..inputComplete = true;
            _tools[id] = n;
            list.add(n);
          }
      }
    }
    _parentTouch(parent);
    _notify();
  }

  void _onUser(Map<String, dynamic> m) {
    final msg = (m['message'] as Map?)?.cast<String, dynamic>() ?? {};
    final content = msg['content'];
    final structured = m['tool_use_result'];
    if (content is String) {
      _maybeLocalCommandOutput(content);
      return;
    }
    if (content is! List) return;
    for (final raw in content) {
      if (raw is! Map) continue;
      final block = raw.cast<String, dynamic>();
      if (block['type'] == 'tool_result') {
        final t = _tools['${block['tool_use_id']}'];
        if (t == null) continue;
        t.resultText = _resultText(block['content']);
        t.structured = structured;
        final isError = block['is_error'] == true;
        t.status = !isError
            ? ToolStatus.done
            : (t.resultText ?? '').contains("doesn't want to proceed") ||
                    (t.resultText ?? '').contains('denied')
                ? ToolStatus.denied
                : ToolStatus.error;
        t.touch();
        _parentTouch(m['parent_tool_use_id'] as String?);
      } else if (block['type'] == 'text') {
        _maybeLocalCommandOutput('${block['text'] ?? ''}');
      }
    }
    _notify();
  }

  void _maybeLocalCommandOutput(String text) {
    final re = RegExp(r'<local-command-(stdout|stderr)>([\s\S]*?)</local-command-\1>');
    for (final match in re.allMatches(text)) {
      final body = match.group(2)!.trim();
      if (body.isEmpty) continue;
      items.add(NoticeItem(body, kind: match.group(1) == 'stderr' ? NoticeKind.error : NoticeKind.info));
    }
  }

  void _onResult(Map<String, dynamic> m) {
    final cost = m['total_cost_usd'];
    if (cost is num) totalCost = cost.toDouble();
    final isError = m['is_error'] == true || (m['subtype'] != null && m['subtype'] != 'success');
    for (final it in items) {
      if (it is TextItem && it.streaming) {
        it.streaming = false;
        it.touch();
      }
      if (it is ThinkingItem && it.streaming) {
        it.streaming = false;
        it.took ??= DateTime.now().difference(it.started);
        it.touch();
      }
    }
    if (_interruptRequested) {
      items.add(NoticeItem(S.interrupted, kind: NoticeKind.interrupted));
    } else if (isError) {
      final errors = m['errors'];
      final text = m['result'] is String && (m['result'] as String).isNotEmpty
          ? m['result'] as String
          : errors is List
              ? errors.join('\n')
              : '${m['subtype']}';
      items.add(NoticeItem(S.turnError, kind: NoticeKind.error, detail: text));
    }
    _interruptRequested = false;
    status = _proc == null ? SessionStatus.exited : SessionStatus.idle;
    statusText = null;
    busySince = null;
    _notify(now: true);
    onTurnDone?.call(this);
    refreshContextUsage();
  }

  void _parentTouch(String? parent) {
    if (parent != null) _tools[parent]?.touch();
  }

  // ---------------------------------------------------------------- helpers

  void _notify({bool now = false}) {
    if (now) {
      _notifyTimer?.cancel();
      _notifyTimer = null;
      notifyListeners();
      return;
    }
    _notifyTimer ??= Timer(const Duration(milliseconds: 33), () {
      _notifyTimer = null;
      notifyListeners();
    });
  }

  static String _resultText(dynamic content) {
    if (content is String) return content;
    if (content is List) {
      return content
          .whereType<Map>()
          .where((b) => b['type'] == 'text')
          .map((b) => '${b['text']}')
          .join('\n');
    }
    return content == null ? '' : '$content';
  }

  static String _lastLines(String s, int n) {
    final lines = s.split('\n');
    return lines.length <= n ? s : lines.sublist(lines.length - n).join('\n');
  }

  static String _titleFrom(String text) {
    final t = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    return t.length <= 60 ? t : '${t.substring(0, 57)}…';
  }
}
