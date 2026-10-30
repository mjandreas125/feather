import 'dart:io';

import 'package:path/path.dart' as p;

/// How to start the Claude Code CLI: an executable plus arguments that go before ours.
class ClaudeLauncher {
  const ClaudeLauncher(this.executable, [this.prefixArgs = const []]);
  final String executable;
  final List<String> prefixArgs;

  @override
  String toString() => [executable, ...prefixArgs].join(' ');
}

String? get homeDir => Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];

/// Finds Claude Code. Order: FEATHER_CLAUDE_PATH, native installer location, PATH,
/// npm global install (run through node), VS Code extension's bundled binary.
ClaudeLauncher? locateClaude({String? override}) {
  final env = Platform.environment;
  final exeName = Platform.isWindows ? 'claude.exe' : 'claude';

  for (final candidate in [override, env['FEATHER_CLAUDE_PATH']]) {
    if (candidate != null && candidate.trim().isNotEmpty && File(candidate.trim()).existsSync()) {
      return _launcherFor(candidate.trim());
    }
  }

  final home = homeDir;
  if (home != null) {
    final native = p.join(home, '.local', 'bin', exeName);
    if (File(native).existsSync()) return ClaudeLauncher(native);
  }

  final pathDirs = (env['PATH'] ?? env['Path'] ?? '').split(Platform.isWindows ? ';' : ':');
  for (final dir in pathDirs) {
    if (dir.trim().isEmpty) continue;
    final exe = p.join(dir.trim(), exeName);
    if (File(exe).existsSync()) return ClaudeLauncher(exe);
  }
  // npm shim (claude.cmd) → run the package's cli.js with node directly, so stdin/stdout
  // are not routed through cmd.exe.
  for (final dir in pathDirs) {
    if (dir.trim().isEmpty) continue;
    final cli = p.join(dir.trim(), 'node_modules', '@anthropic-ai', 'claude-code', 'cli.js');
    if (File(cli).existsSync()) {
      final node = _which(Platform.isWindows ? 'node.exe' : 'node', pathDirs);
      if (node != null) return ClaudeLauncher(node, [cli]);
    }
  }
  final appData = env['APPDATA'];
  if (appData != null) {
    final cli = p.join(appData, 'npm', 'node_modules', '@anthropic-ai', 'claude-code', 'cli.js');
    final node = _which('node.exe', pathDirs);
    if (File(cli).existsSync() && node != null) return ClaudeLauncher(node, [cli]);
  }

  if (home != null) {
    final ext = Directory(p.join(home, '.vscode', 'extensions'));
    if (ext.existsSync()) {
      final dirs = ext
          .listSync()
          .whereType<Directory>()
          .where((d) => p.basename(d.path).startsWith('anthropic.claude-code-'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      for (final d in dirs) {
        final exe = p.join(d.path, 'resources', 'native-binary', exeName);
        if (File(exe).existsSync()) return ClaudeLauncher(exe);
      }
    }
  }
  return null;
}

ClaudeLauncher _launcherFor(String path) {
  if (path.toLowerCase().endsWith('.js')) {
    final node = _which(Platform.isWindows ? 'node.exe' : 'node',
        (Platform.environment['PATH'] ?? '').split(Platform.isWindows ? ';' : ':'));
    return ClaudeLauncher(node ?? 'node', [path]);
  }
  return ClaudeLauncher(path);
}

String? _which(String name, List<String> dirs) {
  for (final dir in dirs) {
    if (dir.trim().isEmpty) continue;
    final f = p.join(dir.trim(), name);
    if (File(f).existsSync()) return f;
  }
  return null;
}
