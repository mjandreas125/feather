import 'package:flutter/material.dart';

import '../codicons.dart';
import '../platform_window.dart';
import '../theme.dart';

/// VS Code-style title bar drawn by the app (the native caption is removed in
/// win32_window.cpp): app icon, window title, and the window buttons. Dragging moves the
/// window through Windows itself, so Aero Snap and Win+arrows keep working.
class TitleBar extends StatelessWidget {
  const TitleBar({super.key, this.trailing});
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => NativeWindow.startDrag(),
            onDoubleTap: NativeWindow.toggleMaximize,
            child: Container(
              decoration: BoxDecoration(color: P.sideBg, border: Border(bottom: BorderSide(color: P.border))),
              child: Row(children: [
                const SizedBox(width: 10),
                Image.asset('assets/feather.png', width: 16, height: 16, filterQuality: FilterQuality.medium),
                const SizedBox(width: 10),
                Expanded(
                  child: ValueListenableBuilder<String>(
                    valueListenable: NativeWindow.title,
                    builder: (context, t, _) => Text(
                      t,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: uiText(size: 12, color: P.fgMuted),
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
                const SizedBox(width: 6),
                _WinButton(Codicons.chromeMinimize, onTap: NativeWindow.minimize),
                ValueListenableBuilder<bool>(
                  valueListenable: NativeWindow.maximized,
                  builder: (context, max, _) =>
                      _WinButton(max ? Codicons.chromeRestore : Codicons.chromeMaximize, onTap: NativeWindow.toggleMaximize),
                ),
                _WinButton(Codicons.chromeClose, onTap: NativeWindow.close, danger: true),
              ]),
            ),
          ),
        ),
        // Thin strips along the top edge to resize the window from there.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 4,
          child: _ResizeStrip(edge: 'top', cursor: SystemMouseCursors.resizeUp),
        ),
        Positioned(left: 0, top: 0, width: 8, height: 6, child: _ResizeStrip(edge: 'topLeft', cursor: SystemMouseCursors.resizeUpLeft)),
        Positioned(right: 0, top: 0, width: 8, height: 6, child: _ResizeStrip(edge: 'topRight', cursor: SystemMouseCursors.resizeUpRight)),
      ]),
    );
  }
}

class _ResizeStrip extends StatelessWidget {
  const _ResizeStrip({required this.edge, required this.cursor});
  final String edge;
  final MouseCursor cursor;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: NativeWindow.maximized,
        builder: (context, max, _) => max
            ? const SizedBox.shrink()
            : MouseRegion(
                cursor: cursor,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (_) => NativeWindow.startResize(edge),
                ),
              ),
      );
}

class _WinButton extends StatefulWidget {
  const _WinButton(this.icon, {required this.onTap, this.danger = false});
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;
  @override
  State<_WinButton> createState() => _WinButtonState();
}

class _WinButtonState extends State<_WinButton> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final bg = !_h ? Colors.transparent : (widget.danger ? const Color(0xFFE81123) : P.hover);
    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 46,
          height: 30,
          color: bg,
          child: Icon(widget.icon, size: 16, color: _h && widget.danger ? Colors.white : P.fg),
        ),
      ),
    );
  }
}
