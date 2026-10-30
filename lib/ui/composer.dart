import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../claude/chat_items.dart';
import '../claude/session.dart';
import '../files.dart';
import '../keys.dart';
import '../l10n.dart';
import '../platform_window.dart';
import '../theme.dart';
import 'widgets.dart';
import '../codicons.dart';

const permissionModes = ['default', 'acceptEdits', 'plan', 'auto'];

String modeLabel(String m) => switch (m) {
      'acceptEdits' => S.modeAcceptEdits,
      'plan' => S.modePlan,
      'auto' => S.modeAuto,
      'bypassPermissions' => S.modeBypass,
      _ => S.modeDefault,
    };

String modeHint(String m) => switch (m) {
      'acceptEdits' => S.modeAcceptEditsHint,
      'plan' => S.modePlanHint,
      'auto' => S.modeAutoHint,
      'bypassPermissions' => S.modeBypassHint,
      _ => S.modeDefaultHint,
    };

IconData modeIcon(String m) => switch (m) {
      'acceptEdits' => Codicons.edit,
      'plan' => Codicons.checklist,
      'auto' => Codicons.sparkle,
      'bypassPermissions' => Codicons.warning,
      _ => Codicons.shield,
    };

class Composer extends StatefulWidget {
  const Composer({super.key, required this.session});
  final ChatSession session;
  @override
  State<Composer> createState() => ComposerState();
}

/// Popup shown above the input: slash commands ("/") or project files ("@").
class _Suggest {
  _Suggest(this.kind, this.start, this.end, this.items);
  final String kind; // '/' or '@'
  final int start, end; // text range the pick replaces
  final List<(String, String)> items; // (value, description)
  int sel = 0;
}

class ComposerState extends State<Composer> {
  final _ctrl = TextEditingController();
  final focus = FocusNode(debugLabel: 'composer');
  final List<String> _history = [];
  final List<ImageAttachment> _images = [];
  int _historyPos = -1;
  bool _focused = false;
  _Suggest? _sug;

  /// The composer of the visible tab (receives files dropped on the window).
  static ComposerState? active;

  ChatSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    focus.addListener(() {
      if (focus.hasFocus) active = this;
      setState(() => _focused = focus.hasFocus);
    });
    _ctrl.addListener(_onText);
  }

  @override
  void dispose() {
    if (identical(active, this)) active = null;
    _ctrl.dispose();
    focus.dispose();
    super.dispose();
  }

  void _send() {
    final text = _ctrl.text.trimRight();
    if (text.trim().isEmpty && _images.isEmpty) return;
    s.send(text, images: List.of(_images));
    if (text.trim().isNotEmpty) _history.add(text);
    _historyPos = -1;
    _images.clear();
    _ctrl.clear();
  }

  // ------------------------------------------------------------ suggestions

  void _onText() {
    final v = _ctrl.value;
    final cur = v.selection.baseOffset;
    _Suggest? next;
    if (cur >= 0 && cur <= v.text.length && !(v.composing.isValid && !v.composing.isCollapsed)) {
      final before = v.text.substring(0, cur);
      if (before.startsWith('/') && !before.contains(RegExp(r'\s'))) {
        final q = before.substring(1).toLowerCase();
        final cmds = s.commands.where((c) => !c.name.startsWith('__') && c.name.toLowerCase().contains(q)).toList()
          ..sort((a, b) {
            final pa = a.name.toLowerCase().startsWith(q) ? 0 : 1, pb = b.name.toLowerCase().startsWith(q) ? 0 : 1;
            return pa != pb ? pa - pb : a.name.compareTo(b.name);
          });
        next = _Suggest('/', 0, cur, [for (final c in cmds.take(60)) ('/${c.name}', c.description)]);
      } else {
        final m = RegExp(r'(?:^|\s)@([^\s@]*)$').firstMatch(before);
        if (m != null) {
          final q = m.group(1)!;
          final index = FileIndex.of(s.cwd);
          final files = index.cached;
          if (files == null) {
            index.files().then((_) {
              if (mounted) _onText();
            });
          }
          next = _Suggest('@', cur - q.length - 1, cur, [for (final f in fuzzyFiles(files ?? const [], q, limit: 60)) ('@$f', '')]);
        }
      }
    }
    if (next != null && next.items.isEmpty && next.kind == '/') next = null;
    if (next != null && _sug != null && _sug!.kind == next.kind) next.sel = _sug!.sel.clamp(0, next.items.length - 1 < 0 ? 0 : next.items.length - 1);
    setState(() => _sug = next);
  }

  void _accept([int? index]) {
    final sug = _sug;
    if (sug == null || sug.items.isEmpty) return;
    final value = sug.items[index ?? sug.sel].$1;
    final text = _ctrl.text;
    final insert = '$value ';
    final next = text.replaceRange(sug.start, sug.end.clamp(sug.start, text.length), insert);
    _ctrl.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: sug.start + insert.length));
    setState(() => _sug = null);
    focus.requestFocus();
  }

  // ------------------------------------------------------------ attachments

  Future<void> _paste() async {
    final png = await NativeWindow.clipboardImage();
    if (png != null && png.isNotEmpty) {
      setState(() => _images.add(ImageAttachment('image/png', base64Encode(png))));
      return;
    }
    final files = await NativeWindow.clipboardFiles();
    if (files.isNotEmpty) {
      await addPaths(files);
      return;
    }
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text;
    if (t != null && t.isNotEmpty) insert(t.replaceAll('\r\n', '\n'));
  }

  static const _imageTypes = {'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'gif': 'image/gif', 'webp': 'image/webp'};

  /// Images become attachments; other files are mentioned as @path.
  Future<void> addPaths(List<String> paths) async {
    final mentions = <String>[];
    for (final path in paths) {
      final ext = path.split('.').last.toLowerCase();
      final type = _imageTypes[ext];
      final f = File(path);
      if (type != null && f.existsSync() && f.lengthSync() < 8 * 1024 * 1024) {
        final bytes = await f.readAsBytes();
        _images.add(ImageAttachment(type, base64Encode(bytes)));
      } else {
        final rel = p.isWithin(s.cwd, path) ? p.relative(path, from: s.cwd).replaceAll('\\', '/') : path;
        mentions.add(rel.contains(' ') ? '@"$rel"' : '@$rel');
      }
    }
    setState(() {});
    if (mentions.isNotEmpty) insert('${mentions.join(' ')} ');
    focus.requestFocus();
  }

  Future<void> _pickFiles() async {
    final files = await openFiles();
    if (files.isEmpty) return;
    await addPaths([for (final f in files) f.path]);
  }

  void _cycleMode() {
    final i = permissionModes.indexOf(s.permissionMode);
    s.setPermissionMode(permissionModes[(i + 1) % permissionModes.length]);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final kb = HardwareKeyboard.instance;
    final composing = _ctrl.value.composing.isValid && !_ctrl.value.composing.isCollapsed;
    if (composing) return KeyEventResult.ignored; // IME is busy with this key
    final sug = _sug;
    if (sug != null && sug.items.isNotEmpty) {
      if (isDown(e)) {
        setState(() => sug.sel = (sug.sel + 1) % sug.items.length);
        return KeyEventResult.handled;
      }
      if (isUp(e)) {
        setState(() => sug.sel = (sug.sel - 1 + sug.items.length) % sug.items.length);
        return KeyEventResult.handled;
      }
      if ((isEnter(e) && !kb.isShiftPressed) || (isTab(e) && !kb.isShiftPressed)) {
        _accept();
        return KeyEventResult.handled;
      }
      if (isEscape(e)) {
        setState(() => _sug = null);
        return KeyEventResult.handled;
      }
    }
    if (kb.isControlPressed && !kb.isShiftPressed && isLetter(e, LogicalKeyboardKey.keyV, PhysicalKeyboardKey.keyV)) {
      _paste();
      return KeyEventResult.handled;
    }
    if (isEnter(e) && !kb.isShiftPressed && !kb.isAltPressed) {
      _send();
      return KeyEventResult.handled;
    }
    if (isEscape(e) && s.isBusy) {
      s.interrupt();
      return KeyEventResult.handled;
    }
    if (isTab(e) && kb.isShiftPressed) {
      _cycleMode();
      return KeyEventResult.handled;
    }
    if (isUp(e) && _history.isNotEmpty) {
      final atStart = _ctrl.selection.baseOffset <= 0 || _ctrl.text.isEmpty || _historyPos >= 0;
      if (atStart && (_ctrl.text.isEmpty || _historyPos >= 0)) {
        _historyPos = _historyPos < 0 ? _history.length - 1 : (_historyPos - 1).clamp(0, _history.length - 1);
        _setText(_history[_historyPos]);
        return KeyEventResult.handled;
      }
    }
    if (isDown(e) && _historyPos >= 0) {
      _historyPos++;
      if (_historyPos >= _history.length) {
        _historyPos = -1;
        _setText('');
      } else {
        _setText(_history[_historyPos]);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _setText(String t) {
    _ctrl.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
  }

  /// Inserts text at the cursor (used by other parts of the UI, e.g. file mentions).
  void insert(String t) {
    final sel = _ctrl.selection;
    final text = _ctrl.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final next = text.replaceRange(start, end, t);
    _ctrl.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: start + t.length));
    focus.requestFocus();
  }

  Future<void> _modeMenu(BuildContext anchor) async {
    final picked = await _showMenuAt<String>(anchor, [
      for (final m in permissionModes)
        _MenuEntry(m, modeLabel(m), hint: modeHint(m), icon: modeIcon(m), selected: m == s.permissionMode),
    ]);
    if (picked != null) s.setPermissionMode(picked);
  }

  Future<void> _modelMenu(BuildContext anchor) async {
    final models = s.models;
    final current = s.model ?? 'default';
    final cur = models.where((m) => m.value == current).toList();
    final efforts = cur.isNotEmpty ? cur.first.effortLevels : const <String>[];
    final picked = await _showMenuAt<String>(anchor, [
      for (final m in models)
        _MenuEntry('m:${m.value}', m.displayName, hint: m.description, selected: m.value == current),
      if (efforts.isNotEmpty) _MenuEntry.header(S.effort),
      for (final e in efforts) _MenuEntry('e:$e', e, selected: (s.effort ?? '') == e, dense: true),
    ]);
    if (picked == null) return;
    if (picked.startsWith('m:')) s.setModel(picked.substring(2));
    if (picked.startsWith('e:')) s.setEffort(picked.substring(2));
  }

  @override
  Widget build(BuildContext context) {
    final busy = s.isBusy;
    final canSend = _ctrl.text.trim().isNotEmpty || _images.isNotEmpty;
    final modelName = s.modelDisplayName;
    final box = Container(
      decoration: BoxDecoration(
        color: P.inputBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _focused ? P.focus : P.inputBorder),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_images.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (var i = 0; i < _images.length; i++)
                Stack(clipBehavior: Clip.none, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.memory(_images[i].bytes, height: 56, width: 72, fit: BoxFit.cover, cacheHeight: 112),
                  ),
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Material(
                      color: P.menuBg,
                      shape: CircleBorder(side: BorderSide(color: P.inputBorder)),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => setState(() => _images.removeAt(i)),
                        child: Padding(padding: const EdgeInsets.all(2), child: Icon(Codicons.close, size: 12, color: P.fg)),
                      ),
                    ),
                  ),
                ]),
            ]),
          ),
        Focus(
          onKeyEvent: _onKey,
          child: TextField(
            controller: _ctrl,
            focusNode: focus,
            autofocus: true,
            inputFormatters: [noControlChars],
            minLines: 1,
            maxLines: 14,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            style: uiText(),
            cursorColor: P.fg,
            cursorWidth: 1.5,
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.fromLTRB(10, 9, 10, 4),
              hintText: busy ? S.inputPlaceholderBusy : S.inputPlaceholder.replaceAll('Claude', s.agentName),
              hintStyle: uiText(color: P.fgFaint),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 5, 5),
          child: Row(children: [
            Builder(
              builder: (c) => HoverBox(
                onTap: () => _modeMenu(c),
                tooltip: 'Shift+Tab',
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(modeIcon(s.permissionMode),
                      size: 14,
                      color: s.permissionMode == 'default' ? P.fgMuted : P.accent),
                  const SizedBox(width: 5),
                  Text(modeLabel(s.permissionMode),
                      style: uiText(size: 12, color: s.permissionMode == 'default' ? P.fgMuted : P.fg)),
                ]),
              ),
            ),
            IconBtn(Codicons.attach, size: 15, color: P.fgMuted, tooltip: S.attach, onTap: _pickFiles),
            IconBtn(Codicons.mention, size: 15, color: P.fgMuted, tooltip: S.mentionFile, onTap: () => insert('@')),
            const Spacer(),
            if (s.contextPercent != null && s.contextPercent! >= 50)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Tooltip(
                  message: S.contextUsed(s.contextPercent!.round()),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    _ContextRing(s.contextPercent! / 100),
                    const SizedBox(width: 4),
                    Text('${s.contextPercent!.round()}%',
                        style: uiText(size: 11.5, color: s.contextPercent! > 80 ? P.warn : P.fgFaint)),
                  ]),
                ),
              ),
            Builder(
              builder: (c) => HoverBox(
                onTap: s.models.isEmpty ? null : () => _modelMenu(c),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(modelName, style: uiText(size: 12, color: P.fgMuted)),
                  if (s.effort != null) Text(' · ${s.effort}', style: uiText(size: 12, color: P.fgFaint)),
                  Icon(Codicons.chevronDown, size: 14, color: P.fgMuted),
                ]),
              ),
            ),
            const SizedBox(width: 4),
            _SendButton(
              busy: busy && !canSend,
              enabled: canSend || busy,
              tooltip: busy && !canSend ? '${S.stop} (Esc)' : '${S.send} (Enter)',
              onTap: () => busy && !canSend ? s.interrupt() : _send(),
            ),
          ]),
        ),
      ]),
    );
    final sug = _sug;
    // Same widget structure with or without the popup, so the text field is never rebuilt
    // from scratch (that would drop focus and keystrokes).
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (sug != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: _SuggestList(sug: sug, onPick: _accept, emptyText: sug.kind == '@' ? S.noFiles : ''),
        )
      else
        const SizedBox.shrink(),
      box,
    ]);
  }
}

class _SuggestList extends StatelessWidget {
  const _SuggestList({required this.sug, required this.onPick, required this.emptyText});
  final _Suggest sug;
  final void Function(int) onPick;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 248),
      decoration: BoxDecoration(
        color: P.menuBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: P.menuBorder),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: P.dark ? 0.35 : 0.1), blurRadius: 10)],
      ),
      child: sug.items.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(10),
              child: Text(emptyText, style: uiText(size: 12, color: P.fgMuted)),
            )
          : ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: sug.items.length,
              itemBuilder: (context, i) {
                final (value, desc) = sug.items[i];
                final selected = i == sug.sel;
                final isFile = sug.kind == '@';
                final name = isFile ? value.substring(1).split('/').last : value;
                final dir = isFile ? value.substring(1, value.length - name.length).replaceAll(RegExp(r'/$'), '') : '';
                return HoverBox(
                  onTap: () => onPick(i),
                  color: selected ? P.selection.withValues(alpha: 0.55) : null,
                  radius: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: Row(children: [
                    Icon(isFile ? Codicons.fileCode : Codicons.terminal, size: 14, color: P.fgMuted),
                    const SizedBox(width: 8),
                    Text(name, style: isFile ? uiText() : monoText(size: 12.5)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isFile ? dir : desc,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: uiText(size: 12, color: P.fgFaint),
                      ),
                    ),
                  ]),
                );
              },
            ),
    );
  }
}

class _SendButton extends StatefulWidget {
  const _SendButton({required this.busy, required this.enabled, required this.onTap, required this.tooltip});
  final bool busy, enabled;
  final VoidCallback onTap;
  final String tooltip;
  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final bg = !widget.enabled
        ? P.inputBorder
        : widget.busy
            ? P.secondaryButtonHover
            : (_h ? Color.alphaBlend(Colors.white.withValues(alpha: 0.1), P.accent) : P.accent);
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _h = true),
        onExit: (_) => setState(() => _h = false),
        child: GestureDetector(
          onTap: widget.enabled ? widget.onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 24,
            height: 24,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
            child: Icon(
              widget.busy ? Codicons.primitiveSquare : Codicons.arrowUp,
              size: 16,
              color: widget.enabled ? Colors.white : P.fgFaint,
            ),
          ),
        ),
      ),
    );
  }
}

class _ContextRing extends StatelessWidget {
  const _ContextRing(this.value);
  final double value;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          value: value.clamp(0, 1),
          strokeWidth: 2,
          backgroundColor: P.inputBorder,
          color: value > 0.8 ? P.warn : P.fgMuted,
        ),
      );
}

// ------------------------------------------------------------------ menus

class _MenuEntry {
  _MenuEntry(this.value, this.label, {this.hint, this.icon, this.selected = false, this.dense = false})
      : header = false;
  _MenuEntry.header(this.label)
      : value = '',
        hint = null,
        icon = null,
        selected = false,
        dense = false,
        header = true;
  final String value, label;
  final String? hint;
  final IconData? icon;
  final bool selected, dense, header;
}

Future<T?> _showMenuAt<T>(BuildContext anchor, List<_MenuEntry> entries) {
  final box = anchor.findRenderObject() as RenderBox;
  final overlay = Overlay.of(anchor).context.findRenderObject() as RenderBox;
  final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
  final rect = RelativeRect.fromLTRB(
    topLeft.dx,
    topLeft.dy - 8,
    overlay.size.width - topLeft.dx - box.size.width,
    overlay.size.height - topLeft.dy,
  );
  return showMenu<T>(
    context: anchor,
    position: rect,
    menuPadding: const EdgeInsets.symmetric(vertical: 4),
    constraints: const BoxConstraints(minWidth: 220, maxWidth: 360),
    items: [
      for (final e in entries)
        if (e.header)
          PopupMenuItem<T>(
            enabled: false,
            height: 26,
            child: Text(e.label.toUpperCase(), style: uiText(size: 11, color: P.fgFaint, weight: FontWeight.w600)),
          )
        else
          PopupMenuItem<T>(
            value: e.value as T,
            height: e.dense ? 28 : (e.hint != null ? 44 : 32),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(children: [
              SizedBox(
                width: 20,
                child: e.selected ? Icon(Codicons.check, size: 14, color: P.fg) : null,
              ),
              if (e.icon != null) ...[Icon(e.icon, size: 15, color: P.fgMuted), const SizedBox(width: 8)],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(e.label, style: uiText()),
                  if (e.hint != null && e.hint!.isNotEmpty)
                    Text(e.hint!, style: uiText(size: 11.5, color: P.fgMuted), maxLines: 2, overflow: TextOverflow.ellipsis),
                ]),
              ),
            ]),
          ),
    ],
  );
}
