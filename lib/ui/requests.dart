import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../claude/chat_items.dart';
import '../claude/session.dart';
import '../keys.dart';
import '../l10n.dart';
import '../theme.dart';
import 'markdown.dart';
import 'tools.dart';
import 'widgets.dart';
import '../codicons.dart';

/// The card shown above the composer while Claude waits for the user.
class RequestDock extends StatelessWidget {
  const RequestDock({super.key, required this.session, required this.request, required this.queued});
  final ChatSession session;
  final RequestItem request;
  final int queued;

  @override
  Widget build(BuildContext context) {
    final card = switch (request.kind) {
      RequestKind.permission => PermissionCard(key: ValueKey(request.requestId), session: session, r: request),
      RequestKind.question => QuestionCard(key: ValueKey(request.requestId), session: session, r: request),
      RequestKind.plan => PlanCard(key: ValueKey(request.requestId), session: session, r: request),
    };
    return Container(
      decoration: BoxDecoration(
        color: P.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: P.focus.withValues(alpha: 0.75)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: P.dark ? 0.35 : 0.08), blurRadius: 12)],
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        if (queued > 0)
          Align(
            alignment: Alignment.centerRight,
            child: Pill('+$queued', color: P.fgMuted),
          ),
        card,
      ]),
    );
  }
}

// ------------------------------------------------------------------ option list

class _Option {
  _Option(this.label, {this.hint, this.onPick, this.field = false, this.checked});
  final String label;
  final String? hint;
  final VoidCallback? onPick;
  final bool field; // "tell Claude what to do instead" style input
  final bool? checked; // multi-select checkbox state
}

/// Numbered options navigable with ↑/↓, digits and Enter (by physical key).
class _OptionList extends StatefulWidget {
  const _OptionList({
    super.key,
    required this.options,
    this.onFieldSubmit,
    this.onEscape,
    this.onHover,
  });
  final List<_Option> options;
  final void Function(String text)? onFieldSubmit;
  final VoidCallback? onEscape;
  final void Function(int index)? onHover;
  @override
  State<_OptionList> createState() => _OptionListState();
}

class _OptionListState extends State<_OptionList> {
  int _sel = 0;
  final _focus = FocusNode(debugLabel: 'options');
  final _fieldFocus = FocusNode(debugLabel: 'option-field');
  final _field = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _fieldFocus.dispose();
    _field.dispose();
    super.dispose();
  }

  void _activate(int i) {
    final o = widget.options[i];
    if (o.field) {
      setState(() => _sel = i);
      _fieldFocus.requestFocus();
      if (_field.text.trim().isNotEmpty) widget.onFieldSubmit?.call(_field.text);
      return;
    }
    o.onPick?.call();
  }

  void _select(int i) {
    setState(() => _sel = i);
    widget.onHover?.call(i);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (_fieldFocus.hasFocus) {
      if (isEscape(e)) {
        _focus.requestFocus();
        return KeyEventResult.handled;
      }
      if (isUp(e) && _field.text.isEmpty) {
        _focus.requestFocus();
        _select((_sel - 1).clamp(0, widget.options.length - 1));
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final d = keyDigit(e);
    if (d != null && d <= widget.options.length && !HardwareKeyboard.instance.isControlPressed) {
      _select(d - 1);
      _activate(d - 1);
      return KeyEventResult.handled;
    }
    if (isDown(e)) {
      _select((_sel + 1) % widget.options.length);
      if (widget.options[_sel].field) _fieldFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (isUp(e)) {
      _select((_sel - 1 + widget.options.length) % widget.options.length);
      return KeyEventResult.handled;
    }
    if (isEnter(e) && HardwareKeyboard.instance.isControlPressed) {
      return KeyEventResult.ignored; // Ctrl+Enter = submit, handled by the card
    }
    if (isEnter(e) || isSpace(e)) {
      _activate(_sel);
      return KeyEventResult.handled;
    }
    if (isEscape(e)) {
      widget.onEscape?.call();
      return KeyEventResult.handled;
    }
    // Typing while the list is focused goes straight into the free-text option.
    final ch = e.character;
    final fieldIndex = widget.options.indexWhere((o) => o.field);
    final kb = HardwareKeyboard.instance;
    if (fieldIndex >= 0 &&
        ch != null &&
        ch.isNotEmpty &&
        ch.runes.first >= 0x20 &&
        !kb.isControlPressed &&
        !kb.isAltPressed) {
      _select(fieldIndex);
      _field.value = TextEditingValue(
        text: _field.text + ch,
        selection: TextSelection.collapsed(offset: _field.text.length + ch.length),
      );
      _fieldFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < widget.options.length; i++) _row(i),
      ]),
    );
  }

  Widget _row(int i) {
    final o = widget.options[i];
    final sel = i == _sel;
    return MouseRegion(
      onEnter: (_) => _select(i),
      child: HoverBox(
        onTap: () => _activate(i),
        color: sel ? P.hover : null,
        hoverColor: P.hover,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.only(right: 8, top: 1),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: sel ? P.focus : P.inlineCodeBg,
              borderRadius: BorderRadius.circular(3),
            ),
            child: o.checked == null
                ? Text('${i + 1}', style: uiText(size: 11, color: sel ? P.buttonFg : P.fgMuted, height: 1.1))
                : Icon(o.checked! ? Codicons.check : null, size: 13, color: sel ? P.buttonFg : P.fg),
          ),
          Expanded(
            child: o.field
                ? TextField(
                    controller: _field,
                    focusNode: _fieldFocus,
                    inputFormatters: [noControlChars],
                    style: uiText(),
                    cursorColor: P.fg,
                    minLines: 1,
                    maxLines: 4,
                    onTap: () => _select(i),
                    onSubmitted: (v) {
                      if (v.trim().isNotEmpty) widget.onFieldSubmit?.call(v);
                    },
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.only(top: 1),
                      hintText: o.label,
                      hintStyle: uiText(color: P.fgMuted),
                    ),
                  )
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(o.label, style: uiText(weight: sel ? FontWeight.w600 : null)),
                    if (o.hint != null && o.hint!.isNotEmpty)
                      Text(o.hint!, style: uiText(size: 12, color: P.fgMuted)),
                  ]),
          ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ permission

class PermissionCard extends StatelessWidget {
  const PermissionCard({super.key, required this.session, required this.r});
  final ChatSession session;
  final RequestItem r;

  String get _title => _agent(switch (r.toolName) {
        'Bash' || 'PowerShell' || 'Shell' => S.permRunCommand,
        'Edit' || 'MultiEdit' || 'NotebookEdit' || 'Patch' => S.permEditFile,
        'Write' => S.permWriteFile,
        'Read' || 'Glob' || 'Grep' => S.permReadFile,
        'WebFetch' || 'WebSearch' => S.permFetch,
        _ => S.permUseTool(ToolItem(toolUseId: '', name: r.toolName).displayName),
      });

  /// UI strings name Claude; other agents get their own name.
  String _agent(String s) => s.replaceAll('Claude', session.agentName);

  String? _alwaysLabel() {
    if (r.suggestions.isEmpty) return null;
    if (r.suggestions.every((s) => s == 'session')) return S.allowSession;
    final parts = <String>[];
    for (final s in r.suggestions) {
      if (s is! Map) continue;
      switch (s['type']) {
        case 'addRules':
        case 'replaceRules':
          for (final rule in (s['rules'] as List? ?? [])) {
            if (rule is Map) {
              final content = rule['ruleContent'];
              parts.add(content is String && content.isNotEmpty ? '${rule['toolName']}($content)' : '${rule['toolName']}');
            }
          }
        case 'setMode':
          parts.add(s['mode'] == 'acceptEdits' ? S.modeAcceptEdits.toLowerCase() : '${s['mode']}');
        case 'addDirectories':
          parts.addAll([for (final d in (s['directories'] as List? ?? [])) '$d']);
      }
    }
    if (parts.isEmpty) return S.allowAlways;
    return S.allowAlwaysFor(parts.join(', '));
  }

  Widget _preview() {
    final i = r.input;
    switch (r.toolName) {
      case 'Bash':
      case 'PowerShell':
      case 'Shell':
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CodeBlock(code: '${i['command'] ?? ''}', language: r.toolName == 'Bash' ? 'bash' : 'powershell'),
          if (i['description'] is String)
            Text('${i['description']}', style: uiText(size: 12, color: P.fgMuted)),
        ]);
      case 'Patch':
        final changes = (i['changes'] as List? ?? []).whereType<Map>().toList();
        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 300),
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final c in changes) ...[
                Text('${c['path']}', style: monoText(color: P.fgMuted)),
                DiffView(lines: parseUnifiedDiff('${c['diff'] ?? ''}'), path: '${c['path']}', maxLines: 400),
              ],
              if (i['description'] is String) Text('${i['description']}', style: uiText(size: 12, color: P.fgMuted)),
            ]),
          ),
        );
      case 'Edit':
      case 'MultiEdit':
      case 'Write':
        final t = ToolItem(toolUseId: '', name: r.toolName, input: i)..inputComplete = true;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${i['file_path'] ?? ''}', style: monoText(color: P.fgMuted)),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: SingleChildScrollView(child: DiffView(lines: diffForTool(t), path: '${i['file_path'] ?? ''}', maxLines: 400)),
          ),
        ]);
      default:
        final t = ToolItem(toolUseId: '', name: r.toolName, input: i)..inputComplete = true;
        final summary = toolSummary(t, session.cwd);
        return summary.isEmpty
            ? const SizedBox.shrink()
            : Text(summary, style: monoText(color: P.fgMuted), maxLines: 4, overflow: TextOverflow.ellipsis);
    }
  }

  @override
  Widget build(BuildContext context) {
    final always = _alwaysLabel();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(_title, style: uiText(weight: FontWeight.w600)),
      const SizedBox(height: 6),
      _preview(),
      if (r.decisionReason != null && r.decisionReason!.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(r.decisionReason!, style: uiText(size: 12, color: P.fgMuted)),
        ),
      const SizedBox(height: 8),
      _OptionList(
        options: [
          _Option(S.allow, onPick: () => session.allow(r, summary: S.allowed)),
          if (always != null)
            _Option(always, onPick: () => session.allow(r, permissions: r.suggestions, summary: S.allowAlways)),
          _Option(_agent(S.denyHint), field: true),
        ],
        onFieldSubmit: (text) => session.deny(r, feedback: text),
        onEscape: () => session.deny(r),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ question

class QuestionCard extends StatefulWidget {
  const QuestionCard({super.key, required this.session, required this.r});
  final ChatSession session;
  final RequestItem r;
  @override
  State<QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<QuestionCard> {
  int _q = 0;
  final Map<int, Set<String>> _picked = {};
  final Map<int, String> _other = {};
  final Map<int, int> _hovered = {};

  List<Map<String, dynamic>> get _questions => [
        for (final q in (widget.r.input['questions'] as List? ?? []))
          if (q is Map) q.cast<String, dynamic>()
      ];

  bool _answered(int i) => (_picked[i]?.isNotEmpty ?? false) || (_other[i]?.trim().isNotEmpty ?? false);

  void _submit() {
    final qs = _questions;
    final answers = <String, String>{};
    final summary = <String>[];
    for (var i = 0; i < qs.length; i++) {
      final parts = [...?_picked[i]];
      final other = _other[i]?.trim();
      if (other != null && other.isNotEmpty) parts.add(other);
      if (parts.isEmpty) continue;
      final a = parts.join(', ');
      answers['${qs[i]['question']}'] = a;
      summary.add('${qs[i]['header'] ?? qs[i]['question']} → $a');
    }
    widget.session.allow(
      widget.r,
      updatedInput: {...widget.r.input, 'answers': answers},
      summary: summary.join('\n'),
    );
  }

  void _pick(int qi, String label, bool multi) {
    setState(() {
      final set = _picked.putIfAbsent(qi, () => <String>{});
      if (multi) {
        set.contains(label) ? set.remove(label) : set.add(label);
      } else {
        set
          ..clear()
          ..add(label);
        _other.remove(qi);
        final qs = _questions;
        if (qi < qs.length - 1) {
          _q = qi + 1;
        } else if (List.generate(qs.length, _answered).every((x) => x)) {
          _submit();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final qs = _questions;
    if (qs.isEmpty) return const SizedBox.shrink();
    final q = qs[_q];
    final multi = q['multiSelect'] == true;
    final opts = [for (final o in (q['options'] as List? ?? [])) if (o is Map) o.cast<String, dynamic>()];
    final hasPreview = opts.any((o) => (o['preview'] as String?)?.isNotEmpty ?? false);
    final hoveredPreview = () {
      final h = _hovered[_q] ?? 0;
      if (h < opts.length) return opts[h]['preview'] as String?;
      return null;
    }();
    final allAnswered = List.generate(qs.length, _answered).every((x) => x);

    final list = _OptionList(
      key: ValueKey('q$_q'),
      onHover: (i) => setState(() => _hovered[_q] = i),
      options: [
        for (final o in opts)
          _Option(
            '${o['label']}',
            hint: o['description'] as String?,
            checked: multi ? (_picked[_q]?.contains('${o['label']}') ?? false) : null,
            onPick: () => _pick(_q, '${o['label']}', multi),
          ),
        _Option(S.otherHint, field: true),
      ],
      onFieldSubmit: (text) {
        setState(() {
          _other[_q] = text;
          if (!multi) _picked[_q]?.clear();
          if (_q < qs.length - 1) {
            _q++;
          } else if (List.generate(qs.length, _answered).every((x) => x)) {
            _submit();
          }
        });
      },
      onEscape: () => widget.session.deny(widget.r, feedback: null),
    );

    final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (qs.length > 1)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(spacing: 4, runSpacing: 4, children: [
            for (var i = 0; i < qs.length; i++)
              HoverBox(
                onTap: () => setState(() => _q = i),
                color: i == _q ? P.inputBg : null,
                border: Border.all(color: i == _q ? P.focus : P.inputBorder),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (_answered(i)) ...[Icon(Codicons.check, size: 12, color: P.ok), const SizedBox(width: 4)],
                  Text('${qs[i]['header'] ?? i + 1}', style: uiText(size: 12)),
                ]),
              ),
          ]),
        )
      else if (q['header'] is String)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Align(alignment: Alignment.centerLeft, child: Pill('${q['header']}')),
        ),
      Text('${q['question']}', style: uiText(weight: FontWeight.w600)),
      const SizedBox(height: 8),
      if (hasPreview)
        LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth > 620;
          final preview = Container(
            constraints: const BoxConstraints(maxHeight: 320),
            decoration: BoxDecoration(
              color: P.codeBg,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: P.border),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(hoveredPreview ?? '', style: monoText(), softWrap: false),
              ),
            ),
          );
          return wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 4, child: list),
                  const SizedBox(width: 10),
                  Expanded(flex: 5, child: preview),
                ])
              : Column(children: [list, const SizedBox(height: 8), preview]);
        })
      else
        list,
      const SizedBox(height: 8),
      Row(children: [
        if (_q > 0) VsButton(S.back, primary: false, dense: true, onTap: () => setState(() => _q--)),
        const Spacer(),
        VsButton(S.skip, primary: false, dense: true, onTap: () => widget.session.deny(widget.r, feedback: 'The user skipped these questions; continue with your best judgement.')),
        const SizedBox(width: 6),
        if (_q < qs.length - 1)
          VsButton(S.next, dense: true, onTap: _answered(_q) ? () => setState(() => _q++) : null)
        else
          VsButton(S.submit, dense: true, onTap: allAnswered ? _submit : null),
      ]),
    ]);
    // Ctrl+Enter: next question, or submit on the last one.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, e) {
        if (e is KeyDownEvent && isEnter(e) && HardwareKeyboard.instance.isControlPressed) {
          if (_q < qs.length - 1) {
            if (_answered(_q)) setState(() => _q++);
          } else if (allAnswered) {
            _submit();
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: body,
    );
  }
}

// ------------------------------------------------------------------ plan

class PlanCard extends StatelessWidget {
  const PlanCard({super.key, required this.session, required this.r});
  final ChatSession session;
  final RequestItem r;

  void _approve(String mode) {
    session.allow(r, permissions: [
      {'type': 'setMode', 'mode': mode, 'destination': 'session'}
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.45;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(S.planTitle, style: uiText(weight: FontWeight.w600)),
      const SizedBox(height: 6),
      Container(
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: BoxDecoration(border: Border.all(color: P.border), borderRadius: BorderRadius.circular(5)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(10),
          child: MarkdownView('${r.input['plan'] ?? ''}'),
        ),
      ),
      const SizedBox(height: 8),
      _OptionList(
        options: [
          _Option(S.planApproveAuto, onPick: () => _approve('acceptEdits')),
          _Option(S.planApprove, onPick: () => _approve('default')),
          _Option(S.planKeepHint, field: true),
        ],
        onFieldSubmit: (text) => session.deny(r, feedback: text),
        onEscape: () => session.deny(r),
      ),
    ]);
  }
}
