import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

/// Folders that are never worth mentioning (dependencies, build output, caches, VCS).
const _skipDirs = {
  '.git', '.hg', '.svn', 'node_modules', '.dart_tool', 'build', 'dist', 'out', 'target', 'bin', 'obj',
  '.venv', 'venv', '.venv312', 'env', '__pycache__', '.mypy_cache', '.pytest_cache', '.idea', '.vs',
  '.gradle', '.next', '.nuxt', '.cache', 'coverage', 'Pods', '.terraform', '.wrangler', 'vendor',
};

/// Relative paths of the files in a project folder, built lazily (first "@") off the UI
/// thread and cached per folder.
class FileIndex {
  FileIndex._(this.root);
  final String root;
  static final Map<String, FileIndex> _cache = {};
  static FileIndex of(String root) => _cache.putIfAbsent(root, () => FileIndex._(root));

  List<String>? _files;
  Future<List<String>>? _loading;
  DateTime? _builtAt;

  Future<List<String>> files() {
    // Rebuild at most every 30 s so new files show up.
    if (_files != null && DateTime.now().difference(_builtAt!).inSeconds < 30) return Future.value(_files);
    return _loading ??= Isolate.run(() => _walk(root)).then((f) {
      _files = f;
      _builtAt = DateTime.now();
      _loading = null;
      return f;
    });
  }

  List<String>? get cached => _files;

  static List<String> _walk(String root) {
    final out = <String>[];
    final stack = <Directory>[Directory(root)];
    while (stack.isNotEmpty && out.length < 30000) {
      final dir = stack.removeLast();
      List<FileSystemEntity> entries;
      try {
        entries = dir.listSync(followLinks: false);
      } catch (_) {
        continue;
      }
      for (final e in entries) {
        final name = p.basename(e.path);
        if (e is Directory) {
          if (!_skipDirs.contains(name) && !name.startsWith('.')) stack.add(e);
        } else if (e is File) {
          out.add(p.relative(e.path, from: root).replaceAll('\\', '/'));
        }
      }
    }
    out.sort();
    return out;
  }
}

/// Fuzzy file match: every query character in order; file-name hits and contiguous runs
/// rank higher. Returns the best [limit] paths.
List<String> fuzzyFiles(List<String> files, String query, {int limit = 50}) {
  if (query.isEmpty) return files.take(limit).toList();
  final q = query.toLowerCase().replaceAll('\\', '/');
  final scored = <(int, String)>[];
  for (final f in files) {
    final s = _score(f.toLowerCase(), q);
    if (s > 0) scored.add((s, f));
  }
  scored.sort((a, b) => b.$1 != a.$1 ? b.$1.compareTo(a.$1) : a.$2.length.compareTo(b.$2.length));
  return [for (final s in scored.take(limit)) s.$2];
}

int _score(String path, String q) {
  final base = path.substring(path.lastIndexOf('/') + 1);
  if (base == q) return 10000;
  if (base.startsWith(q)) return 5000 - base.length;
  final inBase = base.indexOf(q);
  if (inBase >= 0) return 3000 - inBase;
  final inPath = path.indexOf(q);
  if (inPath >= 0) return 2000 - inPath;
  var score = 0, pi = 0, run = 0;
  for (var qi = 0; qi < q.length; qi++) {
    final c = q[qi];
    var found = false;
    while (pi < path.length) {
      if (path[pi] == c) {
        run++;
        score += 1 + run * 2;
        pi++;
        found = true;
        break;
      }
      run = 0;
      pi++;
    }
    if (!found) return 0;
  }
  return score;
}
