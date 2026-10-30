import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../codicons.dart';
import '../files.dart';
import '../l10n.dart';
import '../memory.dart';
import '../theme.dart';
import 'widgets.dart';

enum SideView { projects, explorer, search, memory }

/// The narrow icon column on the far left, like VS Code's activity bar.
class ActivityBar extends StatelessWidget {
  const ActivityBar({super.key, required this.view, required this.open, required this.onPick, this.badges = const {}});
  final SideView view;
  final bool open;
  final void Function(SideView) onPick;
  final Map<SideView, int> badges;

  @override
  Widget build(BuildContext context) {
    Widget item(SideView v, IconData icon, String tip) {
      final selected = open && v == view;
      final badge = badges[v] ?? 0;
      return Tooltip(
        message: tip,
        waitDuration: const Duration(milliseconds: 400),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => onPick(v),
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: selected ? P.fg : Colors.transparent, width: 2)),
              ),
              child: Stack(alignment: Alignment.center, children: [
                Icon(icon, size: 22, color: selected ? P.fg : P.fgFaint),
                if (badge > 0)
                  Positioned(
                    right: 8,
                    bottom: 9,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
                      decoration: BoxDecoration(color: P.accent, borderRadius: BorderRadius.circular(8)),
                      child: Text('$badge',
                          textAlign: TextAlign.center, style: uiText(size: 10, color: Colors.white, height: 1.45)),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 46,
      color: P.sideBg,
      child: Column(children: [
        item(SideView.projects, Codicons.home, S.projects),
        item(SideView.explorer, Codicons.files, '${S.explorer} (Ctrl+B)'),
        item(SideView.search, Codicons.search, '${S.searchFiles} (Ctrl+Shift+F)'),
        item(SideView.memory, Codicons.book, S.memory),
      ]),
    );
  }
}

/// Header line of a side panel ("EXPLORER" style).
class PanelHeader extends StatelessWidget {
  const PanelHeader(this.title, {super.key, this.actions = const []});
  final String title;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Container(
        height: 35,
        padding: const EdgeInsets.only(left: 18, right: 6),
        child: Row(children: [
          Expanded(
            child: Text(title.toUpperCase(),
                overflow: TextOverflow.ellipsis,
                style: uiText(size: 11, color: P.fgMuted, weight: FontWeight.w600).copyWith(letterSpacing: 0.4)),
          ),
          ...actions,
        ]),
      );
}

// ------------------------------------------------------------------ explorer

const _hiddenInExplorer = {'.git', '.dart_tool', '__pycache__', '.idea', '.vs'};

class ExplorerView extends StatefulWidget {
  const ExplorerView({super.key, required this.root, required this.onOpen, this.onMention});
  final String root;
  final void Function(String path) onOpen;
  final void Function(String path)? onMention;
  @override
  State<ExplorerView> createState() => _ExplorerViewState();
}

class _ExplorerViewState extends State<ExplorerView> {
  final Set<String> _open = {};
  final Map<String, List<FileSystemEntity>> _children = {};
  String? _selected;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // Agents create and delete files: re-list the visible (open) folders now and then.
    _poll = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) setState(_children.clear);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ExplorerView old) {
    super.didUpdateWidget(old);
    if (old.root != widget.root) {
      _open.clear();
      _children.clear();
    }
  }

  List<FileSystemEntity> _list(String dir) => _children.putIfAbsent(dir, () {
        try {
          final items = Directory(dir)
              .listSync(followLinks: false)
              .where((e) => !_hiddenInExplorer.contains(p.basename(e.path)))
              .toList();
          items.sort((a, b) {
            final da = a is Directory ? 0 : 1, db = b is Directory ? 0 : 1;
            if (da != db) return da - db;
            return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
          });
          return items;
        } catch (_) {
          return <FileSystemEntity>[];
        }
      });

  void _refresh() => setState(() => _children.clear());

  @override
  Widget build(BuildContext context) {
    final rows = <(FileSystemEntity, int)>[];
    void walk(String dir, int depth) {
      for (final e in _list(dir)) {
        rows.add((e, depth));
        if (e is Directory && _open.contains(e.path)) walk(e.path, depth + 1);
      }
    }

    walk(widget.root, 0);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PanelHeader(p.basename(widget.root), actions: [
        IconBtn(Codicons.refresh, size: 15, tooltip: S.refresh, onTap: _refresh),
        IconBtn(Codicons.collapseAll, size: 15, tooltip: S.collapseAll, onTap: () => setState(_open.clear)),
      ]),
      Expanded(
        child: ListView.builder(
          itemExtent: 22,
          itemCount: rows.length,
          itemBuilder: (context, i) {
            final (e, depth) = rows[i];
            final isDir = e is Directory;
            final name = p.basename(e.path);
            final open = _open.contains(e.path);
            return _TreeRow(
              depth: depth,
              selected: _selected == e.path,
              leading: isDir
                  ? Icon(open ? Codicons.chevronDown : Codicons.chevronRight, size: 14, color: P.fgMuted)
                  : const SizedBox(width: 14),
              icon: isDir ? null : fileIcon(name),
              label: name,
              onTap: () {
                setState(() => _selected = e.path);
                if (isDir) {
                  setState(() => open ? _open.remove(e.path) : _open.add(e.path));
                } else {
                  widget.onOpen(e.path);
                }
              },
              onMention: widget.onMention == null ? null : () => widget.onMention!(e.path),
            );
          },
        ),
      ),
    ]);
  }
}

IconData fileIcon(String name) {
  final ext = p.extension(name).toLowerCase();
  if (const {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg', '.ico', '.bmp'}.contains(ext)) return Codicons.fileMedia;
  if (const {'.md', '.txt', '.rst'}.contains(ext)) return Codicons.markdown;
  if (const {'.json', '.yaml', '.yml', '.toml', '.ini', '.xml'}.contains(ext)) return Codicons.settings;
  if (const {'.zip', '.7z', '.tar', '.gz', '.rar'}.contains(ext)) return Codicons.fileZip;
  if (const {'.pdf'}.contains(ext)) return Codicons.filePdf;
  return Codicons.fileCode;
}

class _TreeRow extends StatefulWidget {
  const _TreeRow({
    required this.depth,
    required this.selected,
    required this.leading,
    required this.icon,
    required this.label,
    required this.onTap,
    this.onMention,
  });
  final int depth;
  final bool selected;
  final Widget leading;
  final IconData? icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onMention;
  @override
  State<_TreeRow> createState() => _TreeRowState();
}

class _TreeRowState extends State<_TreeRow> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          color: widget.selected ? P.selection.withValues(alpha: 0.45) : (_h ? P.hover : null),
          padding: EdgeInsets.only(left: 8.0 + widget.depth * 12, right: 4),
          child: Row(children: [
            widget.leading,
            const SizedBox(width: 4),
            if (widget.icon != null) ...[Icon(widget.icon, size: 14, color: P.fgMuted), const SizedBox(width: 6)],
            Expanded(
              child: Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: uiText(size: 13)),
            ),
            if (_h && widget.onMention != null)
              IconBtn(Codicons.mention, size: 13, tooltip: S.mentionInChat, onTap: widget.onMention),
          ]),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ search

class SearchHit {
  SearchHit(this.path, this.line, this.text);
  final String path;
  final int line;
  final String text;
}

class SearchView extends StatefulWidget {
  const SearchView({super.key, required this.root, required this.onOpen});
  final String root;
  final void Function(String path, int line) onOpen;
  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  final _ctrl = TextEditingController();
  List<SearchHit> _hits = [];
  bool _busy = false;
  int _gen = 0;

  Future<void> _run() async {
    final q = _ctrl.text;
    final gen = ++_gen;
    if (q.trim().length < 2) {
      setState(() => _hits = []);
      return;
    }
    setState(() => _busy = true);
    final files = await FileIndex.of(widget.root).files();
    final root = widget.root;
    final hits = await Isolate.run(() => _grep(root, files, q));
    if (!mounted || gen != _gen) return;
    setState(() {
      _hits = hits;
      _busy = false;
    });
  }

  static List<SearchHit> _grep(String root, List<String> files, String q) {
    final out = <SearchHit>[];
    final needle = q.toLowerCase();
    for (final rel in files) {
      if (out.length >= 2000) break;
      final f = File(p.join(root, rel));
      try {
        if (f.lengthSync() > 1024 * 1024) continue;
        final bytes = f.readAsBytesSync();
        if (bytes.take(4000).contains(0)) continue;
        final lines = _decode(bytes).split('\n');
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].toLowerCase().contains(needle)) {
            out.add(SearchHit(rel, i + 1, lines[i].trim()));
            if (out.length >= 2000) break;
          }
        }
      } catch (_) {}
    }
    return out;
  }

  static String _decode(List<int> b) {
    try {
      return const Utf8Codec(allowMalformed: true).decode(b);
    } catch (_) {
      return String.fromCharCodes(b);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final byFile = <String, List<SearchHit>>{};
    for (final h in _hits) {
      (byFile[h.path] ??= []).add(h);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PanelHeader(S.searchFiles),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 10, 6),
        child: TextField(
          controller: _ctrl,
          autofocus: true,
          style: uiText(),
          onChanged: (_) => Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) _run();
          }),
          onSubmitted: (_) => _run(),
          decoration: InputDecoration(
            isDense: true,
            hintText: S.searchHint,
            hintStyle: uiText(color: P.fgFaint),
            filled: true,
            fillColor: P.inputBg,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(3), borderSide: BorderSide(color: P.inputBorder)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(3), borderSide: BorderSide(color: P.inputBorder)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(3), borderSide: BorderSide(color: P.focus)),
          ),
        ),
      ),
      if (_busy) LinearProgressIndicator(minHeight: 1, color: P.focus, backgroundColor: Colors.transparent),
      if (!_busy && _ctrl.text.trim().length >= 2)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 10, 4),
          child: Text(S.searchCount(_hits.length, byFile.length), style: uiText(size: 12, color: P.fgMuted)),
        ),
      Expanded(
        child: ListView(
          children: [
            for (final entry in byFile.entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 8, 2),
                child: Row(children: [
                  Icon(fileIcon(entry.key), size: 14, color: P.fgMuted),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(entry.key.split('/').last, overflow: TextOverflow.ellipsis, style: uiText(size: 13)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(entry.key, maxLines: 1, overflow: TextOverflow.ellipsis, style: uiText(size: 11.5, color: P.fgFaint)),
                  ),
                ]),
              ),
              for (final h in entry.value.take(30))
                HoverBox(
                  onTap: () => widget.onOpen(p.join(widget.root, h.path), h.line),
                  radius: 0,
                  padding: const EdgeInsets.fromLTRB(30, 2, 8, 2),
                  child: Text(
                    h.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: monoText(size: 12, color: P.fgMuted),
                  ),
                ),
            ],
          ],
        ),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ memory

class MemoryView extends StatefulWidget {
  const MemoryView({super.key, required this.cwd, required this.onOpen, required this.onGraph});
  final String cwd;
  final void Function(MemoryNote note) onOpen;
  final void Function(List<MemoryNote> notes) onGraph;
  @override
  State<MemoryView> createState() => _MemoryViewState();
}

class _MemoryViewState extends State<MemoryView> {
  late MemoryIndex _index = MemoryIndex.load(widget.cwd);
  String _q = '';

  @override
  void didUpdateWidget(covariant MemoryView old) {
    super.didUpdateWidget(old);
    if (old.cwd != widget.cwd) _index = MemoryIndex.load(widget.cwd);
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final notes = _index.notes
        .where((n) => q.isEmpty || n.title.toLowerCase().contains(q) || n.description.toLowerCase().contains(q))
        .toList();
    Widget section(String title, List<MemoryNote> list) => list.isEmpty
        ? const SizedBox.shrink()
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 4),
              child: Text(title, style: uiText(size: 11.5, color: P.fgFaint, weight: FontWeight.w600)),
            ),
            for (final n in list)
              HoverBox(
                onTap: () => widget.onOpen(n),
                radius: 0,
                padding: const EdgeInsets.fromLTRB(14, 4, 10, 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(n.kind == NoteKind.note ? Codicons.note : Codicons.book, size: 13, color: P.fgMuted),
                    const SizedBox(width: 6),
                    Expanded(child: Text(n.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: uiText(size: 13))),
                  ]),
                  if (n.description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 19),
                      child: Text(n.description,
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: uiText(size: 11.5, color: P.fgFaint)),
                    ),
                ]),
              ),
          ]);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PanelHeader(S.memory, actions: [
        IconBtn(Codicons.typeHierarchy, size: 15, tooltip: S.graph, onTap: () => widget.onGraph(_index.notes)),
        IconBtn(Codicons.refresh, size: 15, tooltip: S.refresh, onTap: () => setState(() => _index = MemoryIndex.load(widget.cwd))),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 10, 4),
        child: TextField(
          style: uiText(),
          onChanged: (v) => setState(() => _q = v),
          decoration: InputDecoration(
            isDense: true,
            hintText: S.search,
            hintStyle: uiText(color: P.fgFaint),
            filled: true,
            fillColor: P.inputBg,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(3), borderSide: BorderSide(color: P.inputBorder)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(3), borderSide: BorderSide(color: P.inputBorder)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(3), borderSide: BorderSide(color: P.focus)),
          ),
        ),
      ),
      Expanded(
        child: notes.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: Text(S.memoryEmpty, style: uiText(size: 12.5, color: P.fgMuted)),
              )
            : ListView(children: [
                section(S.memoryInstructions, notes.where((n) => n.kind != NoteKind.note).toList()),
                section(S.memoryNotes, notes.where((n) => n.kind == NoteKind.note).toList()),
              ]),
      ),
    ]);
  }
}
