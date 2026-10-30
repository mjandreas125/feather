import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Keyboard handling that works with every layout, following the same rule Windows uses
/// for shortcuts:
/// * on Latin layouts (QWERTY, AZERTY, Dvorak, …) a shortcut letter is the *logical*
///   letter, so Ctrl+C is wherever the layout puts "C";
/// * on non-Latin layouts (Russian, Greek, Hebrew, Arabic, …) the letter key produces a
///   non-Latin character, so we fall back to the *physical* position of the US key.
/// Flutter's built-in text shortcuts only look at logical keys, so on a Russian layout
/// Ctrl+C / Ctrl+V / Ctrl+Z silently do nothing; this fixes that.
class LayoutShortcut extends ShortcutActivator {
  const LayoutShortcut(this.logical, this.physical, {this.control = false, this.shift = false, this.alt = false});

  final LogicalKeyboardKey logical;
  final PhysicalKeyboardKey physical;
  final bool control, shift, alt;

  @override
  Iterable<LogicalKeyboardKey>? get triggers => null;

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (state.isControlPressed != control ||
        state.isShiftPressed != shift ||
        state.isAltPressed != alt ||
        state.isMetaPressed) {
      return false;
    }
    if (event.logicalKey == logical) return true;
    return event.physicalKey == physical && !isLatinLetterKey(event.logicalKey);
  }

  @override
  String debugDescribeKeys() =>
      '${control ? 'Ctrl+' : ''}${shift ? 'Shift+' : ''}${alt ? 'Alt+' : ''}${logical.keyLabel}';
}

/// True for the logical keys a..z (what a Latin layout produces on letter keys).
bool isLatinLetterKey(LogicalKeyboardKey k) {
  final id = k.keyId;
  return id >= 0x61 && id <= 0x7a;
}

/// Text-editing shortcuts that also work on non-Latin layouts. Placed below WidgetsApp
/// so they are found before the default (logical-only) ones; when nothing editable or
/// selectable has focus they are ignored and the event continues as usual.
const Map<ShortcutActivator, Intent> layoutIndependentTextShortcuts = {
  LayoutShortcut(LogicalKeyboardKey.keyC, PhysicalKeyboardKey.keyC, control: true): CopySelectionTextIntent.copy,
  LayoutShortcut(LogicalKeyboardKey.keyX, PhysicalKeyboardKey.keyX, control: true):
      CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
  LayoutShortcut(LogicalKeyboardKey.keyV, PhysicalKeyboardKey.keyV, control: true):
      PasteTextIntent(SelectionChangedCause.keyboard),
  LayoutShortcut(LogicalKeyboardKey.keyA, PhysicalKeyboardKey.keyA, control: true):
      SelectAllTextIntent(SelectionChangedCause.keyboard),
  LayoutShortcut(LogicalKeyboardKey.keyZ, PhysicalKeyboardKey.keyZ, control: true):
      UndoTextIntent(SelectionChangedCause.keyboard),
  LayoutShortcut(LogicalKeyboardKey.keyY, PhysicalKeyboardKey.keyY, control: true):
      RedoTextIntent(SelectionChangedCause.keyboard),
  LayoutShortcut(LogicalKeyboardKey.keyZ, PhysicalKeyboardKey.keyZ, control: true, shift: true):
      RedoTextIntent(SelectionChangedCause.keyboard),
};

/// Shortcut letter test for app commands (Ctrl+N etc.), same rule as [LayoutShortcut].
bool isLetter(KeyEvent e, LogicalKeyboardKey logical, PhysicalKeyboardKey physical) =>
    e.logicalKey == logical || (e.physicalKey == physical && !isLatinLetterKey(e.logicalKey));

/// 1..9 from the digit row or numpad. Uses the typed digit when there is one, otherwise
/// the key position (AZERTY's top row types "&é"…" without Shift).
int? keyDigit(KeyEvent e) {
  final id = e.logicalKey.keyId;
  if (id >= 0x31 && id <= 0x39) return id - 0x30;
  const pad = [
    LogicalKeyboardKey.numpad1, LogicalKeyboardKey.numpad2, LogicalKeyboardKey.numpad3,
    LogicalKeyboardKey.numpad4, LogicalKeyboardKey.numpad5, LogicalKeyboardKey.numpad6,
    LogicalKeyboardKey.numpad7, LogicalKeyboardKey.numpad8, LogicalKeyboardKey.numpad9,
  ];
  final p = pad.indexOf(e.logicalKey);
  if (p >= 0) return p + 1;
  if (isLatinLetterKey(e.logicalKey)) return null;
  const top = [
    PhysicalKeyboardKey.digit1, PhysicalKeyboardKey.digit2, PhysicalKeyboardKey.digit3,
    PhysicalKeyboardKey.digit4, PhysicalKeyboardKey.digit5, PhysicalKeyboardKey.digit6,
    PhysicalKeyboardKey.digit7, PhysicalKeyboardKey.digit8, PhysicalKeyboardKey.digit9,
  ];
  final t = top.indexOf(e.physicalKey);
  return t < 0 ? null : t + 1;
}

/// Drops invisible control characters (what Ctrl+letter can type on some layouts and
/// input tools) while keeping new lines and tabs.
final TextInputFormatter noControlChars =
    FilteringTextInputFormatter.deny(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'));

/// Named keys (Enter, Esc, arrows, Tab) are the same on every layout: match logically.
bool isEnter(KeyEvent e) =>
    e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.numpadEnter;
bool isEscape(KeyEvent e) => e.logicalKey == LogicalKeyboardKey.escape;
bool isTab(KeyEvent e) => e.logicalKey == LogicalKeyboardKey.tab;
bool isUp(KeyEvent e) => e.logicalKey == LogicalKeyboardKey.arrowUp;
bool isDown(KeyEvent e) => e.logicalKey == LogicalKeyboardKey.arrowDown;
bool isSpace(KeyEvent e) => e.logicalKey == LogicalKeyboardKey.space;
