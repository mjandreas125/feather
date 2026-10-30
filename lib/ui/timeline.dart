import 'package:flutter/material.dart';

import '../claude/chat_items.dart';
import '../l10n.dart';
import '../theme.dart';
import 'markdown.dart';
import 'tools.dart';
import 'widgets.dart';
import '../codicons.dart';

/// Draws one timeline entry: a status dot in a left gutter, a thin connecting line,
/// and the content. Mirrors the look of the Claude Code panel.
class TimelineEntry extends StatelessWidget {
  const TimelineEntry({
    super.key,
    required this.child,
    this.dot,
    this.lineAbove = true,
    this.lineBelow = true,
    this.dotTop = 6,
  });
  final Widget child;
  final Color? dot;
  final bool lineAbove, lineBelow;
  final double dotTop;

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      if (lineAbove || lineBelow)
        Positioned(
          left: 7.5,
          top: lineAbove ? 0 : dotTop + 4,
          bottom: lineBelow ? 0 : null,
          height: lineBelow ? null : dotTop + 4,
          child: Container(width: 1, color: P.inputBorder),
        ),
      if (dot != null)
        Positioned(
          left: 4,
          top: dotTop + 1,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: dot,
              shape: BoxShape.circle,
              border: Border.all(color: P.bg, width: 1.5),
            ),
          ),
        ),
      Padding(padding: const EdgeInsets.only(left: 20), child: child),
    ]);
  }
}

class UserBubble extends StatelessWidget {
  const UserBubble(this.item, {super.key});
  final UserItem item;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: P.inputBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: P.inputBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (item.images.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final img in item.images)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.memory(img.bytes, height: 64, fit: BoxFit.cover, cacheHeight: 128),
                ),
            ]),
          ),
        if (item.text.isNotEmpty) Text(item.text, style: uiText()),
      ]),
    );
  }
}

class ThinkingRow extends StatefulWidget {
  const ThinkingRow(this.item, {super.key});
  final ThinkingItem item;
  @override
  State<ThinkingRow> createState() => _ThinkingRowState();
}

class _ThinkingRowState extends State<ThinkingRow> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    final t = widget.item;
    final label = t.streaming
        ? S.thinking
        : t.took != null && t.took!.inSeconds > 0
            ? S.thoughtFor(t.took!.inSeconds)
            : S.thinking;
    final hasText = t.text.trim().isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      HoverBox(
        onTap: hasText ? () => setState(() => _open = !_open) : null,
        cursor: hasText ? SystemMouseCursors.click : SystemMouseCursors.basic,
        padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: uiText(color: P.fgMuted).copyWith(fontStyle: FontStyle.italic)),
          if (hasText)
            Icon(_open ? Codicons.chevronDown : Codicons.chevronRight, size: 16, color: P.fgMuted),
        ]),
      ),
      if (_open && hasText)
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 4),
          child: Text(t.text.trim(), style: uiText(color: P.fgMuted).copyWith(fontStyle: FontStyle.italic)),
        ),
    ]);
  }
}

class ToolRow extends StatefulWidget {
  const ToolRow(this.item, {super.key, required this.cwd, this.depth = 0});
  final ToolItem item;
  final String cwd;
  final int depth;
  @override
  State<ToolRow> createState() => _ToolRowState();
}

class _ToolRowState extends State<ToolRow> {
  late bool _open = widget.item.expanded || toolStartsExpanded(widget.item);

  @override
  Widget build(BuildContext context) {
    final t = widget.item;
    final summary = toolSummary(t, widget.cwd);
    final stats = editStats(t);
    final isAgent = t.name == 'Task' || t.name == 'Agent';
    final alwaysBody = t.name == 'TodoWrite';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HoverBox(
        onTap: alwaysBody
            ? null
            : () => setState(() {
                  _open = !_open;
                  t.expanded = _open;
                }),
        padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 2),
        child: Row(children: [
          Text(t.displayName, style: uiText(weight: FontWeight.w600)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: monoText(color: P.fgMuted),
            ),
          ),
          if (stats != null) ...[
            const SizedBox(width: 6),
            Text(stats.split(' ').first, style: monoText(color: P.added)),
            const SizedBox(width: 4),
            Text(stats.split(' ').last, style: monoText(color: P.removed)),
          ],
          if (t.status == ToolStatus.running && !isAgent) ...[
            const SizedBox(width: 6),
            const ClaudeSpinner(size: 11),
          ],
          if (!alwaysBody)
            Icon(_open ? Codicons.chevronDown : Codicons.chevronRight, size: 16, color: P.fgFaint),
        ]),
      ),
      if (isAgent) _agentChildren(t),
      if (_open || alwaysBody)
        Padding(padding: const EdgeInsets.only(top: 2, bottom: 4), child: ToolBody(t))
      else if (t.status == ToolStatus.error && (t.resultText ?? '').isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 2, left: 2),
          child: Text(
            t.resultText!.trim().split('\n').take(3).join('\n'),
            style: monoText(color: P.error, size: 11.5),
          ),
        ),
    ]);
  }

  Widget _agentChildren(ToolItem t) {
    final kids = t.children;
    if (kids.isEmpty) return const SizedBox.shrink();
    final tools = kids.whereType<ToolItem>().toList();
    if (!_open) {
      // Collapsed: show only the latest step, like the panel does.
      final last = kids.lastWhere((k) => k is ToolItem || k is TextItem, orElse: () => kids.last);
      return Padding(
        padding: const EdgeInsets.only(left: 2, top: 1),
        child: Row(children: [
          Text('${S.subagentSteps(tools.length)} · ', style: uiText(size: 12, color: P.fgFaint)),
          Expanded(
            child: Text(
              last is ToolItem
                  ? '${last.displayName} ${toolSummary(last, widget.cwd)}'
                  : last is TextItem
                      ? last.text.split('\n').first
                      : '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: uiText(size: 12, color: P.fgFaint),
            ),
          ),
        ]),
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: 4, left: 2),
      padding: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(border: Border(left: BorderSide(color: P.inputBorder))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final k in kids)
          if (k is ToolItem)
            Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: ToolRow(k, cwd: widget.cwd, depth: widget.depth + 1))
          else if (k is TextItem && k.text.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: MarkdownView(k.text, fontSize: 12.5),
            ),
      ]),
    );
  }
}

class NoticeRow extends StatelessWidget {
  const NoticeRow(this.item, {super.key});
  final NoticeItem item;
  @override
  Widget build(BuildContext context) {
    final color = switch (item.kind) {
      NoticeKind.error => P.error,
      NoticeKind.interrupted => P.warn,
      _ => P.fgMuted,
    };
    if (item.kind == NoticeKind.compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Divider(color: P.border, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(item.text, style: uiText(size: 12, color: P.fgFaint)),
          ),
          Expanded(child: Divider(color: P.border, height: 1)),
        ]),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(item.text, style: uiText(color: color)),
      if (item.detail != null) OutputView(item.detail!, error: item.kind == NoticeKind.error, maxLines: 10),
    ]);
  }
}

/// Resolved question/plan requests stay in the timeline as a compact record.
class ResolvedRequestRow extends StatelessWidget {
  const ResolvedRequestRow(this.item, {super.key});
  final RequestItem item;
  @override
  Widget build(BuildContext context) {
    final state = switch (item.state) {
      RequestState.allowed => item.kind == RequestKind.question ? S.answered : S.allowed,
      RequestState.denied => S.denied,
      RequestState.cancelled => S.cancelled,
      RequestState.pending => '',
    };
    if (item.kind == RequestKind.plan) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text(S.planTitle, style: uiText(weight: FontWeight.w600)),
          const SizedBox(width: 8),
          Pill(state, color: item.state == RequestState.allowed ? P.ok : P.fgMuted),
        ]),
        Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: P.border),
            borderRadius: BorderRadius.circular(5),
          ),
          child: MarkdownView('${item.input['plan'] ?? ''}'),
        ),
        if (item.summary != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('“${item.summary}”', style: uiText(color: P.fgMuted)),
          ),
      ]);
    }
    if (item.kind == RequestKind.question) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('AskUserQuestion', style: uiText(weight: FontWeight.w600)),
          const SizedBox(width: 8),
          Pill(state, color: item.state == RequestState.allowed ? P.ok : P.fgMuted),
        ]),
        if (item.summary != null)
          Padding(
            padding: const EdgeInsets.only(top: 3, left: 2),
            child: Text(item.summary!, style: uiText(color: P.fgMuted)),
          ),
      ]);
    }
    return const SizedBox.shrink();
  }
}
