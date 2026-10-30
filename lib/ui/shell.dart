import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../claude/chat_items.dart';
import '../claude/history.dart';
import '../claude/session.dart';
import '../keys.dart';
import '../memory.dart';
import '../projects.dart';
import '../l10n.dart';
import '../platform_window.dart';
import '../theme.dart';
import 'chat_panel.dart';
import 'composer.dart';
import 'editor.dart';
import 'memory_views.dart';
import 'projects_views.dart';
import 'sidebar.dart';
import 'widgets.dart';
import '../codicons.dart';

/// Defaults a new tab inherits.
class TabDefaults {
  const TabDefaults({this.model, this.mode, this.agent});
  final String? model, mode, agent;
}

/// Window content: a strip of conversation tabs (each its own Claude Code process)
/// over the active chat.
class Shell extends StatefulWidget {
  const Shell({
    super.key,
    required this.initialFolder,
    this.defaults = const TabDefaults(),
    this.initialPrompt,
    this.onFolderChanged,
    this.headerExtra,
  });
  final String initialFolder;
  final TabDefaults defaults;
  final String? initialPrompt;
  final void Function(String folder)? onFolderChanged;
  final Widget Function(BuildContext context)? headerExtra;

  @override
  State<Shell> createState() => ShellState();
}

class ShellState extends State<Shell> {
  final List<ChatSession> _tabs = [];
  int _active = 0;
  int _nextId = 1;
  final Set<int> _toasted = {};
  final _historyKey = GlobalKey();

  void showHistory() {
    final c = _historyKey.currentContext;
    // Open a moment later so the rest of the shortcut's key input can't land in the search box.
    if (c != null) Future.delayed(const Duration(milliseconds: 120), () { if (mounted) _showHistory(c, this); });
  }

  ChatSession get current => _tabs[_active];

  @override
  void initState() {
    super.initState();
    NativeWindow.init();
    NativeWindow.onToastActivated = (tag) {
      final id = int.tryParse(tag.replaceFirst('tab-', ''));
      final i = _tabs.indexWhere((t) => t.tabId == id);
      if (i >= 0) setState(() => _active = i);
    };
    NativeWindow.onFilesDropped = (paths) => ComposerState.active?.addPaths(paths);
    final d = widget.defaults;
    final s = _add(d.agent == 'codex'
        ? CodexSession(cwd: widget.initialFolder, model: d.model, permissionMode: d.mode)
        : ChatSession(cwd: widget.initialFolder, model: d.model, permissionMode: d.mode));
    s.start();
    final prompt = widget.initialPrompt;
    if (prompt != null && prompt.isNotEmpty) s.send(prompt);
  }

  @override
  void dispose() {
    for (final t in _tabs) {
      t.dispose();
    }
    super.dispose();
  }

  ChatSession _add(ChatSession s, {bool activate = true}) {
    s.tabId = _nextId++;
    s.onNeedsUser = _onNeedsUser;
    s.onTurnDone = _onTurnDone;
    s.addListener(_onSessionChanged);
    _tabs.add(s);
    if (activate) _active = _tabs.length - 1;
    widget.onFolderChanged?.call(s.cwd);
    return s;
  }

  /// New conversation. [agent] = 'claude' or 'codex'; default: same agent as the
  /// current tab (model/effort/mode are carried over only within the same agent).
  void newTab({String? folder, String? agent}) {
    final like = _tabs.isEmpty ? null : current;
    final a = agent ?? like?.agent ?? 'claude';
    final same = like != null && like.agent == a;
    final cwd = folder ?? like?.cwd ?? widget.initialFolder;
    final mode = like == null || like.permissionMode == 'default' ? null : like.permissionMode;
    final s = a == 'codex'
        ? CodexSession(cwd: cwd, model: same ? like.model : null, effort: same ? like.effort : null, permissionMode: mode)
        : ChatSession(cwd: cwd, model: same ? like.model : null, effort: same ? like.effort : null, permissionMode: mode);
    setState(() => _add(s));
    s.start();
  }

  Future<void> _newTabMenu(BuildContext anchor) async {
    final box = anchor.findRenderObject() as RenderBox;
    final pos = box.localToGlobal(Offset(0, box.size.height));
    final picked = await showMenu<String>(
      context: anchor,
      position: RelativeRect.fromLTRB(pos.dx - 160, pos.dy + 2, pos.dx, 0),
      items: [
        for (final (id, name, icon) in [('claude', 'Claude', Codicons.sparkle), ('codex', 'Codex', Codicons.hubot)])
          PopupMenuItem(
            value: id,
            height: 32,
            child: Row(children: [
              Icon(icon, size: 14, color: P.fgMuted),
              const SizedBox(width: 8),
              Text(S.newChatWith(name), style: uiText()),
            ]),
          ),
      ],
    );
    if (picked != null) newTab(agent: picked);
  }

  void closeTab(int i) {
    final s = _tabs[i];
    s.removeListener(_onSessionChanged);
    NativeWindow.hideToast('tab-${s.tabId}');
    setState(() {
      _tabs.removeAt(i);
      if (_tabs.isEmpty) {
        _add(ChatSession(cwd: s.cwd)).start();
      }
      _active = _active.clamp(0, _tabs.length - 1);
      if (i < _active || _active >= _tabs.length) _active = (_active - 1).clamp(0, _tabs.length - 1);
    });
    s.dispose();
  }

  void select(int i) {
    if (i < 0 || i >= _tabs.length) return;
    setState(() => _active = i);
    widget.onFolderChanged?.call(current.cwd);
  }

  Future<void> openFolder() async {
    final dir = await getDirectoryPath(initialDirectory: current.cwd);
    if (dir == null) return;
    // Reuse an empty tab instead of piling up blank ones.
    if (current.items.isEmpty && !current.isBusy) {
      final old = current;
      final s = ChatSession(cwd: dir, model: old.model, effort: old.effort);
      setState(() {
        old.removeListener(_onSessionChanged);
        s.tabId = _nextId++;
        s.onNeedsUser = _onNeedsUser;
        s.onTurnDone = _onTurnDone;
        s.addListener(_onSessionChanged);
        _tabs[_active] = s;
      });
      old.dispose();
      s.start();
      widget.onFolderChanged?.call(dir);
    } else {
      newTab(folder: dir);
    }
  }

  Future<void> resume(SessionInfo info, {String? cwd}) async {
    final open = _tabs.indexWhere((t) => t.sessionId == info.id);
    if (open >= 0) return select(open);
    final s = ChatSession(cwd: cwd ?? current.cwd, resumeId: info.id, model: current.model);
    s.title = info.title;
    setState(() {
      if (current.items.isEmpty && !current.isBusy && current.status != SessionStatus.busy) {
        final old = current;
        old.removeListener(_onSessionChanged);
        s.tabId = _nextId++;
        s.onNeedsUser = _onNeedsUser;
        s.onTurnDone = _onTurnDone;
        s.addListener(_onSessionChanged);
        _tabs[_active] = s;
        old.dispose();
      } else {
        _add(s);
      }
    });
    final past = await loadTranscript(info.file.path);
    s.loadHistory(past);
  }

  // ------------------------------------------------------------ notifications

  void _onSessionChanged() {
    if (!mounted) return;
    setState(() {});
    // A request answered in the app no longer needs its reminder ("finished" toasts stay
    // until the user dismisses them).
    for (final t in _tabs) {
      if (_toasted.contains(t.tabId) && t.pendingRequests.isEmpty && _lastToastWasRequest[t.tabId] == true) {
        _toasted.remove(t.tabId);
        NativeWindow.hideToast('tab-${t.tabId}');
      }
    }
  }

  final Map<int, bool> _lastToastWasRequest = {};

  Future<void> _onNeedsUser(ChatSession s, RequestItem r) async {
    if (r.notified) return;
    final looking = await NativeWindow.isForeground() && identical(s, current);
    if (looking) return;
    r.notified = true;
    final what = switch (r.kind) {
      RequestKind.question => '${((r.input['questions'] as List?)?.firstOrNull as Map?)?['question'] ?? S.waitingForYou}',
      RequestKind.plan => S.planTitle,
      RequestKind.permission => S.waitingForYou,
    };
    await _notify(s, S.notifyWaiting, what, request: true);
  }

  Future<void> _onTurnDone(ChatSession s) async {
    final started = s.lastTurnStarted;
    if (started == null || DateTime.now().difference(started).inSeconds < 20) return;
    final looking = await NativeWindow.isForeground() && identical(s, current);
    if (looking) return;
    final last = s.items.whereType<TextItem>().lastOrNull?.text.trim().split('\n').first ?? '';
    await _notify(s, S.notifyDone, last, request: false);
  }

  Future<void> _notify(ChatSession s, String title, String detail, {required bool request}) async {
    _toasted.add(s.tabId);
    _lastToastWasRequest[s.tabId] = request;
    final where = '${s.title ?? S.newChat} · ${p.basename(s.cwd)}';
    await NativeWindow.flash();
    await NativeWindow.toast(
      tag: 'tab-${s.tabId}',
      title: title,
      body: detail.isEmpty ? where : '$where\n$detail',
      openLabel: S.open,
      dismissLabel: S.dismiss,
    );
  }

  // ------------------------------------------------------------ keyboard

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final kb = HardwareKeyboard.instance;
    if (!kb.isControlPressed) return KeyEventResult.ignored;
    if (isLetter(e, LogicalKeyboardKey.keyB, PhysicalKeyboardKey.keyB)) {
      setState(() => _sideOpen = !_sideOpen);
      return KeyEventResult.handled;
    }
    if (kb.isShiftPressed && isLetter(e, LogicalKeyboardKey.keyF, PhysicalKeyboardKey.keyF)) {
      setState(() {
        _view = SideView.search;
        _sideOpen = true;
      });
      return KeyEventResult.handled;
    }
    if (isLetter(e, LogicalKeyboardKey.keyT, PhysicalKeyboardKey.keyT) ||
        isLetter(e, LogicalKeyboardKey.keyN, PhysicalKeyboardKey.keyN)) {
      newTab();
      return KeyEventResult.handled;
    }
    if (isLetter(e, LogicalKeyboardKey.keyW, PhysicalKeyboardKey.keyW)) {
      closeTab(_active);
      return KeyEventResult.handled;
    }
    if (isLetter(e, LogicalKeyboardKey.keyH, PhysicalKeyboardKey.keyH)) {
      showHistory();
      return KeyEventResult.handled;
    }
    if (isLetter(e, LogicalKeyboardKey.keyO, PhysicalKeyboardKey.keyO)) {
      openFolder();
      return KeyEventResult.handled;
    }
    if (isTab(e)) {
      final n = _tabs.length;
      select(kb.isShiftPressed ? (_active - 1 + n) % n : (_active + 1) % n);
      return KeyEventResult.handled;
    }
    final d = keyDigit(e);
    if (d != null && d <= _tabs.length) {
      select(d - 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ------------------------------------------------------------ side bar & editor

  SideView _view = SideView.explorer;
  bool _sideOpen = true;
  double _sideWidth = 260;
  final List<DocTab> _docs = [];
  int _activeDoc = 0;
  double? _editorWidth; // null = 55 % of the room on first open

  void pickView(SideView v) => setState(() {
        if (_sideOpen && _view == v) {
          _sideOpen = false;
        } else {
          _view = v;
          _sideOpen = true;
        }
      });

  void openDoc(DocTab d) {
    final i = _docs.indexWhere((x) => x.id == d.id);
    setState(() {
      if (i >= 0) {
        _docs[i] = d;
        _activeDoc = i;
      } else {
        _docs.add(d);
        _activeDoc = _docs.length - 1;
      }
    });
  }

  void closeDoc(int i) => setState(() {
        _docs.removeAt(i);
        if (_activeDoc >= _docs.length) _activeDoc = _docs.length - 1;
        if (_activeDoc < 0) _activeDoc = 0;
      });

  void openFile(String path, {int? line}) => openDoc(DocTab(
        id: 'file:$path${line == null ? '' : ':$line'}',
        title: p.basename(path),
        tooltip: path,
        icon: fileIcon(path),
        builder: (_) => FileView(path: path, line: line, root: current.cwd, onMention: mention),
      ));

  void openNote(MemoryNote note, MemoryIndex index) => openDoc(DocTab(
        id: 'note:${note.path}',
        title: note.title,
        tooltip: note.path,
        icon: Codicons.note,
        builder: (_) => NoteView(note: note, index: index, onOpenNote: (n) => openNote(n, index)),
      ));

  void openGraph(String cwd) {
    final index = MemoryIndex.load(cwd);
    openDoc(DocTab(
      id: 'graph:$cwd',
      title: S.graph,
      icon: Codicons.typeHierarchy,
      builder: (_) => MemoryGraph(index: index, onOpenNote: (n) => openNote(n, index)),
    ));
  }

  /// "@path" into the visible chat's input box.
  void mention(String path) {
    final c = ComposerState.active;
    if (c == null) return;
    final rel = p.isWithin(current.cwd, path) ? p.relative(path, from: current.cwd).replaceAll('\\', '/') : path;
    c.insert(rel.contains(' ') ? '@"$rel" ' : '@$rel ');
  }

  /// Links in Claude's answers such as [x](src/a.dart#L42) open in the editor.
  void _openLinkPath(String href, String cwd) {
    final parts = href.split('#');
    final raw = Uri.decodeComponent(parts.first);
    final path = p.isAbsolute(raw) ? raw : p.normalize(p.join(cwd, raw));
    final m = parts.length > 1 ? RegExp(r'L(\d+)').firstMatch(parts[1]) : null;
    openFile(path, line: m == null ? null : int.parse(m.group(1)!));
  }

  /// Chats waiting for the user inside [folder].
  int waitingIn(String folder) {
    final n = normPath(folder);
    return _tabs
        .where((t) => t.pendingRequests.isNotEmpty && (normPath(t.cwd) == n || normPath(t.cwd).startsWith('$n${p.separator}')))
        .length;
  }

  void openProjectHome(Project pr) => openDoc(DocTab(
        id: 'project:${pr.path}',
        title: pr.name,
        tooltip: pr.path,
        icon: Codicons.home,
        builder: (_) => ProjectHome(
          project: pr,
          onContinue: () => continueProject(pr),
          onNewChat: () => newTab(folder: pr.path),
          onResume: (s) => resume(s, cwd: pr.path),
          onOpenFile: openFile,
          onRemove: () {
            ProjectStore.instance.remove(pr);
            final i = _docs.indexWhere((d) => d.id == 'project:${pr.path}');
            if (i >= 0) closeDoc(i);
          },
        ),
      ));

  void openOverview() => openDoc(DocTab(
        id: 'overview',
        title: S.projects,
        icon: Codicons.dashboard,
        builder: (_) => ProjectsOverview(onOpen: openProjectHome, waitingIn: waitingIn),
      ));

  /// «Continue»: the latest conversation of the project (or a fresh chat if none).
  void continueProject(Project pr) {
    final sessions = listSessions(pr.path);
    if (sessions.isEmpty) {
      newTab(folder: pr.path);
    } else {
      resume(sessions.first, cwd: pr.path);
    }
  }

  Future<void> addProjectFolder() async {
    final dir = await getDirectoryPath(initialDirectory: current.cwd);
    if (dir == null) return;
    ProjectStore.instance.add(dir);
    setState(() {});
    final pr = ProjectStore.instance.forFolder(dir);
    if (pr != null) openProjectHome(pr);
  }

  Widget _sidePanel() {
    final cwd = current.cwd;
    return switch (_view) {
      SideView.explorer => ExplorerView(root: cwd, onOpen: (path) => openFile(path), onMention: mention),
      SideView.search => SearchView(root: cwd, onOpen: (path, line) => openFile(path, line: line)),
      SideView.memory => MemoryView(
          cwd: cwd,
          onOpen: (n) => openNote(n, MemoryIndex.load(cwd)),
          onGraph: (_) => openGraph(cwd),
        ),
      SideView.projects => ProjectsView(
          currentFolder: cwd,
          waitingIn: waitingIn,
          onOpenHome: openProjectHome,
          onOverview: openOverview,
          onOpenFolder: addProjectFolder,
        ),
    };
  }

  Widget _splitter(void Function(double dx) onDrag) => MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragUpdate: (d) => setState(() => onDrag(d.delta.dx)),
          child: Container(width: 4, color: Colors.transparent, child: Center(child: Container(width: 1, color: P.border))),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = current;
    final folder = p.basename(s.cwd);
    NativeWindow.setTitle(s.title == null ? '$folder — Feather' : '${s.title} — $folder — Feather');
    final chat = Column(children: [
      _TabStrip(shell: this),
      Expanded(
        child: IndexedStack(
          index: _active,
          children: [
            for (var i = 0; i < _tabs.length; i++)
              ExcludeFocus(
                excluding: i != _active,
                child: ChatPanel(
                  key: ObjectKey(_tabs[i]),
                  session: _tabs[i],
                  active: i == _active,
                  onOpenPath: (href) => _openLinkPath(href, _tabs[i].cwd),
                ),
              ),
          ],
        ),
      ),
    ]);
    final waiting = _tabs.where((t) => t.pendingRequests.isNotEmpty).length;
    return Focus(
      onKeyEvent: _onKey,
      child: LayoutBuilder(builder: (context, box) {
        final maxSide = (box.maxWidth * 0.4).clamp(180.0, 600.0);
        _sideWidth = _sideWidth.clamp(180.0, maxSide);
        final room = box.maxWidth - 46 - (_sideOpen ? _sideWidth + 4 : 0);
        _editorWidth = (_editorWidth ?? room * 0.55).clamp(260.0, math.max(260.0, room - 340));
        return Row(children: [
          ActivityBar(
            view: _view,
            open: _sideOpen,
            onPick: pickView,
            badges: {SideView.projects: waiting},
          ),
          if (_sideOpen) ...[
            Container(width: _sideWidth, color: P.sideBg, child: _sidePanel()),
            _splitter((dx) => _sideWidth += dx),
          ],
          if (_docs.isNotEmpty) ...[
            SizedBox(
              width: _editorWidth!,
              child: EditorArea(docs: _docs, active: _activeDoc, onSelect: (i) => setState(() => _activeDoc = i), onClose: closeDoc),
            ),
            _splitter((dx) => _editorWidth = _editorWidth! + dx),
          ],
          Expanded(child: chat),
        ]);
      }),
    );
  }
}


// ------------------------------------------------------------------ tab strip

class _TabStrip extends StatelessWidget {
  const _TabStrip({required this.shell});
  final ShellState shell;

  @override
  Widget build(BuildContext context) {
    final tabs = shell._tabs;
    return Container(
      height: 35,
      decoration: BoxDecoration(
        color: P.sideBg,
        border: Border(bottom: BorderSide(color: P.border)),
      ),
      child: Row(children: [
        Expanded(
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: tabs.length,
            itemBuilder: (context, i) => _Tab(
              session: tabs[i],
              active: i == shell._active,
              onTap: () => shell.select(i),
              onClose: () => shell.closeTab(i),
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconBtn(Codicons.add, tooltip: '${S.newChat} (Ctrl+T)', onTap: shell.newTab),
        Builder(builder: (c) => IconBtn(Codicons.chevronDown, size: 12, tooltip: 'Claude / Codex', onTap: () => shell._newTabMenu(c))),
        const SizedBox(width: 2),
        KeyedSubtree(
          key: shell._historyKey,
          child: IconBtn(Codicons.history, tooltip: '${S.history} (Ctrl+H)', onTap: shell.showHistory),
        ),
        const SizedBox(width: 2),
        IconBtn(Codicons.folderOpened, tooltip: '${S.openFolder} (Ctrl+O)', onTap: shell.openFolder),
        if (shell.widget.headerExtra != null) ...[
          const SizedBox(width: 2),
          shell.widget.headerExtra!(context),
        ],
        const SizedBox(width: 6),
      ]),
    );
  }
}

class _Tab extends StatefulWidget {
  const _Tab({required this.session, required this.active, required this.onTap, required this.onClose});
  final ChatSession session;
  final bool active;
  final VoidCallback onTap, onClose;
  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final waiting = s.pendingRequests.isNotEmpty;
    Widget status;
    if (waiting) {
      status = Container(width: 8, height: 8, decoration: BoxDecoration(color: P.accent, shape: BoxShape.circle));
    } else if (s.isBusy) {
      status = const ClaudeSpinner(size: 12);
    } else {
      status = Icon(s.agent == 'codex' ? Codicons.hubot : Codicons.comment, size: 13, color: widget.active ? P.fgMuted : P.fgFaint);
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onTertiaryTapUp: (_) => widget.onClose(),
        child: Tooltip(
          message: '${s.title ?? S.newChat}\n${s.cwd}',
          waitDuration: const Duration(milliseconds: 700),
          child: Container(
            constraints: const BoxConstraints(minWidth: 110, maxWidth: 220),
            padding: const EdgeInsets.only(left: 10, right: 4),
            decoration: BoxDecoration(
              color: widget.active ? P.panelBg == P.sideBg ? P.bg : P.panelBg : (_hover ? P.hover : P.sideBg),
              border: Border(
                top: BorderSide(color: widget.active ? P.focus : Colors.transparent, width: 1),
                right: BorderSide(color: P.border),
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(width: 14, child: Center(child: status)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  s.title ?? S.newChat,
                  overflow: TextOverflow.ellipsis,
                  style: uiText(size: 12.5, color: widget.active ? P.fg : P.fgMuted),
                ),
              ),
              const SizedBox(width: 4),
              Opacity(
                opacity: widget.active || _hover ? 1 : 0,
                child: IconBtn(Codicons.close, size: 14, tooltip: '${S.close} (Ctrl+W)', onTap: widget.onClose),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ history

Future<void> _showHistory(BuildContext anchor, ShellState shell) async {
  final box = anchor.findRenderObject() as RenderBox;
  final pos = box.localToGlobal(Offset(box.size.width, box.size.height));
  final picked = await showDialog<SessionInfo>(
    context: anchor,
    barrierColor: Colors.transparent,
    builder: (context) => Stack(children: [
      Positioned(
        top: pos.dy + 4,
        right: (MediaQuery.of(context).size.width - pos.dx).clamp(8, 4000).toDouble(),
        child: _HistoryPanel(cwd: shell.current.cwd),
      ),
    ]),
  );
  if (picked != null) await shell.resume(picked);
}

class _HistoryPanel extends StatefulWidget {
  const _HistoryPanel({required this.cwd});
  final String cwd;
  @override
  State<_HistoryPanel> createState() => _HistoryPanelState();
}

class _HistoryPanelState extends State<_HistoryPanel> {
  late final List<SessionInfo> _all = listSessions(widget.cwd);
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final list = q.isEmpty ? _all : _all.where((s) => (s.title ?? '').toLowerCase().contains(q)).toList();
    return Material(
      color: P.menuBg,
      elevation: 8,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: P.menuBorder),
        borderRadius: BorderRadius.circular(6),
      ),
      child: SizedBox(
        width: 420,
        height: 460,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
            child: Text(S.history, style: uiText(weight: FontWeight.w600)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: TextField(
              autofocus: true,
              inputFormatters: [noControlChars],
              style: uiText(),
              onChanged: (v) => setState(() => _q = v),
              onSubmitted: (_) {
                if (list.isNotEmpty) Navigator.of(context).pop(list.first);
              },
              decoration: InputDecoration(
                isDense: true,
                hintText: S.search,
                hintStyle: uiText(color: P.fgFaint),
                prefixIcon: Icon(Codicons.search, size: 16, color: P.fgMuted),
                prefixIconConstraints: const BoxConstraints(minWidth: 30),
                filled: true,
                fillColor: P.inputBg,
                contentPadding: const EdgeInsets.symmetric(vertical: 7),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: P.inputBorder)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: P.inputBorder)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: P.focus)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: list.isEmpty
                ? Center(child: Text(S.historyEmpty, style: uiText(color: P.fgMuted)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final s = list[i];
                      return HoverBox(
                        onTap: () => Navigator.of(context).pop(s),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: Row(children: [
                          Expanded(
                            child: Text(s.title ?? s.id, maxLines: 1, overflow: TextOverflow.ellipsis, style: uiText()),
                          ),
                          const SizedBox(width: 10),
                          Text(S.ago(s.modified), style: uiText(size: 12, color: P.fgFaint)),
                        ]),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}
