import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../codicons.dart';

/// Rectangle that shows the VS Code hover background under the mouse.
class HoverBox extends StatefulWidget {
  const HoverBox({
    super.key,
    required this.child,
    this.onTap,
    this.padding = EdgeInsets.zero,
    this.radius = 4,
    this.color,
    this.hoverColor,
    this.border,
    this.cursor,
    this.tooltip,
  });
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final double radius;
  final Color? color;
  final Color? hoverColor;
  final BoxBorder? border;
  final MouseCursor? cursor;
  final String? tooltip;

  @override
  State<HoverBox> createState() => _HoverBoxState();
}

class _HoverBoxState extends State<HoverBox> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    Widget w = MouseRegion(
      cursor: widget.cursor ?? (enabled ? SystemMouseCursors.click : MouseCursor.defer),
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: widget.padding,
          decoration: BoxDecoration(
            color: _hover && enabled ? (widget.hoverColor ?? P.hover) : widget.color,
            borderRadius: BorderRadius.circular(widget.radius),
            border: widget.border,
          ),
          child: widget.child,
        ),
      ),
    );
    if (widget.tooltip != null) w = Tooltip(message: widget.tooltip!, child: w);
    return w;
  }
}

class IconBtn extends StatelessWidget {
  const IconBtn(this.icon, {super.key, this.onTap, this.tooltip, this.size = 16, this.color, this.active = false});
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final Color? color;
  final bool active;

  @override
  Widget build(BuildContext context) => HoverBox(
        onTap: onTap,
        tooltip: tooltip,
        radius: 5,
        color: active ? P.hover : null,
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: size, color: onTap == null ? P.fgFaint : (color ?? P.fg)),
      );
}

/// VS Code style button.
class VsButton extends StatefulWidget {
  const VsButton(this.label, {super.key, this.onTap, this.primary = true, this.dense = false, this.icon});
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool dense;
  final IconData? icon;

  @override
  State<VsButton> createState() => _VsButtonState();
}

class _VsButtonState extends State<VsButton> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final bg = widget.primary
        ? (_hover ? P.buttonHover : P.button)
        : (_hover ? P.secondaryButtonHover : P.secondaryButton);
    final fg = widget.primary ? P.buttonFg : P.fg;
    return MouseRegion(
      cursor: widget.onTap == null ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Opacity(
          opacity: widget.onTap == null ? 0.5 : 1,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: widget.dense ? 8 : 14, vertical: widget.dense ? 3 : 5),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (widget.icon != null) ...[Icon(widget.icon, size: 14, color: fg), const SizedBox(width: 6)],
              Text(widget.label, style: uiText(color: fg, size: 13)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The "✻ Working…" indicator: a star that cycles through glyphs, like Claude Code's CLI.
/// Only ticks while mounted, so an idle window costs no CPU.
class ClaudeSpinner extends StatefulWidget {
  const ClaudeSpinner({super.key, this.size = 14, this.color});
  final double size;
  final Color? color;
  @override
  State<ClaudeSpinner> createState() => _ClaudeSpinnerState();
}

class _ClaudeSpinnerState extends State<ClaudeSpinner> {
  static const frames = ['·', '✢', '✳', '✶', '✻', '✽', '✻', '✶', '✳', '✢'];
  int _i = 0;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 120), (_) => setState(() => _i = (_i + 1) % frames.length));
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: widget.size + 4,
        child: Text(frames[_i],
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: 'Segoe UI Symbol',
                fontSize: widget.size,
                color: widget.color ?? P.accent,
                height: 1.2)),
      );
}

/// Ticking elapsed-time label ("12s", "1m 05s").
class ElapsedText extends StatefulWidget {
  const ElapsedText(this.since, {super.key, this.style});
  final DateTime since;
  final TextStyle? style;
  @override
  State<ElapsedText> createState() => _ElapsedTextState();
}

class _ElapsedTextState extends State<ElapsedText> {
  Timer? _t;
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = DateTime.now().difference(widget.since);
    final s = d.inSeconds;
    final text = s < 60 ? '${s}s' : '${d.inMinutes}m ${(s % 60).toString().padLeft(2, '0')}s';
    return Text(text, style: widget.style);
  }
}

class CopyButton extends StatefulWidget {
  const CopyButton(this.text, {super.key, this.tooltip});
  final String Function() text;
  final String? tooltip;
  @override
  State<CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<CopyButton> {
  bool _done = false;
  @override
  Widget build(BuildContext context) => IconBtn(
        _done ? Codicons.check : Codicons.copy,
        size: 14,
        tooltip: widget.tooltip,
        color: _done ? P.ok : P.fgMuted,
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: widget.text()));
          if (!mounted) return;
          setState(() => _done = true);
          Future.delayed(const Duration(milliseconds: 1400), () {
            if (mounted) setState(() => _done = false);
          });
        },
      );
}

/// Small rounded label.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color, this.bg});
  final String text;
  final Color? color, bg;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: bg ?? P.inlineCodeBg, borderRadius: BorderRadius.circular(3)),
        child: Text(text, style: uiText(size: 11, color: color ?? P.fgMuted)),
      );
}
