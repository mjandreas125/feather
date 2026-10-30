import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'claude/history.dart';
import 'claude/locate.dart';

enum NoteKind { globalInstructions, projectInstructions, memoryIndex, note }

/// One thing Claude "knows": a CLAUDE.md file or a memory note (memory/*.md).
class MemoryNote {
  MemoryNote({required this.path, required this.kind, required this.title, required this.description, required this.slug});
  final String path;
  final NoteKind kind;
  final String title;
  final String description;

  /// Name used in [[links]] (frontmatter `name`, else the file name).
  final String slug;

  String read() {
    try {
      return File(path).readAsStringSync();
    } catch (_) {
      return '';
    }
  }

  /// Body without the frontmatter block.
  String body() {
    final t = read().replaceAll('\r\n', '\n');
    if (t.startsWith('---\n')) {
      final end = t.indexOf('\n---', 4);
      if (end > 0) return t.substring(end + 4).trimLeft();
    }
    return t;
  }

  Set<String> links() => {for (final m in linkRe.allMatches(read())) m.group(1)!.trim()};

  static final linkRe = RegExp(r'\[\[([^\]\|#]+)(?:[|#][^\]]*)?\]\]');
}

/// What Claude Code loads for a folder: global and project CLAUDE.md plus the project's
/// auto-memory notes. Only the first lines (frontmatter) of each note are read here;
/// the full text is read when a note is opened.
class MemoryIndex {
  MemoryIndex(this.notes);
  final List<MemoryNote> notes;

  MemoryNote? bySlug(String slug) {
    final s = slug.toLowerCase();
    for (final n in notes) {
      if (n.slug.toLowerCase() == s || p.basenameWithoutExtension(n.path).toLowerCase() == s) return n;
    }
    return null;
  }

  List<MemoryNote> backlinks(MemoryNote target) =>
      [for (final n in notes) if (!identical(n, target) && n.links().any((l) => l.toLowerCase() == target.slug.toLowerCase())) n];

  static MemoryIndex load(String cwd) {
    final out = <MemoryNote>[];
    final home = homeDir;
    void addFile(String path, NoteKind kind, String title) {
      if (File(path).existsSync()) {
        out.add(MemoryNote(path: path, kind: kind, title: title, description: path, slug: p.basenameWithoutExtension(path)));
      }
    }

    if (home != null) addFile(p.join(home, '.claude', 'CLAUDE.md'), NoteKind.globalInstructions, 'CLAUDE.md · ~/.claude');
    for (final rel in ['CLAUDE.md', p.join('.claude', 'CLAUDE.md'), 'CLAUDE.local.md']) {
      addFile(p.join(cwd, rel), NoteKind.projectInstructions, rel.replaceAll('\\', '/'));
    }
    final proj = projectDir(cwd);
    final memDir = proj == null ? null : Directory(p.join(proj.path, 'memory'));
    if (memDir != null && memDir.existsSync()) {
      final files = memDir.listSync().whereType<File>().where((f) => f.path.toLowerCase().endsWith('.md')).toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final f in files) {
        final isIndex = p.basename(f.path).toUpperCase() == 'MEMORY.MD';
        final fm = _frontmatter(f);
        final name = fm['name'] ?? p.basenameWithoutExtension(f.path);
        out.add(MemoryNote(
          path: f.path,
          kind: isIndex ? NoteKind.memoryIndex : NoteKind.note,
          title: isIndex ? 'MEMORY.md' : _pretty(name),
          description: fm['description'] ?? '',
          slug: name,
        ));
      }
    }
    return MemoryIndex(out);
  }

  /// Reads only the frontmatter (first ~2 KB).
  static Map<String, String> _frontmatter(File f) {
    final out = <String, String>{};
    try {
      final raf = f.openSync();
      final head = utf8.decode(raf.readSync(2048), allowMalformed: true).replaceAll('\r\n', '\n');
      raf.closeSync();
      if (!head.startsWith('---\n')) return out;
      final end = head.indexOf('\n---', 4);
      final block = end > 0 ? head.substring(4, end) : head.substring(4);
      for (final line in block.split('\n')) {
        final m = RegExp(r'^(name|description):\s*(.*)$').firstMatch(line);
        if (m != null) {
          var v = m.group(2)!.trim();
          if (v.length >= 2 && (v.startsWith('"') && v.endsWith('"') || v.startsWith("'") && v.endsWith("'"))) {
            v = v.substring(1, v.length - 1).replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
          }
          out[m.group(1)!] = v;
        }
      }
    } catch (_) {}
    return out;
  }

  static String _pretty(String slug) {
    final s = slug.replaceAll(RegExp(r'[-_]+'), ' ').trim();
    return s.isEmpty ? slug : s[0].toUpperCase() + s.substring(1);
  }
}
