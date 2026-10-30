part of 'session.dart';

/// Finds the Codex CLI: FEATHER_CODEX_PATH, PATH, npm global install, or the binary bundled
/// with the ChatGPT/Codex VS Code extension.
ClaudeLauncher? locateCodex() {
  final env = Platform.environment;
  final custom = env['FEATHER_CODEX_PATH'];
  if (custom != null && File(custom).existsSync()) return ClaudeLauncher(custom);
  final pathDirs = (env['PATH'] ?? env['Path'] ?? '').split(Platform.isWindows ? ';' : ':');
  final exe = Platform.isWindows ? 'codex.exe' : 'codex';
  for (final d in pathDirs) {
    if (d.trim().isEmpty) continue;
    final f = File('${d.trim()}${Platform.pathSeparator}$exe');
    if (f.existsSync()) return ClaudeLauncher(f.path);
  }
  final appData = env['APPDATA'];
  if (appData != null) {
    final js = File('$appData\\npm\\node_modules\\@openai\\codex\\bin\\codex.js');
    if (js.existsSync()) {
      for (final d in pathDirs) {
        final node = File('${d.trim()}${Platform.pathSeparator}node.exe');
        if (node.existsSync()) return ClaudeLauncher(node.path, [js.path]);
      }
    }
  }
  final home = homeDir;
  if (home != null) {
    final ext = Directory('$home${Platform.pathSeparator}.vscode${Platform.pathSeparator}extensions');
    if (ext.existsSync()) {
      final dirs = ext
          .listSync()
          .whereType<Directory>()
          .where((d) => d.path.split(Platform.pathSeparator).last.startsWith('openai.chatgpt-'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      for (final d in dirs) {
        final bin = Directory('${d.path}${Platform.pathSeparator}bin');
        if (!bin.existsSync()) continue;
        for (final e in bin.listSync(recursive: true)) {
          if (e is File && e.path.toLowerCase().endsWith(Platform.isWindows ? '\\codex.exe' : '/codex')) {
            return ClaudeLauncher(e.path);
          }
        }
      }
    }
  }
  return null;
}

/// OpenAI Codex as a second agent: `codex app-server` speaks JSON-RPC over stdio. Its
/// events are translated into the same timeline items Claude uses, so the whole UI
/// (tool rows, diffs, permission and question cards, tabs) works unchanged.
class CodexSession extends ChatSession {
  CodexSession({required super.cwd, super.resumeId, super.model, super.permissionMode, super.effort});

  @override
  String get agent => 'codex';
  @override
  String get agentName => 'Codex';

  String? _threadId;
  String? _turnId;
  int _rpcId = 0;
  final Map<int, Completer<dynamic>> _rpc = {};
  final Map<String, ChatItem> _byItemId = {};
  final Map<String, Map<String, dynamic>> _fileChanges = {};

  // ---------------------------------------------------------------- lifecycle

  @override
  Future<void> start() async {
    final launcher = locateCodex();
    if (launcher == null) {
      status = SessionStatus.notFound;
      _notify(now: true);
      return;
    }
    if (status != SessionStatus.busy) {
      status = SessionStatus.starting;
      statusText = S.starting;
    }
    _killedOnPurpose = false;
    _initialized = false;
    _notify(now: true);
    try {
      _proc = await Process.start(launcher.executable, [...launcher.prefixArgs, 'app-server'], workingDirectory: cwd);
    } catch (e) {
      status = SessionStatus.exited;
      items.add(NoticeItem(S.processExited(-1), kind: NoticeKind.error, detail: '$e'));
      _notify(now: true);
      return;
    }
    final proc = _proc!;
    proc.stdout.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).listen(_onCodexLine);
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
      for (final c in _rpc.values) {
        if (!c.isCompleted) c.complete(null);
      }
      _rpc.clear();
      status = SessionStatus.exited;
      statusText = null;
      if (!_killedOnPurpose) {
        final tail = _stderr.toString().trim();
        items.add(NoticeItem(S.processExited(code),
            kind: NoticeKind.error, detail: tail.isEmpty ? null : ChatSession._lastLines(tail, 12)));
      }
      _notify(now: true);
    });

    await _call('initialize', {
      'clientInfo': {'name': 'feather', 'title': 'Feather', 'version': '1.0.0'},
      'capabilities': null,
    });
    _sendRaw({'method': 'initialized'});
    final list = await _call('model/list', {});
    if (list is Map && list['data'] is List) {
      final ms = <ModelInfo>[];
      for (final m in list['data'] as List) {
        if (m is! Map || m['hidden'] == true) continue;
        final efforts = [
          for (final e in (m['supportedReasoningEfforts'] as List? ?? []))
            if (e is Map) '${e['reasoningEffort']}'
        ];
        final info = ModelInfo('${m['id']}', '${m['displayName'] ?? m['id']}', '${m['description'] ?? ''}', efforts,
            resolvedModel: '${m['model'] ?? m['id']}');
        if (m['isDefault'] == true) {
          ms.insert(0, info);
        } else {
          ms.add(info);
        }
      }
      models = ms;
    }
    // The model in ~/.codex/config.toml may not be available for this account: always
    // pass one the server just listed.
    _model ??= models.isNotEmpty ? models.first.value : null;
    final policy = _policy(permissionMode);
    final threadParams = {
      'cwd': cwd,
      if (_model != null) 'model': _model,
      'approvalPolicy': policy.$1,
      'sandbox': policy.$2,
    };
    final r = resumeId != null
        ? await _call('thread/resume', {'threadId': resumeId, ...threadParams})
        : await _call('thread/start', threadParams);
    if (r is Map) {
      final thread = (r['thread'] as Map?)?.cast<String, dynamic>();
      _threadId = '${thread?['id'] ?? resumeId ?? ''}';
      sessionId = _threadId;
      resolvedModel = r['model'] as String?;
    }
    _initialized = true;
    if (status == SessionStatus.starting) {
      status = SessionStatus.idle;
      statusText = null;
    }
    for (final w in List.of(_pendingWrites)) {
      _startTurn(w);
    }
    _pendingWrites.clear();
    _notify(now: true);
  }

  /// Feather's modes → Codex approval policy + sandbox.
  static (String, String) _policy(String mode) => switch (mode) {
        'acceptEdits' => ('on-request', 'workspace-write'),
        'auto' => ('on-request', 'workspace-write'),
        'plan' => ('untrusted', 'read-only'),
        'bypassPermissions' => ('never', 'danger-full-access'),
        _ => ('untrusted', 'workspace-write'),
      };

  // ---------------------------------------------------------------- sending

  @override
  void send(String text, {List<ImageAttachment> images = const []}) {
    if (text.trim().isEmpty && images.isEmpty) return;
    items.add(UserItem(text, images: images));
    title ??= ChatSession._titleFrom(text);
    final input = <Map<String, dynamic>>[
      if (text.isNotEmpty) {'type': 'text', 'text': text, 'text_elements': []},
    ];
    for (final img in images) {
      // Codex takes local image files; write the attachment to a temp file.
      final ext = img.mediaType.split('/').last.replaceAll('jpeg', 'jpg');
      final f = File('${Directory.systemTemp.path}${Platform.pathSeparator}feather_${DateTime.now().microsecondsSinceEpoch}.$ext');
      f.writeAsBytesSync(img.bytes);
      input.add({'type': 'localImage', 'path': f.path});
    }
    final turn = {'input': input};
    if (_proc == null && status != SessionStatus.starting) {
      _pendingWrites.add(turn);
      restart();
    } else if (!_initialized) {
      _pendingWrites.add(turn);
    } else {
      _startTurn(turn);
    }
    status = SessionStatus.busy;
    busySince = DateTime.now();
    lastTurnStarted = busySince;
    statusText = S.working;
    _interruptRequested = false;
    _notify(now: true);
  }

  void _startTurn(Map<String, dynamic> turn) {
    final policy = _policy(permissionMode);
    _call('turn/start', {
      'threadId': _threadId,
      'input': turn['input'],
      if (_model != null) 'model': _model,
      if (_effort != null) 'effort': _effort,
      'approvalPolicy': policy.$1,
      'sandboxPolicy': _sandboxPolicy(policy.$2),
    });
  }

  static Map<String, dynamic> _sandboxPolicy(String mode) => switch (mode) {
        'read-only' => {'type': 'readOnly'},
        'danger-full-access' => {'type': 'dangerFullAccess'},
        _ => {'type': 'workspaceWrite'},
      };

  @override
  void interrupt() {
    if (_proc == null || _threadId == null) return;
    _interruptRequested = true;
    for (final r in pendingRequests) {
      _answer(r, 'cancel');
      r.state = RequestState.cancelled;
      r.touch();
    }
    if (_turnId != null) _call('turn/interrupt', {'threadId': _threadId, 'turnId': _turnId});
    _notify(now: true);
  }

  @override
  Future<void> setPermissionMode(String mode) async {
    _permissionMode = mode; // applied with the next turn/start
    _notify(now: true);
  }

  @override
  Future<void> setModel(String model) async {
    _model = model;
    resolvedModel = null;
    _notify(now: true);
  }

  @override
  Future<void> setEffort(String? effort) async {
    _effort = effort;
    _notify(now: true);
  }

  @override
  Future<Map<String, dynamic>?> refreshContextUsage() async => null;

  // ------------------------------------------------------- answering requests

  @override
  void allow(RequestItem r, {Map<String, dynamic>? updatedInput, List<dynamic>? permissions, String? summary}) {
    if (r.kind == RequestKind.question) {
      // Our card answers by question text; Codex wants them by question id.
      final byText = (updatedInput?['answers'] as Map?)?.cast<String, dynamic>() ?? {};
      final answers = <String, dynamic>{};
      for (final q in (r.input['questions'] as List? ?? [])) {
        if (q is! Map) continue;
        final a = byText['${q['question']}'];
        if (a != null) answers['${q['id']}'] = {'answers': '$a'.split(', ')};
      }
      _reply(r.requestId, {'answers': answers});
    } else {
      _answer(r, permissions != null && permissions.isNotEmpty ? 'acceptForSession' : 'accept');
    }
    r.state = RequestState.allowed;
    r.summary = summary;
    r.touch();
    _notify(now: true);
  }

  @override
  void deny(RequestItem r, {String? feedback}) {
    final has = feedback != null && feedback.trim().isNotEmpty;
    if (r.kind == RequestKind.question) {
      _reply(r.requestId, {'answers': <String, dynamic>{}});
    } else {
      _answer(r, has ? 'decline' : 'cancel');
    }
    r.state = RequestState.denied;
    r.summary = has ? feedback.trim() : null;
    r.touch();
    // Codex has no feedback field on a decision: steer the turn with the text instead.
    if (has && _threadId != null && _turnId != null) {
      _call('turn/steer', {
        'threadId': _threadId,
        'expectedTurnId': _turnId,
        'input': [
          {'type': 'text', 'text': feedback.trim(), 'text_elements': []}
        ],
      });
    }
    _notify(now: true);
  }

  void _answer(RequestItem r, String decision) => _reply(r.requestId, {'decision': decision});

  void _reply(String id, Map<String, dynamic> result) {
    final n = int.tryParse(id);
    _sendRaw({'id': n ?? id, 'result': result});
  }

  // ---------------------------------------------------------------- protocol

  Future<dynamic> _call(String method, Map<String, dynamic> params) {
    final id = ++_rpcId;
    final c = Completer<dynamic>();
    _rpc[id] = c;
    _sendRaw({'id': id, 'method': method, 'params': params});
    return c.future.timeout(const Duration(seconds: 90), onTimeout: () {
      _rpc.remove(id);
      return null;
    });
  }

  void _sendRaw(Map<String, dynamic> msg) {
    final p = _proc;
    if (p == null) return;
    final line = jsonEncode(msg);
    _log('>> $line');
    try {
      p.stdin.add(utf8.encode('$line\n'));
    } catch (_) {}
  }

  void _onCodexLine(String line) {
    _log('<< $line');
    if (line.isEmpty || line.codeUnitAt(0) != 0x7B) return;
    Map<String, dynamic> m;
    try {
      m = (jsonDecode(line) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    final method = m['method'] as String?;
    if (method == null) {
      // Response to one of our calls.
      final id = m['id'];
      final c = id is int ? _rpc.remove(id) : null;
      if (c != null && !c.isCompleted) {
        if (m['error'] != null) {
          final err = m['error'];
          items.add(NoticeItem(S.turnError, kind: NoticeKind.error, detail: err is Map ? '${err['message']}' : '$err'));
          _notify();
          c.complete(null);
        } else {
          c.complete(m['result']);
        }
      }
      return;
    }
    final params = (m['params'] as Map?)?.cast<String, dynamic>() ?? {};
    if (m.containsKey('id')) {
      _onServerRequest('${m['id']}', method, params);
      return;
    }
    _onNotification(method, params);
  }

  void _onServerRequest(String id, String method, Map<String, dynamic> p) {
    RequestItem? r;
    switch (method) {
      case 'item/commandExecution/requestApproval':
      case 'execCommandApproval':
        r = RequestItem(
          requestId: id,
          kind: RequestKind.permission,
          toolName: 'Shell',
          input: {
            'command': _prettyCommand(p['command'] is List ? (p['command'] as List).join(' ') : '${p['command'] ?? ''}'),
            if (p['reason'] != null) 'description': '${p['reason']}',
          },
          toolUseId: p['itemId'] as String?,
          suggestions: const ['session'],
          decisionReason: p['reason'] as String?,
        );
      case 'item/fileChange/requestApproval':
      case 'applyPatchApproval':
        final change = _fileChanges['${p['itemId']}'];
        r = RequestItem(
          requestId: id,
          kind: RequestKind.permission,
          toolName: 'Patch',
          input: {
            'changes': change?['changes'] ?? const [],
            if (p['reason'] != null) 'description': '${p['reason']}',
          },
          toolUseId: p['itemId'] as String?,
          suggestions: const ['session'],
          decisionReason: p['reason'] as String?,
        );
      case 'item/tool/requestUserInput':
        r = RequestItem(
          requestId: id,
          kind: RequestKind.question,
          toolName: 'AskUserQuestion',
          input: {
            'questions': [
              for (final q in (p['questions'] as List? ?? []))
                if (q is Map)
                  {
                    'id': q['id'],
                    'header': q['header'],
                    'question': q['question'],
                    'multiSelect': false,
                    'options': [
                      for (final o in (q['options'] as List? ?? []))
                        if (o is Map) {'label': o['label'], 'description': o['description'] ?? ''}
                    ],
                  }
            ],
          },
        );
      default:
        _sendRaw({
          'id': int.tryParse(id) ?? id,
          'error': {'code': -32601, 'message': 'Not supported by Feather'},
        });
        return;
    }
    _requests[id] = r;
    items.add(r);
    _notify(now: true);
    onNeedsUser?.call(this, r);
  }

  void _onNotification(String method, Map<String, dynamic> p) {
    switch (method) {
      case 'turn/started':
        _turnId = '${(p['turn'] as Map?)?['id'] ?? ''}';
      case 'item/started':
        _itemStarted((p['item'] as Map?)?.cast<String, dynamic>() ?? {});
      case 'item/completed':
        _itemCompleted((p['item'] as Map?)?.cast<String, dynamic>() ?? {});
      case 'item/agentMessage/delta':
        final it = _byItemId['${p['itemId']}'];
        if (it is TextItem) {
          it.text += '${p['delta'] ?? ''}';
          it.touch();
          _notify();
        }
      case 'item/reasoning/summaryTextDelta':
      case 'item/reasoning/textDelta':
        final it = _byItemId['${p['itemId']}'];
        if (it is ThinkingItem) {
          it.text += '${p['delta'] ?? ''}';
          it.touch();
          _notify();
        }
      case 'item/commandExecution/outputDelta':
        final it = _byItemId['${p['itemId']}'];
        if (it is ToolItem) {
          it.resultText = (it.resultText ?? '') + '${p['delta'] ?? ''}';
          it.touch();
          _notify();
        }
      case 'thread/tokenUsage/updated':
        final u = (p['tokenUsage'] as Map?)?.cast<String, dynamic>();
        final last = (u?['last'] as Map?)?['totalTokens'];
        final window = u?['modelContextWindow'];
        if (last is num && window is num && window > 0) contextPercent = last / window * 100;
      case 'error':
        if (p['willRetry'] == true) return;
        items.add(NoticeItem(S.turnError, kind: NoticeKind.error, detail: _errorText(p['error'])));
        _notify(now: true);
      case 'turn/completed':
        final turn = (p['turn'] as Map?)?.cast<String, dynamic>() ?? {};
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
        if (_interruptRequested || turn['status'] == 'interrupted') {
          items.add(NoticeItem(S.interrupted, kind: NoticeKind.interrupted));
        } else if (turn['status'] == 'failed' && !items.any((i) => i is NoticeItem && identical(i, items.last))) {
          items.add(NoticeItem(S.turnError, kind: NoticeKind.error, detail: _errorText(turn['error'])));
        }
        _interruptRequested = false;
        _turnId = null;
        status = _proc == null ? SessionStatus.exited : SessionStatus.idle;
        statusText = null;
        busySince = null;
        _notify(now: true);
        onTurnDone?.call(this);
    }
  }

  /// Codex wraps commands as "...powershell.exe" -Command '...' (or cmd /c ...) with
  /// escaped backslashes; show just the command the agent meant.
  static String _prettyCommand(String raw) {
    var c = raw.trim();
    final ps = RegExp(r"""^"?[^"]*powershell(?:\.exe)?"?\s+(?:-NoProfile\s+)?-Command\s+'([\s\S]*)'$""", caseSensitive: false).firstMatch(c);
    if (ps != null) return ps.group(1)!.replaceAll("''", "'");
    final cmd = RegExp(r'^"?[^"]*cmd(?:\.exe)?"?\s+/c\s+([\s\S]*)$', caseSensitive: false).firstMatch(c);
    if (cmd != null) return cmd.group(1)!;
    return c.replaceAll(r'\\', r'\');
  }

  static String _errorText(dynamic e) {
    if (e is! Map) return '$e';
    var msg = '${e['message'] ?? e}';
    // Server errors often wrap a JSON body: show its inner message.
    try {
      final inner = jsonDecode(msg);
      if (inner is Map && inner['error'] is Map) msg = '${(inner['error'] as Map)['message'] ?? msg}';
    } catch (_) {}
    return msg;
  }

  void _itemStarted(Map<String, dynamic> item) {
    final id = '${item['id'] ?? ''}';
    ChatItem? out;
    switch (item['type']) {
      case 'agentMessage':
        out = TextItem(text: '${item['text'] ?? ''}', streaming: true, messageId: id);
      case 'reasoning':
        out = ThinkingItem(streaming: true, messageId: id);
      case 'commandExecution':
        out = ToolItem(toolUseId: id, name: 'Shell', input: {'command': _prettyCommand('${item['command'] ?? ''}')})..inputComplete = true;
      case 'fileChange':
        _fileChanges[id] = item;
        out = _patchItem(id, item);
      case 'mcpToolCall':
        final args = item['arguments'];
        out = ToolItem(
          toolUseId: id,
          name: 'mcp__${item['server']}__${item['tool']}',
          input: args is Map ? args.cast<String, dynamic>() : {'arguments': '$args'},
        )..inputComplete = true;
      case 'webSearch':
        out = ToolItem(toolUseId: id, name: 'WebSearch', input: {'query': '${item['query'] ?? ''}'})..inputComplete = true;
      case 'plan':
        out = TextItem(text: '${item['text'] ?? ''}', streaming: true, messageId: id);
    }
    if (out == null) return;
    _byItemId[id] = out;
    if (out is ToolItem) _tools[id] = out;
    items.add(out);
    _notify();
  }

  ToolItem _patchItem(String id, Map<String, dynamic> item) {
    final changes = (item['changes'] as List? ?? []).whereType<Map>().toList();
    final first = changes.isEmpty ? '' : '${changes.first['path']}';
    final diff = changes.map((c) => '${c['diff'] ?? ''}').join('\n');
    return ToolItem(toolUseId: id, name: 'Patch', input: {
      'file_path': changes.length > 1 ? '$first (+${changes.length - 1})' : first,
      'unified_diff': diff,
    })
      ..inputComplete = true;
  }

  void _itemCompleted(Map<String, dynamic> item) {
    final id = '${item['id'] ?? ''}';
    final it = _byItemId[id];
    switch (item['type']) {
      case 'agentMessage':
      case 'plan':
        if (it is TextItem) {
          it.text = '${item['text'] ?? it.text}';
          it.streaming = false;
          it.touch();
        } else if ('${item['text'] ?? ''}'.trim().isNotEmpty) {
          items.add(TextItem(text: '${item['text']}', messageId: id));
        }
      case 'reasoning':
        if (it is ThinkingItem) {
          final summary = (item['summary'] as List? ?? []).join('\n');
          final content = (item['content'] as List? ?? []).join('\n');
          if (it.text.trim().isEmpty) it.text = summary.isNotEmpty ? summary : content;
          it.streaming = false;
          it.took = DateTime.now().difference(it.started);
          it.touch();
        }
      case 'commandExecution':
        if (it is ToolItem) {
          it.resultText = '${item['aggregatedOutput'] ?? it.resultText ?? ''}';
          final st = item['status'];
          final code = item['exitCode'];
          it.status = st == 'declined'
              ? ToolStatus.denied
              : (st == 'failed' || (code is num && code != 0))
                  ? ToolStatus.error
                  : ToolStatus.done;
          it.touch();
        }
      case 'fileChange':
        _fileChanges[id] = item;
        if (it is ToolItem) {
          it.input = _patchItem(id, item).input;
          final st = item['status'];
          it.status = st == 'declined' ? ToolStatus.denied : (st == 'failed' ? ToolStatus.error : ToolStatus.done);
          it.touch();
        }
      case 'mcpToolCall':
        if (it is ToolItem) {
          final err = item['error'];
          final res = item['result'];
          it.resultText = err != null ? '${err is Map ? err['message'] : err}' : (res == null ? '' : const JsonEncoder.withIndent('  ').convert(res));
          it.status = err != null ? ToolStatus.error : ToolStatus.done;
          it.touch();
        }
      case 'webSearch':
        if (it is ToolItem) {
          it.status = ToolStatus.done;
          it.touch();
        }
    }
    _notify();
  }
}
