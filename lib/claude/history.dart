import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import 'chat_items.dart';
import 'locate.dart';

/// A past conversation stored by Claude Code in ~/.claude/projects/<folder-slug>/<id>.jsonl.
class SessionInfo {
  SessionInfo(this.id, this.file, this.modified);
  final String id;
  final File file;
  final DateTime modified;
  String? _title;
  bool _titleLoaded = false;

  /// AI title Claude Code wrote for the session, or the first thing the user typed.
  /// Read lazily (only when the row is shown) from the head/tail of the file.
  String? get title {
    if (!_titleLoaded) {
      _titleLoaded = true;
      _title = readSessionTitle(file);
    }
    return _title;
  }
}

/// Claude Code names a project folder by replacing every non-alphanumeric character of
/// the working directory with "-".
String projectSlug(String cwd) => cwd.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '-');

Directory? projectDir(String cwd) {
  final home = homeDir;
  if (home == null) return null;
  final root = Directory(p.join(home, '.claude', 'projects'));
  final exact = Directory(p.join(root.path, projectSlug(cwd)));
  if (exact.existsSync()) return exact;
  // Drive letters may differ in case (d: vs D:).
  if (root.existsSync()) {
    final want = projectSlug(cwd).toLowerCase();
    for (final d in root.listSync().whereType<Directory>()) {
      if (p.basename(d.path).toLowerCase() == want) return d;
    }
  }
  return null;
}

List<SessionInfo> listSessions(String cwd) {
  final dir = projectDir(cwd);
  if (dir == null) return [];
  final out = <SessionInfo>[];
  for (final f in dir.listSync().whereType<File>()) {
    if (!f.path.endsWith('.jsonl')) continue;
    final stat = f.statSync();
    if (stat.size < 200) continue;
    out.add(SessionInfo(p.basenameWithoutExtension(f.path), f, stat.modified));
  }
  out.sort((a, b) => b.modified.compareTo(a.modified));
  return out;
}

String? readSessionTitle(File f) {
  try {
    final len = f.lengthSync();
    final raf = f.openSync();
    try {
      // Latest AI / custom title near the end.
      const chunk = 48 * 1024;
      final start = len > chunk ? len - chunk : 0;
      raf.setPositionSync(start);
      final tail = utf8.decode(raf.readSync(len - start), allowMalformed: true);
      String? title;
      for (final line in const LineSplitter().convert(tail)) {
        if (!line.contains('-title"')) continue;
        try {
          final m = jsonDecode(line);
          if (m is Map) {
            final t = m['customTitle'] ?? m['aiTitle'] ?? m['title'];
            if (t is String && t.trim().isNotEmpty) title = t.trim();
          }
        } catch (_) {}
      }
      if (title != null) return title;
      // Otherwise the first message the user typed.
      raf.setPositionSync(0);
      final head = utf8.decode(raf.readSync(len < chunk ? len : chunk), allowMalformed: true);
      for (final line in const LineSplitter().convert(head)) {
        if (!line.contains('"type":"user"')) continue;
        try {
          final m = jsonDecode(line);
          if (m is! Map || m['isMeta'] == true) continue;
          final text = _firstUserText((m['message'] as Map?)?['content']);
          if (text != null) return text.length > 90 ? '${text.substring(0, 87)}…' : text;
        } catch (_) {}
      }
    } finally {
      raf.closeSync();
    }
  } catch (_) {}
  return null;
}

String? _firstUserText(dynamic content) {
  if (content is String) {
    final t = content.trim();
    return t.isEmpty || t.startsWith('<') ? null : t.replaceAll(RegExp(r'\s+'), ' ');
  }
  if (content is List) {
    for (final b in content) {
      if (b is Map && b['type'] == 'text') {
        final t = '${b['text']}'.trim();
        if (t.isNotEmpty && !t.startsWith('<')) return t.replaceAll(RegExp(r'\s+'), ' ');
      }
    }
  }
  return null;
}

/// Rebuilds the chat timeline from a transcript, off the UI thread.
Future<List<ChatItem>> loadTranscript(String path) => Isolate.run(() => _parseTranscript(path));

const _maxResult = 20000; // keep memory low: long tool outputs are trimmed in history

List<ChatItem> _parseTranscript(String path) {
  final items = <ChatItem>[];
  final tools = <String, ToolItem>{};
  final seenText = <String>{};
  for (final line in File(path).readAsLinesSync()) {
    if (!line.startsWith('{')) continue;
    Map<String, dynamic> m;
    try {
      m = (jsonDecode(line) as Map).cast<String, dynamic>();
    } catch (_) {
      continue;
    }
    final type = m['type'];
    if (type != 'user' && type != 'assistant') continue;
    if (m['isSidechain'] == true) continue; // sub-agent internals
    final msg = (m['message'] as Map?)?.cast<String, dynamic>() ?? const {};
    final content = msg['content'];

    if (type == 'assistant') {
      final msgId = '${msg['id'] ?? ''}';
      if (content is! List) continue;
      for (final b in content) {
        if (b is! Map) continue;
        switch (b['type']) {
          case 'text':
            final text = '${b['text'] ?? ''}';
            // The same block can be written twice (streaming + final); keep one.
            if (text.trim().isEmpty || !seenText.add('$msgId|$text')) continue;
            items.add(TextItem(text: text, messageId: msgId));
          case 'thinking':
            final text = '${b['thinking'] ?? ''}';
            if (text.trim().isEmpty) continue;
            items.add(ThinkingItem(text: text, messageId: msgId)..took = Duration.zero);
          case 'tool_use':
          case 'server_tool_use':
          case 'mcp_tool_use':
            final id = '${b['id']}';
            if (tools.containsKey(id)) continue;
            final t = ToolItem(
              toolUseId: id,
              name: '${b['name']}',
              input: (b['input'] as Map?)?.cast<String, dynamic>() ?? {},
              messageId: msgId,
            )
              ..inputComplete = true
              ..status = ToolStatus.done;
            tools[id] = t;
            items.add(t);
        }
      }
      continue;
    }

    // user
    if (m['isMeta'] == true) continue;
    if (m['isCompactSummary'] == true) {
      items.add(NoticeItem('Conversation compacted', kind: NoticeKind.compact));
      continue;
    }
    if (content is String) {
      _userString(content, items);
      continue;
    }
    if (content is! List) continue;
    final texts = <String>[];
    final images = <ImageAttachment>[];
    for (final b in content) {
      if (b is! Map) continue;
      switch (b['type']) {
        case 'tool_result':
          final t = tools['${b['tool_use_id']}'];
          if (t == null) continue;
          var r = _resultText(b['content']);
          if (r.length > _maxResult) r = '${r.substring(0, _maxResult)}\n…';
          t.resultText = r;
          final err = b['is_error'] == true;
          t.status = !err
              ? ToolStatus.done
              : (r.contains("doesn't want to proceed") ? ToolStatus.denied : ToolStatus.error);
          final structured = m['toolUseResult'];
          if (structured is Map && (structured['structuredPatch'] is List || structured['todos'] is List)) {
            t.structured = structured;
          }
        case 'text':
          final text = '${b['text'] ?? ''}';
          if (text.trim().isEmpty) continue;
          if (text.startsWith('[Request interrupted')) {
            items.add(NoticeItem('Interrupted', kind: NoticeKind.interrupted));
          } else if (!text.trimLeft().startsWith('<')) {
            texts.add(text);
          }
        case 'image':
          final src = b['source'];
          if (src is Map && src['type'] == 'base64') {
            images.add(ImageAttachment('${src['media_type']}', '${src['data']}'));
          }
      }
    }
    if (texts.isNotEmpty || images.isNotEmpty) items.add(UserItem(texts.join('\n'), images: images));
  }
  return items;
}

void _userString(String content, List<ChatItem> items) {
  final cmd = RegExp(r'<command-name>([^<]*)</command-name>').firstMatch(content);
  if (cmd != null) {
    final args = RegExp(r'<command-args>([^<]*)</command-args>').firstMatch(content)?.group(1) ?? '';
    items.add(UserItem('${cmd.group(1)!.trim()} ${args.trim()}'.trim()));
    return;
  }
  final out = RegExp(r'<local-command-stdout>([\s\S]*?)</local-command-stdout>').firstMatch(content);
  if (out != null) {
    final body = out.group(1)!.trim();
    if (body.isNotEmpty) items.add(NoticeItem(body));
    return;
  }
  if (content.startsWith('[Request interrupted')) {
    items.add(NoticeItem('Interrupted', kind: NoticeKind.interrupted));
    return;
  }
  if (content.trim().isEmpty || content.trimLeft().startsWith('<')) return;
  items.add(UserItem(content));
}

String _resultText(dynamic content) {
  if (content is String) return content;
  if (content is List) {
    return content.whereType<Map>().where((b) => b['type'] == 'text').map((b) => '${b['text']}').join('\n');
  }
  return content == null ? '' : '$content';
}
