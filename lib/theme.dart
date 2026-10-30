import 'package:flutter/material.dart';

/// Colour tokens. Values follow VS Code's "Dark Modern" / "Light Modern" themes so the
/// app feels like the Claude Code panel people already know.
class Palette {
  const Palette({
    required this.dark,
    required this.bg,
    required this.sideBg,
    required this.panelBg,
    required this.fg,
    required this.fgMuted,
    required this.fgFaint,
    required this.border,
    required this.inputBg,
    required this.inputBorder,
    required this.focus,
    required this.button,
    required this.buttonHover,
    required this.buttonFg,
    required this.secondaryButton,
    required this.secondaryButtonHover,
    required this.hover,
    required this.selection,
    required this.link,
    required this.codeBg,
    required this.inlineCodeBg,
    required this.inlineCodeFg,
    required this.menuBg,
    required this.menuBorder,
    required this.added,
    required this.removed,
    required this.addedBg,
    required this.removedBg,
    required this.ok,
    required this.error,
    required this.warn,
    required this.accent,
    required this.scrollThumb,
  });

  final bool dark;
  final Color bg, sideBg, panelBg, fg, fgMuted, fgFaint, border, inputBg, inputBorder;
  final Color focus, button, buttonHover, buttonFg, secondaryButton, secondaryButtonHover;
  final Color hover, selection, link, codeBg, inlineCodeBg, inlineCodeFg, menuBg, menuBorder;
  final Color added, removed, addedBg, removedBg, ok, error, warn, accent, scrollThumb;

  static const darkModern = Palette(
    dark: true,
    bg: Color(0xFF1F1F1F),
    sideBg: Color(0xFF181818),
    panelBg: Color(0xFF181818),
    fg: Color(0xFFCCCCCC),
    fgMuted: Color(0xFF9D9D9D),
    fgFaint: Color(0xFF6E6E6E),
    border: Color(0xFF2B2B2B),
    inputBg: Color(0xFF313131),
    inputBorder: Color(0xFF3C3C3C),
    focus: Color(0xFF0078D4),
    button: Color(0xFF0078D4),
    buttonHover: Color(0xFF026EC1),
    buttonFg: Color(0xFFFFFFFF),
    secondaryButton: Color(0xFF313131),
    secondaryButtonHover: Color(0xFF3C3C3C),
    hover: Color(0xFF2A2D2E),
    selection: Color(0xFF264F78),
    link: Color(0xFF4DAAFC),
    codeBg: Color(0xFF2B2B2B),
    inlineCodeBg: Color(0x337F7F7F),
    inlineCodeFg: Color(0xFFD7BA7D),
    menuBg: Color(0xFF1F1F1F),
    menuBorder: Color(0xFF454545),
    added: Color(0xFF81B88B),
    removed: Color(0xFFE5534B),
    addedBg: Color(0x339CCC2C),
    removedBg: Color(0x33FF0000),
    ok: Color(0xFF74C991),
    error: Color(0xFFF14C4C),
    warn: Color(0xFFCCA700),
    accent: Color(0xFFD97757),
    scrollThumb: Color(0x66797979),
  );

  static const lightModern = Palette(
    dark: false,
    bg: Color(0xFFFFFFFF),
    sideBg: Color(0xFFF8F8F8),
    panelBg: Color(0xFFF8F8F8),
    fg: Color(0xFF3B3B3B),
    fgMuted: Color(0xFF6F6F6F),
    fgFaint: Color(0xFF9A9A9A),
    border: Color(0xFFE5E5E5),
    inputBg: Color(0xFFFFFFFF),
    inputBorder: Color(0xFFCECECE),
    focus: Color(0xFF005FB8),
    button: Color(0xFF005FB8),
    buttonHover: Color(0xFF0258A8),
    buttonFg: Color(0xFFFFFFFF),
    secondaryButton: Color(0xFFE5E5E5),
    secondaryButtonHover: Color(0xFFCCCCCC),
    hover: Color(0xFFF2F2F2),
    selection: Color(0xFFADD6FF),
    link: Color(0xFF005FB8),
    codeBg: Color(0xFFF3F3F3),
    inlineCodeBg: Color(0x1F7F7F7F),
    inlineCodeFg: Color(0xFF9A3B1F),
    menuBg: Color(0xFFFFFFFF),
    menuBorder: Color(0xFFCECECE),
    added: Color(0xFF2E7D32),
    removed: Color(0xFFC62828),
    addedBg: Color(0x332EA043),
    removedBg: Color(0x33F85149),
    ok: Color(0xFF388A34),
    error: Color(0xFFE51400),
    warn: Color(0xFFBF8803),
    accent: Color(0xFFC6613F),
    scrollThumb: Color(0x66646464),
  );
}

/// Current palette. Widgets read [P]; the app rebuilds when [paletteNotifier] changes.
final ValueNotifier<Palette> paletteNotifier = ValueNotifier(Palette.darkModern);
Palette get P => paletteNotifier.value;

/// UI fonts: Segoe UI with fallbacks so every script renders (Cyrillic, CJK, Arabic, emoji).
const String uiFont = 'Segoe UI';
const List<String> uiFontFallback = [
  'Segoe UI Variable Text',
  'Microsoft YaHei UI',
  'Yu Gothic UI',
  'Malgun Gothic',
  'Nirmala UI',
  'Segoe UI Historic',
  'Segoe UI Emoji',
  'Segoe UI Symbol',
];
const String monoFont = 'Cascadia Mono';
const List<String> monoFontFallback = [
  'Consolas',
  'Courier New',
  'Microsoft YaHei UI',
  'Segoe UI Emoji',
];

const double chatFontSize = 13;
const double monoFontSize = 12;

TextStyle uiText({double size = chatFontSize, Color? color, FontWeight? weight, double? height}) =>
    TextStyle(
      fontFamily: uiFont,
      fontFamilyFallback: uiFontFallback,
      fontSize: size,
      color: color ?? P.fg,
      fontWeight: weight,
      height: height ?? 1.45,
    );

TextStyle monoText({double size = monoFontSize, Color? color, FontWeight? weight, double? height}) =>
    TextStyle(
      fontFamily: monoFont,
      fontFamilyFallback: monoFontFallback,
      fontSize: size,
      color: color ?? P.fg,
      fontWeight: weight,
      height: height ?? 1.4,
    );

ThemeData buildTheme(Palette p) {
  final base = p.dark ? ThemeData.dark(useMaterial3: true) : ThemeData.light(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: p.hover,
    focusColor: Colors.transparent,
    colorScheme: base.colorScheme.copyWith(
      primary: p.focus,
      secondary: p.accent,
      surface: p.bg,
      onSurface: p.fg,
      error: p.error,
    ),
    textTheme: base.textTheme.apply(
      fontFamily: uiFont,
      fontFamilyFallback: uiFontFallback,
      bodyColor: p.fg,
      displayColor: p.fg,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.fg,
      selectionColor: p.selection,
      selectionHandleColor: p.focus,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(p.scrollThumb),
      thickness: const WidgetStatePropertyAll(10),
      radius: Radius.zero,
      crossAxisMargin: 0,
      mainAxisMargin: 0,
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      textStyle: uiText(size: 12),
      decoration: BoxDecoration(
        color: p.menuBg,
        border: Border.all(color: p.menuBorder),
        borderRadius: BorderRadius.circular(3),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.menuBg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: p.menuBorder),
        borderRadius: BorderRadius.circular(5),
      ),
      textStyle: uiText(),
    ),
    dividerColor: p.border,
  );
}
