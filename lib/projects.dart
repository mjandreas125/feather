import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'claude/locate.dart';

/// A folder the user works in with an agent.
class Project {
  Project({required this.path, required this.name, this.pinned = false, this.color});
  final String path;
  String name;
  bool pinned;
  int? color;
  DateTime? lastActive;
  int claudeSessions = 0;
  int codexSessions = 0;

  Map<String, dynamic> toJson() => {'path': path, 'name': name, if (pinned) 'pinned': true, if (color != null) 'color': color};
  static Project fromJson(Map<String, dynamic> j) =>
      Project(path: '${j['path']}', name: '${j['name'] ?? p.basename('${j['path']}')}', pinned: j['pinned'] == true, color: j['color'] as int?);
}

/// Activity found in agent history for one folder.
class FolderActivity {
  FolderActivity(this.path, this.last, this.claude, this.codex);
  final String path;
  final DateTime last;
  final int claude, codex;
}

String normPath(String path) => Platform.isWindows ? p.normalize(path).toLowerCase() : p.normalize(path);

/// Projects the user confirmed + folders seen in Claude Code / Codex history.
class ProjectStore {
  ProjectStore._();
  static final instance = ProjectStore._();

  final List<Project> projects = [];
  final Set<String> dismissed = {};
  List<FolderActivity> _activity = [];
  File? _file;
  bool loaded = false;

  /// Folders with history that are neither projects nor dismissed: offered to the user.
  List<FolderActivity> get suggestions {
    final known = {for (final pr in projects) normPath(pr.path)};
    return _activity.where((a) => !known.contains(normPath(a.path)) && !dismissed.contains(normPath(a.path))).toList();
  }

  Future<void> load() async {
    if (loaded) return;
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File(p.join(dir.path, 'projects.json'));
      if (_file!.existsSync()) {
        final j = jsonDecode(_file!.readAsStringSync()) as Map<String, dynamic>;
        projects.addAll([for (final x in (j['projects'] as List? ?? [])) if (x is Map) Project.fromJson(x.cast())]);
        dismissed.addAll([for (final d in (j['dismissed'] as List? ?? [])) '$d']);
      }
    } catch (_) {}
    loaded = true;
    await refreshActivity();
  }

  void save() {
    try {
      _file?.parent.createSync(recursive: true);
      _file?.writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
        'projects': [for (final pr in projects) pr.toJson()],
        'dismissed': dismissed.toList(),
      }));
    } catch (_) {}
  }

  Future<void> refreshActivity() async {
    final home = homeDir;
    if (home == null) return;
    _activity = await Isolate.run(() => _scan(home));
    final byPath = {for (final a in _activity) normPath(a.path): a};
    for (final pr in projects) {
      final a = byPath[normPath(pr.path)];
      pr.lastActive = a?.last ?? pr.lastActive;
      pr.claudeSessions = a?.claude ?? 0;
      pr.codexSessions = a?.codex ?? 0;
    }
    projects.sort(_order);
  }

  static int _order(Project a, Project b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    final ta = a.lastActive ?? DateTime(2000), tb = b.lastActive ?? DateTime(2000);
    return tb.compareTo(ta);
  }

  void add(String path, {String? name}) {
    if (projects.any((pr) => normPath(pr.path) == normPath(path))) return;
    final a = _activity.where((x) => normPath(x.path) == normPath(path)).firstOrNull;
    projects.add(Project(path: path, name: name ?? p.basename(path))
      ..lastActive = a?.last ?? DateTime.now()
      ..claudeSessions = a?.claude ?? 0
      ..codexSessions = a?.codex ?? 0);
    dismissed.remove(normPath(path));
    projects.sort(_order);
    save();
  }

  void remove(Project pr) {
    projects.remove(pr);
    dismissed.add(normPath(pr.path));
    save();
  }

  void dismiss(Iterable<String> paths) {
    dismissed.addAll(paths.map(normPath));
    save();
  }

  Project? forFolder(String path) {
    final n = normPath(path);
    for (final pr in projects) {
      if (n == normPath(pr.path) || n.startsWith('${normPath(pr.path)}${p.separator}')) return pr;
    }
    return null;
  }

  // ------------------------------------------------------------ history scan (isolate)

  static List<FolderActivity> _scan(String home) {
    final claude = <String, (String, DateTime, int)>{}; // norm → (path, last, count)
    final codex = <String, (String, DateTime, int)>{};

    // Claude Code: one folder per working directory; the transcript lines carry "cwd".
    final root = Directory(p.join(home, '.claude', 'projects'));
    if (root.existsSync()) {
      for (final d in root.listSync().whereType<Directory>()) {
        final files = d.listSync().whereType<File>().where((f) => f.path.endsWith('.jsonl')).toList();
        if (files.isEmpty) continue;
        files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
        final cwd = _cwdOf(files.first, 'cwd');
        if (cwd == null || !Directory(cwd).existsSync()) continue;
        claude[normPath(cwd)] = (cwd, files.first.lastModifiedSync(), files.length);
      }
    }

    // Codex: ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl, first line is session_meta {cwd}.
    final codexRoot = Directory(p.join(home, '.codex', 'sessions'));
    if (codexRoot.existsSync()) {
      final files = <File>[];
      try {
        for (final e in codexRoot.listSync(recursive: true)) {
          if (e is File && e.path.endsWith('.jsonl')) files.add(e);
        }
      } catch (_) {}
      files.sort((a, b) => b.path.compareTo(a.path)); // dated folders → newest first
      for (final f in files.take(400)) {
        final cwd = _cwdOf(f, 'cwd');
        if (cwd == null || !Directory(cwd).existsSync()) continue;
        final k = normPath(cwd);
        final t = f.lastModifiedSync();
        final prev = codex[k];
        codex[k] = (cwd, prev == null || t.isAfter(prev.$2) ? t : prev.$2, (prev?.$3 ?? 0) + 1);
      }
    }

    // Agents are often started in one folder but work all over the disk: attribute the
    // files they read/edit to the nearest project root (.git, pubspec.yaml, …).
    final touched = <String, (String, DateTime, int)>{};
    if (root.existsSync()) {
      final transcripts = <File>[];
      for (final d in root.listSync().whereType<Directory>()) {
        transcripts.addAll(d.listSync().whereType<File>().where((f) => f.path.endsWith('.jsonl')));
      }
      transcripts.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      final rootCache = <String, String?>{};
      final pathRe = RegExp(r'"(?:file_path|notebook_path)"\s*:\s*"((?:[^"\\]|\\.)*)"');
      for (final f in transcripts.take(60)) {
        final t = f.lastModifiedSync();
        String text;
        try {
          final len = f.lengthSync();
          final raf = f.openSync();
          const cap = 3 * 1024 * 1024;
          raf.setPositionSync(len > cap ? len - cap : 0);
          text = utf8.decode(raf.readSync(len > cap ? cap : len), allowMalformed: true);
          raf.closeSync();
        } catch (_) {
          continue;
        }
        final perFile = <String, int>{};
        for (final m in pathRe.allMatches(text)) {
          String path;
          try {
            path = jsonDecode('"${m.group(1)}"') as String;
          } catch (_) {
            continue;
          }
          if (!p.isAbsolute(path) || p.isWithin(p.join(home, '.claude'), path)) continue;
          final r = _projectRoot(p.dirname(path), home, rootCache);
          if (r != null) perFile[r] = (perFile[r] ?? 0) + 1;
        }
        for (final e in perFile.entries) {
          final k = normPath(e.key);
          final prev = touched[k];
          touched[k] = (e.key, prev == null || t.isAfter(prev.$2) ? t : prev.$2, (prev?.$3 ?? 0) + e.value);
        }
      }
    }
    for (final e in touched.entries) {
      if (e.value.$3 < 3) continue; // a stray read is not a project
      final prev = claude[e.key];
      if (prev == null) {
        claude[e.key] = (e.value.$1, e.value.$2, 0);
      } else if (e.value.$2.isAfter(prev.$2)) {
        claude[e.key] = (prev.$1, e.value.$2, prev.$3);
      }
    }

    final out = <FolderActivity>[];
    for (final k in {...claude.keys, ...codex.keys}) {
      final c = claude[k], x = codex[k];
      final path = c?.$1 ?? x!.$1;
      final last = [c?.$2, x?.$2].whereType<DateTime>().reduce((a, b) => a.isAfter(b) ? a : b);
      // Skip throwaway folders (temp dirs) and the bare home folder.
      final lower = path.toLowerCase();
      if (lower.contains('${p.separator}temp${p.separator}') || lower.contains('${p.separator}tmp${p.separator}')) continue;
      if (normPath(path) == normPath(home)) continue;
      out.add(FolderActivity(path, last, c?.$3 ?? 0, x?.$3 ?? 0));
    }
    out.sort((a, b) => b.last.compareTo(a.last));
    return out;
  }

  static const _markers = {
    '.git', 'pubspec.yaml', 'package.json', 'pyproject.toml', 'requirements.txt', 'Cargo.toml', 'go.mod',
    'CMakeLists.txt', 'WORKLOG.md', 'composer.json', 'Gemfile', 'build.gradle', 'pom.xml', 'deno.json',
  };

  /// Nearest folder above [dir] that looks like a project; null if none before the drive
  /// root or the home folder.
  static String? _projectRoot(String dir, String home, Map<String, String?> cache) {
    final visited = <String>[];
    var d = dir;
    String? found;
    while (true) {
      final k = normPath(d);
      if (cache.containsKey(k)) {
        found = cache[k];
        break;
      }
      visited.add(k);
      if (k == normPath(home) || p.dirname(d) == d) break;
      try {
        final dd = Directory(d);
        if (dd.existsSync()) {
          final names = dd.listSync(followLinks: false).map((e) => p.basename(e.path)).toSet();
          if (names.any(_markers.contains) || names.any((n) => n.endsWith('.sln') || n.endsWith('.csproj'))) {
            found = d;
            break;
          }
        }
      } catch (_) {}
      d = p.dirname(d);
    }
    for (final v in visited) {
      cache[v] = found;
    }
    return found;
  }

  /// First "cwd" value in the first 64 KB of a JSONL transcript.
  static String? _cwdOf(File f, String key) {
    try {
      final raf = f.openSync();
      final head = utf8.decode(raf.readSync(64 * 1024), allowMalformed: true);
      raf.closeSync();
      final m = RegExp('"$key"\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"').firstMatch(head);
      if (m == null) return null;
      return jsonDecode('"${m.group(1)}"') as String;
    } catch (_) {
      return null;
    }
  }
}
