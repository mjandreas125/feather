import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../claude/chat_items.dart';
import '../l10n.dart';
import '../theme.dart';
import 'markdown.dart';
import 'widgets.dart';
import '../codicons.dart';

/// Short one-line description of what a tool call does, shown next to its name.
String toolSummary(ToolItem t, String cwd) {
  final i = t.input;
  String rel(String? path) {
    if (path == null || path.isEmpty) return '';
    final r = p.isWithin(cwd, path) ? p.relative(path, from: cwd) : path;
    return r;
  }

  String? str(String k) => i[k] is String ? i[k] as String : null;
  switch (t.name) {
    case 'Bash':
    case 'PowerShell':
    case 'Shell':
      return (str('command') ?? '').split('\n').first;
    case 'Patch':
      return rel(str('file_path'));
    case 'Read':
      final path = rel(str('file_path'));
      final off = i['offset'], lim = i['limit'];
      return off != null || lim != null ? '$path  (${off ?? 1}–${(off is num ? off : 1) + (lim is num ? lim : 0)})' : path;
    case 'Edit':
    case 'MultiEdit':
    case 'Write':
    case 'NotebookEdit':
      return rel(str('file_path') ?? str('notebook_path'));
    case 'Glob':
      return str('pattern') ?? '';
    case 'Grep':
      final path = str('path');
      return '${str('pattern') ?? ''}${path != null ? '  in ${rel(path)}' : ''}';
    case 'WebFetch':
      return str('url') ?? '';
    case 'WebSearch':
      return str('query') ?? '';
    case 'Task':
    case 'Agent':
      return str('description') ?? str('subagent_type') ?? '';
    case 'Skill':
      return str('skill') ?? str('command') ?? '';
    case 'ToolSearch':
      return str('query') ?? '';
    case 'TodoWrite':
      return '';
    default:
      for (final v in i.values) {
        if (v is String && v.isNotEmpty) return v.split('\n').first;
      }
      if (!t.inputComplete && t.partialJson.isNotEmpty) {
        final m = RegExp(r'"[^"]+"\s*:\s*"((?:[^"\\]|\\.)*)').firstMatch(t.partialJson);
        if (m != null) return m.group(1)!;
      }
      return '';
  }
}

bool toolStartsExpanded(ToolItem t) =>
    const {'Edit', 'MultiEdit', 'Write', 'TodoWrite', 'NotebookEdit', 'Patch'}.contains(t.name);

// ------------------------------------------------------------------ diff

class DiffLine {
  DiffLine(this.kind, this.text, {this.oldNo, this.newNo});
  final String kind; // '+', '-', ' ', '@'
  final String text;
  final int? oldNo, newNo;
}

/// Line diff via LCS (fine for the small hunks an edit produces).
List<DiffLine> diffLines(String a, String b) {
  final x = a.isEmpty ? <String>[] : a.split('\n');
  final y = b.isEmpty ? <String>[] : b.split('\n');
  if (x.length * y.length > 250000) {
    return [for (final l in x) DiffLine('-', l), for (final l in y) DiffLine('+', l)];
  }
  final n = x.length, m = y.length;
  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      dp[i][j] = x[i] == y[j] ? dp[i + 1][j + 1] + 1 : math.max(dp[i + 1][j], dp[i][j + 1]);
    }
  }
  final out = <DiffLine>[];
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (x[i] == y[j]) {
      out.add(DiffLine(' ', x[i], oldNo: i + 1, newNo: j + 1));
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      out.add(DiffLine('-', x[i], oldNo: i + 1));
      i++;
    } else {
      out.add(DiffLine('+', y[j], newNo: j + 1));
      j++;
    }
  }
  while (i < n) {
    out.add(DiffLine('-', x[i], oldNo: i + 1));
    i++;
  }
  while (j < m) {
    out.add(DiffLine('+', y[j], newNo: j + 1));
    j++;
  }
  return out;
}

/// Diff for an Edit/MultiEdit/Write call. Prefers the CLI's structuredPatch (real line
/// numbers) and falls back to diffing the tool input.
/// Lines of a unified diff ("@@ -a,b +c,d @@" hunks), as produced by Codex.
List<DiffLine> parseUnifiedDiff(String diff) {
  final out = <DiffLine>[];
  var o = 0, n = 0;
  for (final l in diff.split('\n')) {
    if (l.startsWith('@@')) {
      final m = RegExp(r'-(\d+)(?:,\d+)? \+(\d+)').firstMatch(l);
      if (m != null) {
        o = int.parse(m.group(1)!);
        n = int.parse(m.group(2)!);
      }
      if (out.isNotEmpty) out.add(DiffLine('@', '⋯'));
    } else if (l.startsWith('+++') || l.startsWith('---') || l.startsWith('diff ') || l.startsWith('index ')) {
      continue;
    } else if (l.startsWith('+')) {
      out.add(DiffLine('+', l.substring(1), newNo: n++));
    } else if (l.startsWith('-')) {
      out.add(DiffLine('-', l.substring(1), oldNo: o++));
    } else if (l.startsWith(' ')) {
      out.add(DiffLine(' ', l.substring(1), oldNo: o++, newNo: n++));
    }
  }
  return out;
}

List<DiffLine> diffForTool(ToolItem t) {
  if (t.name == 'Patch') return parseUnifiedDiff('${t.input['unified_diff'] ?? ''}');
  final s = t.structured;
  if (s is Map && s['structuredPatch'] is List && (s['structuredPatch'] as List).isNotEmpty) {
    final out = <DiffLine>[];
    for (final h in s['structuredPatch'] as List) {
      if (h is! Map) continue;
      var o = (h['oldStart'] as num?)?.toInt() ?? 1;
      var n = (h['newStart'] as num?)?.toInt() ?? 1;
      if (out.isNotEmpty) out.add(DiffLine('@', '⋯'));
      for (final raw in (h['lines'] as List? ?? [])) {
        final l = '$raw';
        final k = l.isEmpty ? ' ' : l[0];
        final text = l.isEmpty ? '' : l.substring(1);
        if (k == '-') {
          out.add(DiffLine('-', text, oldNo: o++));
        } else if (k == '+') {
          out.add(DiffLine('+', text, newNo: n++));
        } else if (k == '\\') {
          continue;
        } else {
          out.add(DiffLine(' ', text, oldNo: o++, newNo: n++));
        }
      }
    }
    return out;
  }
  final i = t.input;
  if (t.name == 'Write') {
    final content = '${i['content'] ?? ''}';
    final lines = content.split('\n');
    return [for (var k = 0; k < lines.length; k++) DiffLine('+', lines[k], newNo: k + 1)];
  }
  if (t.name == 'MultiEdit' && i['edits'] is List) {
    final out = <DiffLine>[];
    for (final e in i['edits'] as List) {
      if (e is! Map) continue;
      if (out.isNotEmpty) out.add(DiffLine('@', '⋯'));
      out.addAll(diffLines('${e['old_string'] ?? ''}', '${e['new_string'] ?? ''}'));
    }
    return out;
  }
  return diffLines('${i['old_string'] ?? ''}', '${i['new_string'] ?? ''}');
}

class DiffView extends StatefulWidget {
  const DiffView({super.key, required this.lines, this.path, this.maxLines = 24});
  final List<DiffLine> lines;
  final String? path;
  final int maxLines;
  @override
  State<DiffView> createState() => _DiffViewState();
}

class _DiffViewState extends State<DiffView> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final lines = widget.lines;
    final shown = _all || lines.length <= widget.maxLines ? lines : lines.sublist(0, widget.maxLines);
    final lang = widget.path == null ? null : CodeHighlighter.forPath(widget.path!);
    final noWidth = math.max(2, '${lines.fold<int>(0, (m, l) => math.max(m, math.max(l.oldNo ?? 0, l.newNo ?? 0)))}'.length);
    final base = monoText();
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 2),
      decoration: BoxDecoration(
        color: P.codeBg,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: P.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: box.maxWidth),
            child: IntrinsicWidth(
            child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final l in shown)
                Container(
                  color: l.kind == '+' ? P.addedBg : l.kind == '-' ? P.removedBg : null,
                  padding: const EdgeInsets.only(right: 12),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(
                      width: noWidth * 7.5 + 12,
                      child: Text(
                        l.kind == '@' ? '' : '${l.kind == '+' ? l.newNo : l.oldNo ?? ''}',
                        textAlign: TextAlign.right,
                        style: monoText(color: P.fgFaint),
                      ),
                    ),
                    SizedBox(
                      width: 18,
                      child: Text(l.kind == ' ' || l.kind == '@' ? '' : l.kind,
                          textAlign: TextAlign.center,
                          style: monoText(color: l.kind == '+' ? P.added : P.removed)),
                    ),
                    l.kind == '@'
                        ? Text(l.text, style: monoText(color: P.fgFaint))
                        : Text.rich(CodeHighlighter.instance.highlight(l.text, lang, base), softWrap: false),
                  ]),
                ),
            ]),
          ),
          ),
          ),
          ),
        ),
        if (lines.length > widget.maxLines)
          HoverBox(
            onTap: () => setState(() => _all = !_all),
            radius: 0,
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(_all ? S.showLess : '${S.showMore} (${lines.length - widget.maxLines})',
                textAlign: TextAlign.center, style: uiText(size: 12, color: P.link)),
          ),
      ]),
    );
  }
}

// ------------------------------------------------------------------ output

/// Monospace output (command results etc.), collapsed to [maxLines].
class OutputView extends StatefulWidget {
  const OutputView(this.text, {super.key, this.maxLines = 16, this.error = false, this.label});
  final String text;
  final int maxLines;
  final bool error;
  final String? label;
  @override
  State<OutputView> createState() => _OutputViewState();
}

class _OutputViewState extends State<OutputView> {
  bool _all = false;
  @override
  Widget build(BuildContext context) {
    var text = widget.text.trimRight();
    if (text.isEmpty) text = S.noOutput;
    final lines = text.split('\n');
    final cut = !_all && lines.length > widget.maxLines;
    final shown = cut ? lines.sublist(0, widget.maxLines).join('\n') : text;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: P.codeBg,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: widget.error ? P.error.withValues(alpha: 0.45) : P.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Stack(children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(10, 6, 30, 6),
            child: Text(shown, softWrap: false, style: monoText(color: widget.error ? P.error : P.fg)),
          ),
          Positioned(right: 2, top: 2, child: CopyButton(() => widget.text)),
        ]),
        if (lines.length > widget.maxLines)
          HoverBox(
            onTap: () => setState(() => _all = !_all),
            radius: 0,
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(_all ? S.showLess : '${S.showMore} (${lines.length - widget.maxLines})',
                textAlign: TextAlign.center, style: uiText(size: 12, color: P.link)),
          ),
      ]),
    );
  }
}

// ------------------------------------------------------------------ todo list

class TodoView extends StatelessWidget {
  const TodoView(this.todos, {super.key});
  final List<dynamic> todos;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final t in todos)
          if (t is Map)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 6),
                  child: Icon(
                    t['status'] == 'completed'
                        ? Codicons.passFilled
                        : t['status'] == 'in_progress'
                            ? Codicons.circleLargeFilled
                            : Codicons.circleLarge,
                    size: 15,
                    color: t['status'] == 'completed'
                        ? P.ok
                        : t['status'] == 'in_progress'
                            ? P.accent
                            : P.fgMuted,
                  ),
                ),
                Expanded(
                  child: Text(
                    '${t['status'] == 'in_progress' ? (t['activeForm'] ?? t['content']) : t['content']}',
                    style: uiText(
                      color: t['status'] == 'completed' ? P.fgMuted : P.fg,
                      weight: t['status'] == 'in_progress' ? FontWeight.w600 : null,
                    ).copyWith(
                        decoration: t['status'] == 'completed' ? TextDecoration.lineThrough : null,
                        decorationColor: P.fgMuted),
                  ),
                ),
              ]),
            ),
      ]),
    );
  }
}

/// Expanded body of a tool row.
class ToolBody extends StatelessWidget {
  const ToolBody(this.t, {super.key});
  final ToolItem t;

  @override
  Widget build(BuildContext context) {
    final i = t.input;
    final result = t.resultText;
    final isErr = t.status == ToolStatus.error || t.status == ToolStatus.denied;
    switch (t.name) {
      case 'Edit':
      case 'MultiEdit':
      case 'Write':
      case 'Patch':
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (t.inputComplete) DiffView(lines: diffForTool(t), path: '${i['file_path'] ?? ''}'),
          if (isErr && result != null) OutputView(result, error: true, maxLines: 6),
        ]);
      case 'TodoWrite':
        return TodoView(i['todos'] is List ? i['todos'] as List : const []);
      case 'Bash':
      case 'PowerShell':
      case 'Shell':
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CodeBlock(code: '${i['command'] ?? ''}', language: t.name == 'Bash' ? 'bash' : 'powershell'),
          if (result != null) OutputView(result, error: isErr),
        ]);
      case 'Read':
        return result == null ? const SizedBox.shrink() : OutputView(_stripLineNumbers(result), error: isErr, maxLines: 12);
      default:
        final pretty = const JsonEncoder.withIndent('  ').convert(i);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (i.isNotEmpty) CodeBlock(code: pretty, language: 'json', maxHeight: 220),
          if (result != null) OutputView(result, error: isErr),
        ]);
    }
  }

  static String _stripLineNumbers(String s) =>
      s.split('\n').map((l) => l.replaceFirst(RegExp(r'^\s*\d+[→\t]'), '')).join('\n');
}

/// "+12 −3" for edit rows.
String? editStats(ToolItem t) {
  if (!const {'Edit', 'MultiEdit', 'Write', 'Patch'}.contains(t.name) || !t.inputComplete) return null;
  final d = diffForTool(t);
  final a = d.where((l) => l.kind == '+').length, r = d.where((l) => l.kind == '-').length;
  return S.linesAddedRemoved(a, r);
}
