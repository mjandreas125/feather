import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'claude/locate.dart';
import 'claude/session.dart';

/// Picks the UI language the user actually talks to Claude in:
///  1. the `language` setting of Claude Code (~/.claude/settings.json), if set;
///  2. otherwise the script of the user's own recent messages in Claude Code history;
///  3. null → caller falls back to the system language.
/// Only reads the tail of a few newest transcripts, so it costs a few milliseconds.
Future<String?> detectUserLanguage(List<String> supported) async {
  final home = homeDir;
  if (home == null) return null;
  final claudeDir = p.join(home, '.claude');

  // 1. Explicit Claude Code setting, e.g. "language": "russian" / "Русский" / "ru".
  try {
    final f = File(p.join(claudeDir, 'settings.json'));
    if (f.existsSync()) {
      final j = jsonDecode(f.readAsStringSync());
      final lang = j is Map ? j['language'] : null;
      if (lang is String && lang.trim().isNotEmpty) {
        final code = _codeFromName(lang, supported);
        if (code != null) return code;
      }
    }
  } catch (_) {}

  // 2. What the user writes in recent conversations.
  try {
    final projects = Directory(p.join(claudeDir, 'projects'));
    if (!projects.existsSync()) return null;
    final files = <File>[];
    for (final d in projects.listSync().whereType<Directory>()) {
      for (final f in d.listSync().whereType<File>()) {
        if (f.path.endsWith('.jsonl')) files.add(f);
      }
    }
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    // One vote per message (a long English prompt must not outweigh many short Russian
    // ones), over the 40 newest conversations.
    final votes = <String, int>{};
    for (final f in files.take(40)) {
      for (final text in _userTexts(f)) {
        final counts = <String, int>{};
        _countScripts(text, counts);
        if (counts.isEmpty) continue;
        final top = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
        if (top.value >= 3) votes[top.key] = (votes[top.key] ?? 0) + 1;
      }
    }
    ChatSession.debugLog('language votes: $votes from ${files.length} transcripts');
    if (votes.isEmpty) return null;
    // People who write in a non-Latin script often write English too (code, quick
    // prompts), the reverse is rare: a solid share of such messages decides.
    final total = votes.values.fold<int>(0, (a, b) => a + b);
    for (final e in votes.entries) {
      if (e.key != 'en' && supported.contains(e.key) && e.value >= 3 && e.value / total >= 0.3) return e.key;
    }
    final best = votes.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return supported.contains(best.key) ? best.key : null;
  } catch (e) {
    ChatSession.debugLog('language detection failed: $e');
    return null;
  }
}

String? _codeFromName(String name, List<String> supported) {
  final n = name.trim().toLowerCase();
  const names = {
    'ru': ['ru', 'russian', 'русский', 'рус'],
    'en': ['en', 'english', 'англ'],
  };
  for (final e in names.entries) {
    if (e.value.any((v) => n == v || n.startsWith(v)) && supported.contains(e.key)) return e.key;
  }
  return null;
}

/// User-typed text from the first and last 64 KB of a transcript (the opening request
/// and the latest replies; the middle is mostly tool output). Skips tool results and the
/// <ide_…>/<system-…> blocks the IDE inserts.
Iterable<String> _userTexts(File f) sync* {
  final len = f.lengthSync();
  const chunk = 64 * 1024;
  final raf = f.openSync();
  try {
    final parts = <List<int>>[];
    parts.add(raf.readSync(len < chunk ? len : chunk));
    if (len > 2 * chunk) {
      raf.setPositionSync(len - chunk);
      parts.add(raf.readSync(chunk));
    } else if (len > chunk) {
      parts.add(raf.readSync(len - chunk));
    }
    final text = parts.map((b) => utf8.decode(b, allowMalformed: true)).join('\n');
    for (final line in const LineSplitter().convert(text)) {
      if (!line.contains('"type":"user"')) continue;
      Map<String, dynamic> m;
      try {
        m = jsonDecode(line) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      if (m['type'] != 'user' || m['isMeta'] == true) continue;
      final content = (m['message'] as Map?)?['content'];
      if (content is String) {
        if (!content.trimLeft().startsWith('<')) yield content;
      } else if (content is List) {
        for (final b in content) {
          if (b is Map && b['type'] == 'text') {
            final t = '${b['text']}';
            if (!t.trimLeft().startsWith('<')) yield t;
          }
        }
      }
    }
  } finally {
    raf.closeSync();
  }
}

void _countScripts(String text, Map<String, int> counts) {
  // Strip code and paths, which are Latin whatever language the user speaks.
  final clean = text
      .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
      .replaceAll(RegExp(r'`[^`]*`'), ' ')
      .replaceAll(RegExp(r'[A-Za-z]:\\\S+|https?://\S+|\S+\.\w{1,5}\b'), ' ');
  for (final r in clean.runes) {
    if (r >= 0x0400 && r <= 0x04FF) {
      counts['ru'] = (counts['ru'] ?? 0) + 1;
    } else if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A)) {
      counts['en'] = (counts['en'] ?? 0) + 1;
    }
  }
}
