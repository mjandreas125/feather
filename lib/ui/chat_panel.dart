import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../claude/chat_items.dart';
import '../claude/session.dart';
import '../l10n.dart';
import '../theme.dart';
import 'composer.dart';
import 'markdown.dart';
import 'requests.dart';
import 'timeline.dart';
import 'widgets.dart';
import '../codicons.dart';

class ChatPanel extends StatefulWidget {
  const ChatPanel({super.key, required this.session, this.onOpenPath, this.active = true});
  final ChatSession session;
  final void Function(String path)? onOpenPath;
  final bool active;
  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _scroll = ScrollController();
  final _composerKey = GlobalKey<ComposerState>();
  /// Follow new output while the user is at the bottom; stop following once they scroll up.
  bool _stick = true;
  bool _jumping = false;

  ChatSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    s.addListener(_changed);
  }

  void _toBottom() {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    if ((_scroll.offset - max).abs() < 0.5) return;
    _jumping = true;
    _scroll.jumpTo(max);
    _jumping = false;
    // Lazily built rows can change the extent once laid out; settle on the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_stick && _scroll.hasClients && _scroll.offset < _scroll.position.maxScrollExtent - 0.5) {
        _jumping = true;
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
        _jumping = false;
      }
    });
  }

  bool _onScroll(Notification n) {
    if (n is ScrollMetricsNotification) {
      if (_stick) WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());
      return false;
    }
    if (n is ScrollUpdateNotification && !_jumping) {
      final m = n.metrics;
      final atBottom = m.pixels >= m.maxScrollExtent - 40;
      if (atBottom != _stick) setState(() => _stick = atBottom);
    }
    return false;
  }

  @override
  void didUpdateWidget(covariant ChatPanel old) {
    super.didUpdateWidget(old);
    if (!identical(old.session, s)) {
      old.session.removeListener(_changed);
      s.addListener(_changed);
    }
    if (widget.active && !old.active) {
      // Tab switched to: put the cursor back in this tab's input box.
      WidgetsBinding.instance.addPostFrameCallback((_) => _composerKey.currentState?.focus.requestFocus());
    }
  }

  @override
  void dispose() {
    s.removeListener(_changed);
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (_stick) WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());
  }

  @override
  Widget build(BuildContext context) {
    final pending = s.pendingRequests;
    return Container(
      color: P.panelBg,
      child: Column(children: [
        Expanded(child: s.status == SessionStatus.notFound ? _notFound() : _timeline()),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: pending.isNotEmpty
                  ? RequestDock(session: s, request: pending.first, queued: pending.length - 1)
                  : Composer(key: _composerKey, session: s),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _notFound() => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Codicons.terminal, size: 40, color: P.fgFaint),
            const SizedBox(height: 12),
            Text(S.claudeNotFound.replaceAll('Claude Code', s.agentName), style: uiText(size: 16, weight: FontWeight.w600)),
            const SizedBox(height: 8),
            MarkdownView(s.agent == 'codex' ? S.codexNotFoundHint : S.claudeNotFoundHint),
            const SizedBox(height: 14),
            VsButton(S.restart, onTap: () => s.start()),
          ]),
        ),
      );

  Widget _timeline() {
    final entries = _buildEntries();
    if (entries.isEmpty) return _empty();
    return Stack(children: [
      NotificationListener<Notification>(
        onNotification: _onScroll,
        child: SelectionArea(
          child: Scrollbar(
            controller: _scroll,
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
              itemCount: entries.length,
              itemBuilder: (context, i) {
                final e = entries[i];
                // Full column width even for short replies (otherwise they get centred).
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: SizedBox(
                      width: double.infinity,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(14, e.gapAbove, 18, 0),
                        child: e.widget,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
      if (!_stick)
        Positioned(
          right: 22,
          bottom: 10,
          child: Material(
            color: P.inputBg,
            shape: CircleBorder(side: BorderSide(color: P.inputBorder)),
            child: IconBtn(Codicons.arrowDown, onTap: () {
              setState(() => _stick = true);
              _scroll.animateTo(_scroll.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
            }),
          ),
        ),
    ]);
  }

  Widget _empty() {
    final folder = p.basename(s.cwd);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (s.status == SessionStatus.starting)
              const ClaudeSpinner(size: 30)
            else
              Image.asset('assets/feather.png', width: 44, height: 44, filterQuality: FilterQuality.medium),
            const SizedBox(height: 14),
            Text(S.emptyTitle, style: uiText(size: 18, weight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(S.emptyHint.replaceAll('Claude', s.agentName), textAlign: TextAlign.center, style: uiText(color: P.fgMuted)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: P.inputBg, borderRadius: BorderRadius.circular(4)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Codicons.folder, size: 14, color: P.fgMuted),
                const SizedBox(width: 6),
                Flexible(
                  child: Tooltip(
                    message: s.cwd,
                    child: Text(folder.isEmpty ? s.cwd : folder,
                        overflow: TextOverflow.ellipsis, style: monoText(color: P.fgMuted)),
                  ),
                ),
              ]),
            ),
            if (s.status == SessionStatus.starting) ...[
              const SizedBox(height: 10),
              Text(S.starting, style: uiText(size: 12, color: P.fgFaint)),
            ],
          ]),
        ),
      ),
    );
  }

  List<_Entry> _buildEntries() {
    final out = <_Entry>[];
    ChatItem? prev;
    for (final it in s.items) {
      Widget? w;
      Color? dot;
      var timeline = true;
      switch (it) {
        case UserItem():
          w = UserBubble(it);
          timeline = false;
        case TextItem():
          if (it.text.trim().isEmpty) continue;
          w = MarkdownView(it.text, onOpenPath: widget.onOpenPath);
          dot = P.fg;
        case ThinkingItem():
          if (!it.streaming && it.text.trim().isEmpty) continue;
          w = ThinkingRow(it);
          dot = P.fgFaint;
        case ToolItem():
          w = ToolRow(it, cwd: s.cwd);
          dot = switch (it.status) {
            ToolStatus.running => P.fgFaint,
            ToolStatus.done => P.ok,
            ToolStatus.error => P.error,
            ToolStatus.denied => P.warn,
          };
        case RequestItem():
          if (it.state == RequestState.pending || it.kind == RequestKind.permission) continue;
          w = ResolvedRequestRow(it);
          dot = it.state == RequestState.allowed ? P.ok : P.fgFaint;
        case NoticeItem():
          w = NoticeRow(it);
          dot = it.kind == NoticeKind.compact ? null : (it.kind == NoticeKind.error ? P.error : P.warn);
          if (it.kind == NoticeKind.compact) timeline = false;
      }
      if (w == null) continue;
      final gap = prev == null ? 0.0 : (it is UserItem ? 16.0 : (prev is UserItem ? 12.0 : 7.0));
      out.add(_Entry(w, gapAbove: gap, timeline: timeline, dot: dot, key: it));
      prev = it;
    }
    if (s.isBusy && s.pendingRequests.isEmpty) {
      out.add(_Entry(_BusyRow(s), gapAbove: out.isEmpty ? 0 : 8, timeline: false));
    }
    // Connect consecutive timeline entries with the gutter line.
    for (var i = 0; i < out.length; i++) {
      final e = out[i];
      if (!e.timeline) continue;
      final above = i > 0 && out[i - 1].timeline;
      final below = i < out.length - 1 && out[i + 1].timeline;
      e.widget = TimelineEntry(
        key: e.key == null ? null : ObjectKey(e.key),
        dot: e.dot,
        lineAbove: above,
        lineBelow: below,
        child: e.widget,
      );
    }
    // Gaps between connected entries must not break the line: move them inside.
    for (var i = 0; i < out.length; i++) {
      final e = out[i];
      if (e.timeline && i > 0 && out[i - 1].timeline && e.gapAbove > 0) {
        final g = e.gapAbove;
        e.gapAbove = 0;
        e.widget = _GapLine(gap: g, child: e.widget);
      }
    }
    return out;
  }
}

class _Entry {
  _Entry(this.widget, {required this.gapAbove, required this.timeline, this.dot, this.key});
  Widget widget;
  double gapAbove;
  final bool timeline;
  final Color? dot;
  final Object? key;
}

/// A gap that keeps the timeline line continuous.
class _GapLine extends StatelessWidget {
  const _GapLine({required this.gap, required this.child});
  final double gap;
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: gap,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 7.5),
              child: Container(width: 1, color: P.inputBorder),
            ),
          ),
        ),
        child,
      ]);
}

class _BusyRow extends StatelessWidget {
  const _BusyRow(this.s);
  final ChatSession s;
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      const ClaudeSpinner(size: 14),
      const SizedBox(width: 6),
      Text(s.statusText ?? S.working, style: uiText(color: P.accent)),
      if (s.busySince != null) ...[
        const SizedBox(width: 8),
        ElapsedText(s.busySince!, style: uiText(size: 12, color: P.fgFaint)),
        Text(' · Esc — ${S.stop.toLowerCase()}', style: uiText(size: 12, color: P.fgFaint)),
      ],
    ]);
  }
}
