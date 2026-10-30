import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../claude/history.dart';
import '../codicons.dart';
import '../l10n.dart';
import '../projects.dart';
import '../theme.dart';
import 'sidebar.dart';
import 'widgets.dart';

/// Calm per-project colours (used when the user hasn't picked one).
const _palette = [0xFF4FA3E0, 0xFF6CC28A, 0xFFD9A74A, 0xFFC97BD6, 0xFFE07B6C, 0xFF5BC0BE, 0xFF9B8FE6, 0xFFB5C45A];
Color projectColor(Project pr) => Color(pr.color ?? _palette[pr.path.toLowerCase().hashCode.abs() % _palette.length]);

// ------------------------------------------------------------------ side panel list

class ProjectsView extends StatefulWidget {
  const ProjectsView({
    super.key,
    required this.onOpenHome,
    required this.onOverview,
    required this.onOpenFolder,
    required this.waitingIn,
    this.currentFolder,
  });
  final void Function(Project) onOpenHome;
  final VoidCallback onOverview;
  final VoidCallback onOpenFolder;
  final int Function(String folder) waitingIn;
  final String? currentFolder;
  @override
  State<ProjectsView> createState() => _ProjectsViewState();
}

class _ProjectsViewState extends State<ProjectsView> {
  final store = ProjectStore.instance;

  @override
  void initState() {
    super.initState();
    store.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _review() async {
    final picked = await showDialog<Set<String>>(context: context, builder: (_) => _SuggestDialog(items: store.suggestions));
    if (picked == null) return;
    for (final a in store.suggestions) {
      if (picked.contains(a.path)) {
        store.add(a.path);
      }
    }
    store.dismiss(store.suggestions.map((a) => a.path));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final sugg = store.suggestions;
    final cur = widget.currentFolder == null ? null : normPath(widget.currentFolder!);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PanelHeader(S.projects, actions: [
        IconBtn(Codicons.dashboard, size: 15, tooltip: S.overview, onTap: widget.onOverview),
        IconBtn(Codicons.newFolder, size: 15, tooltip: S.addProject, onTap: widget.onOpenFolder),
        IconBtn(Codicons.refresh, size: 15, tooltip: S.refresh, onTap: () async {
          await store.refreshActivity();
          if (mounted) setState(() {});
        }),
      ]),
      if (store.loaded && sugg.isNotEmpty)
        Container(
          margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: P.inputBg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: P.inputBorder),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(S.foundFolders(sugg.length), style: uiText(size: 12.5)),
            const SizedBox(height: 8),
            Row(children: [
              VsButton(S.review, dense: true, onTap: _review),
              const SizedBox(width: 6),
              VsButton(S.notNow, dense: true, primary: false, onTap: () {
                store.dismiss(sugg.map((a) => a.path));
                setState(() {});
              }),
            ]),
          ]),
        ),
      Expanded(
        child: !store.loaded
            ? const Center(child: ClaudeSpinner(size: 16))
            : store.projects.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(S.noProjects, style: uiText(size: 12.5, color: P.fgMuted)),
                  )
                : ListView(children: [
                    for (final pr in store.projects)
                      _ProjectRow(
                        project: pr,
                        waiting: widget.waitingIn(pr.path),
                        current: cur != null && (cur == normPath(pr.path) || cur.startsWith('${normPath(pr.path)}${p.separator}')),
                        onTap: () => widget.onOpenHome(pr),
                      ),
                  ]),
      ),
    ]);
  }
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({required this.project, required this.waiting, required this.current, required this.onTap});
  final Project project;
  final int waiting;
  final bool current;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final pr = project;
    return HoverBox(
      onTap: onTap,
      radius: 0,
      color: current ? P.selection.withValues(alpha: 0.35) : null,
      padding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
      child: Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: projectColor(pr), borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(pr.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: uiText(size: 13)),
            Text(
              [
                if (pr.lastActive != null) S.ago(pr.lastActive!),
                if (pr.codexSessions > 0) 'Codex',
              ].join(' · '),
              style: uiText(size: 11.5, color: P.fgFaint),
            ),
          ]),
        ),
        if (waiting > 0)
          Tooltip(
            message: S.waitingForYou,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: P.accent, borderRadius: BorderRadius.circular(8)),
              child: Text('$waiting', style: uiText(size: 11, color: Colors.white)),
            ),
          ),
      ]),
    );
  }
}

class _SuggestDialog extends StatefulWidget {
  const _SuggestDialog({required this.items});
  final List<FolderActivity> items;
  @override
  State<_SuggestDialog> createState() => _SuggestDialogState();
}

class _SuggestDialogState extends State<_SuggestDialog> {
  // Pre-select folders used in the last 60 days.
  late final Set<String> _sel = {
    for (final a in widget.items)
      if (DateTime.now().difference(a.last).inDays < 60) a.path
  };

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: P.menuBg,
      shape: RoundedRectangleBorder(side: BorderSide(color: P.menuBorder), borderRadius: BorderRadius.circular(8)),
      child: SizedBox(
        width: 520,
        height: 520,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
            child: Text(S.addProjectsTitle, style: uiText(size: 15, weight: FontWeight.w600)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
            child: Text(S.addProjectsHint, style: uiText(size: 12.5, color: P.fgMuted)),
          ),
          Expanded(
            child: ListView(children: [
              for (final a in widget.items)
                HoverBox(
                  onTap: () => setState(() => _sel.contains(a.path) ? _sel.remove(a.path) : _sel.add(a.path)),
                  radius: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  child: Row(children: [
                    Icon(_sel.contains(a.path) ? Codicons.passFilled : Codicons.circleLarge,
                        size: 16, color: _sel.contains(a.path) ? P.focus : P.fgFaint),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.basename(a.path), style: uiText()),
                        Text(a.path, maxLines: 1, overflow: TextOverflow.ellipsis, style: uiText(size: 11.5, color: P.fgFaint)),
                      ]),
                    ),
                    Text(S.ago(a.last), style: uiText(size: 11.5, color: P.fgFaint)),
                  ]),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              VsButton(S.cancel, primary: false, onTap: () => Navigator.pop(context)),
              const SizedBox(width: 8),
              VsButton(S.addSelected(_sel.length), onTap: () => Navigator.pop(context, _sel)),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ project home

class ProjectFacts {
  String? lastTitle;
  String? lastReply;
  DateTime? lastAt;
  List<String> nextSteps = [];
  String? nextFrom;
  String? branch;
  int changed = 0;
  List<String> commits = [];
  List<(String, DateTime)> recentFiles = [];
}

Future<ProjectFacts> gatherFacts(String root) async {
  final sessions = listSessions(root);
  final first = sessions.isEmpty ? null : sessions.first;
  final facts = await Isolate.run(() => _facts(root, first?.file.path));
  if (first != null) {
    facts.lastTitle = first.title;
    facts.lastAt = first.modified;
  }
  try {
    final st = await Process.run('git', ['-C', root, 'status', '--porcelain', '-b'], stdoutEncoding: utf8);
    if (st.exitCode == 0) {
      final lines = '${st.stdout}'.split('\n').where((l) => l.trim().isNotEmpty).toList();
      if (lines.isNotEmpty && lines.first.startsWith('##')) {
        facts.branch = lines.first.substring(3).split('...').first;
        facts.changed = lines.length - 1;
      }
      final log = await Process.run('git', ['-C', root, 'log', '-5', '--pretty=%s\t%cr'], stdoutEncoding: utf8);
      facts.commits = '${log.stdout}'.split('\n').where((l) => l.trim().isNotEmpty).toList();
    }
  } catch (_) {}
  return facts;
}

ProjectFacts _facts(String root, String? lastTranscript) {
  final f = ProjectFacts();
  // Last thing Claude said in the newest conversation.
  if (lastTranscript != null) {
    try {
      final file = File(lastTranscript);
      final len = file.lengthSync();
      final raf = file.openSync();
      final start = len > 256 * 1024 ? len - 256 * 1024 : 0;
      raf.setPositionSync(start);
      final tail = utf8.decode(raf.readSync(len - start), allowMalformed: true);
      raf.closeSync();
      for (final line in const LineSplitter().convert(tail).reversed) {
        if (!line.contains('"type":"assistant"')) continue;
        try {
          final m = jsonDecode(line) as Map;
          final content = (m['message'] as Map?)?['content'];
          if (content is List) {
            final t = content.whereType<Map>().where((b) => b['type'] == 'text').map((b) => '${b['text']}').join('\n').trim();
            if (t.isNotEmpty) {
              f.lastReply = t.length > 900 ? '${t.substring(0, 900)}…' : t;
              break;
            }
          }
        } catch (_) {}
      }
    } catch (_) {}
  }
  // Open "- [ ]" items from the usual plan files.
  for (final name in ['WORKLOG.md', 'TODO.md', 'ROADMAP.md', 'PLAN.md', 'NOTES.md', 'TASKS.md']) {
    final file = File(p.join(root, name));
    if (!file.existsSync()) continue;
    try {
      final items = file
          .readAsLinesSync()
          .map((l) => l.trim())
          .where((l) => l.startsWith('- [ ]') || l.startsWith('* [ ]'))
          .map((l) => l.substring(5).trim())
          .where((l) => l.isNotEmpty)
          .take(10)
          .toList();
      if (items.isNotEmpty) {
        f.nextSteps = items;
        f.nextFrom = name;
        break;
      }
    } catch (_) {}
  }
  // Recently changed files (skipping dependency/build folders).
  final recent = <(String, DateTime)>[];
  const skip = {'.git', 'node_modules', 'build', 'dist', '.dart_tool', '__pycache__', '.venv', 'venv', 'target', 'out', '.next'};
  final stack = [Directory(root)];
  var seen = 0;
  while (stack.isNotEmpty && seen < 20000) {
    final d = stack.removeLast();
    List<FileSystemEntity> es;
    try {
      es = d.listSync(followLinks: false);
    } catch (_) {
      continue;
    }
    for (final e in es) {
      final n = p.basename(e.path);
      if (e is Directory) {
        if (!skip.contains(n) && !n.startsWith('.')) stack.add(e);
      } else if (e is File) {
        seen++;
        try {
          recent.add((p.relative(e.path, from: root), e.lastModifiedSync()));
        } catch (_) {}
      }
    }
  }
  recent.sort((a, b) => b.$2.compareTo(a.$2));
  f.recentFiles = recent.take(8).toList();
  return f;
}

class ProjectHome extends StatefulWidget {
  const ProjectHome({
    super.key,
    required this.project,
    required this.onContinue,
    required this.onNewChat,
    required this.onResume,
    required this.onOpenFile,
    required this.onRemove,
  });
  final Project project;
  final VoidCallback onContinue, onNewChat, onRemove;
  final void Function(SessionInfo) onResume;
  final void Function(String path) onOpenFile;
  @override
  State<ProjectHome> createState() => _ProjectHomeState();
}

class _ProjectHomeState extends State<ProjectHome> {
  ProjectFacts? _facts;
  late final List<SessionInfo> _sessions = listSessions(widget.project.path).take(8).toList();

  @override
  void initState() {
    super.initState();
    gatherFacts(widget.project.path).then((f) {
      if (mounted) setState(() => _facts = f);
    });
  }

  Widget _card(String title, IconData icon, Widget child) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        decoration: BoxDecoration(
          color: P.sideBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: P.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(icon, size: 14, color: P.fgFaint),
            const SizedBox(width: 6),
            Text(title.toUpperCase(),
                style: uiText(size: 11, color: P.fgFaint, weight: FontWeight.w600).copyWith(letterSpacing: 0.5)),
          ]),
          const SizedBox(height: 10),
          child,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final pr = widget.project;
    final f = _facts;
    final color = projectColor(pr);
    final stopped = _card(
      S.whereWeStopped,
      Codicons.history,
      f == null
          ? const Align(alignment: Alignment.centerLeft, child: ClaudeSpinner(size: 14))
          : f.lastTitle == null
              ? Text(S.noSessionsYet, style: uiText(color: P.fgMuted))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(f.lastTitle!, style: uiText(weight: FontWeight.w600)),
                  if (f.lastAt != null) Text(S.ago(f.lastAt!), style: uiText(size: 12, color: P.fgFaint)),
                  if (f.lastReply != null) ...[
                    const SizedBox(height: 8),
                    Text(f.lastReply!, maxLines: 8, overflow: TextOverflow.ellipsis, style: uiText(size: 12.5, color: P.fgMuted)),
                  ],
                ]),
    );
    final next = _card(
      f?.nextFrom == null ? S.nextSteps : '${S.nextSteps} · ${f!.nextFrom}',
      Codicons.checklist,
      f == null
          ? const SizedBox(height: 14)
          : f.nextSteps.isEmpty
              ? Text(S.noNextSteps, style: uiText(color: P.fgMuted))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final s in f.nextSteps)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 3, right: 8),
                          child: Icon(Codicons.circleLarge, size: 12, color: P.fgFaint),
                        ),
                        Expanded(child: Text(s, style: uiText(size: 12.5))),
                      ]),
                    ),
                ]),
    );
    final sessions = _card(
      S.history,
      Codicons.commentDiscussion,
      _sessions.isEmpty
          ? Text(S.noSessionsYet, style: uiText(color: P.fgMuted))
          : Column(children: [
              for (final s in _sessions)
                HoverBox(
                  onTap: () => widget.onResume(s),
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  child: Row(children: [
                    Expanded(child: Text(s.title ?? s.id, maxLines: 1, overflow: TextOverflow.ellipsis, style: uiText(size: 12.5))),
                    const SizedBox(width: 8),
                    Text(S.ago(s.modified), style: uiText(size: 11.5, color: P.fgFaint)),
                  ]),
                ),
            ]),
    );
    final files = _card(
      S.recentFiles,
      Codicons.files,
      f == null
          ? const SizedBox(height: 14)
          : Column(children: [
              for (final (rel, t) in f.recentFiles)
                HoverBox(
                  onTap: () => widget.onOpenFile(p.join(pr.path, rel)),
                  padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                  child: Row(children: [
                    Icon(fileIcon(rel), size: 13, color: P.fgMuted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(rel.replaceAll('\\', '/'), maxLines: 1, overflow: TextOverflow.ellipsis, style: uiText(size: 12.5)),
                    ),
                    Text(S.ago(t), style: uiText(size: 11.5, color: P.fgFaint)),
                  ]),
                ),
            ]),
    );
    final git = f?.branch == null
        ? null
        : _card(
            'Git',
            Codicons.sourceControl,
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${f!.branch} · ${S.uncommitted(f.changed)}', style: uiText(size: 12.5)),
              const SizedBox(height: 6),
              for (final c in f.commits)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text(c.replaceAll('\t', '  ·  '), maxLines: 1, overflow: TextOverflow.ellipsis, style: uiText(size: 12, color: P.fgMuted)),
                ),
            ]),
          );

    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth > 820;
      final left = [stopped, next];
      final right = [sessions, files, if (git != null) git];
      return ListView(padding: const EdgeInsets.fromLTRB(28, 24, 28, 32), children: [
        Row(children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 12),
          Expanded(child: Text(pr.name, style: uiText(size: 24, weight: FontWeight.w600, height: 1.2))),
          IconBtn(Codicons.trash, size: 15, tooltip: S.removeProject, onTap: widget.onRemove),
        ]),
        Padding(
          padding: const EdgeInsets.only(left: 24, top: 2),
          child: Text(pr.path, style: uiText(size: 12, color: P.fgFaint)),
        ),
        const SizedBox(height: 16),
        Row(children: [
          VsButton(S.continueWork, icon: Codicons.play, onTap: widget.onContinue),
          const SizedBox(width: 8),
          VsButton(S.newChat, icon: Codicons.add, primary: false, onTap: widget.onNewChat),
        ]),
        const SizedBox(height: 20),
        if (wide)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(children: [for (final c in left) Padding(padding: const EdgeInsets.only(bottom: 14), child: c)])),
            const SizedBox(width: 14),
            Expanded(child: Column(children: [for (final c in right) Padding(padding: const EdgeInsets.only(bottom: 14), child: c)])),
          ])
        else
          for (final c in [...left, ...right]) Padding(padding: const EdgeInsets.only(bottom: 14), child: c),
      ]);
    });
  }
}

// ------------------------------------------------------------------ overview (launcher)

/// All projects as calm cards: the "launcher" view.
class ProjectsOverview extends StatefulWidget {
  const ProjectsOverview({super.key, required this.onOpen, required this.waitingIn});
  final void Function(Project) onOpen;
  final int Function(String folder) waitingIn;
  @override
  State<ProjectsOverview> createState() => _ProjectsOverviewState();
}

class _ProjectsOverviewState extends State<ProjectsOverview> {
  final store = ProjectStore.instance;
  @override
  void initState() {
    super.initState();
    store.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = store.projects;
    final waiting = [for (final pr in list) if (widget.waitingIn(pr.path) > 0) pr];
    return ListView(padding: const EdgeInsets.fromLTRB(28, 24, 28, 32), children: [
      Text(S.projects, style: uiText(size: 24, weight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text(S.overviewHint, style: uiText(color: P.fgMuted)),
      if (waiting.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text(S.waitingForYou.toUpperCase(), style: uiText(size: 11, color: P.accent, weight: FontWeight.w600).copyWith(letterSpacing: 0.5)),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 12, children: [for (final pr in waiting) _tile(pr)]),
      ],
      const SizedBox(height: 20),
      Wrap(spacing: 12, runSpacing: 12, children: [for (final pr in list) _tile(pr)]),
    ]);
  }

  Widget _tile(Project pr) {
    final w = widget.waitingIn(pr.path);
    return SizedBox(
      width: 230,
      child: HoverBox(
        onTap: () => widget.onOpen(pr),
        radius: 8,
        color: P.sideBg,
        border: Border.all(color: w > 0 ? P.accent.withValues(alpha: 0.7) : P.border),
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: projectColor(pr), borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 8),
            Expanded(child: Text(pr.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: uiText(size: 14, weight: FontWeight.w600))),
          ]),
          const SizedBox(height: 6),
          Text(p.basename(p.dirname(pr.path)), maxLines: 1, overflow: TextOverflow.ellipsis, style: uiText(size: 11.5, color: P.fgFaint)),
          const SizedBox(height: 10),
          Row(children: [
            Text(pr.lastActive == null ? '' : S.ago(pr.lastActive!), style: uiText(size: 12, color: P.fgMuted)),
            const Spacer(),
            if (pr.claudeSessions > 0) Pill('Claude ${pr.claudeSessions}'),
            if (pr.codexSessions > 0) ...[const SizedBox(width: 4), Pill('Codex ${pr.codexSessions}')],
          ]),
        ]),
      ),
    );
  }
}
