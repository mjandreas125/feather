import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../codicons.dart';
import '../l10n.dart';
import '../theme.dart';
import 'markdown.dart';
import 'widgets.dart';

/// A document shown in the editor area (a file, a memory note, the memory graph, …).
class DocTab {
  DocTab({required this.id, required this.title, required this.icon, required this.builder, this.tooltip});
  final String id;
  final String title;
  final IconData icon;
  final String? tooltip;
  final Widget Function(BuildContext context) builder;
}

/// Editor area: its own tab strip over the active document. Shown between the side panel
/// and the chat only while something is open, like VS Code's editor next to the chat.
class EditorArea extends StatelessWidget {
  const EditorArea({super.key, required this.docs, required this.active, required this.onSelect, required this.onClose});
  final List<DocTab> docs;
  final int active;
  final void Function(int) onSelect;
  final void Function(int) onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: P.bg,
      child: Column(children: [
        Container(
          height: 35,
          decoration: BoxDecoration(color: P.sideBg, border: Border(bottom: BorderSide(color: P.border))),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: docs.length,
            itemBuilder: (context, i) => _DocTabButton(
              doc: docs[i],
              active: i == active,
              onTap: () => onSelect(i),
              onClose: () => onClose(i),
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: active.clamp(0, docs.isEmpty ? 0 : docs.length - 1),
            children: [for (final d in docs) KeyedSubtree(key: ValueKey(d.id), child: Builder(builder: d.builder))],
          ),
        ),
      ]),
    );
  }
}

class _DocTabButton extends StatefulWidget {
  const _DocTabButton({required this.doc, required this.active, required this.onTap, required this.onClose});
  final DocTab doc;
  final bool active;
  final VoidCallback onTap, onClose;
  @override
  State<_DocTabButton> createState() => _DocTabButtonState();
}

class _DocTabButtonState extends State<_DocTabButton> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onTertiaryTapUp: (_) => widget.onClose(),
        child: Tooltip(
          message: widget.doc.tooltip ?? widget.doc.title,
          waitDuration: const Duration(milliseconds: 700),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 220),
            padding: const EdgeInsets.only(left: 10, right: 4),
            decoration: BoxDecoration(
              color: widget.active ? P.bg : (_h ? P.hover : P.sideBg),
              border: Border(
                top: BorderSide(color: widget.active ? P.focus : Colors.transparent),
                right: BorderSide(color: P.border),
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(widget.doc.icon, size: 14, color: widget.active ? P.fg : P.fgMuted),
              const SizedBox(width: 6),
              Flexible(
                child: Text(widget.doc.title,
                    overflow: TextOverflow.ellipsis, style: uiText(size: 12.5, color: widget.active ? P.fg : P.fgMuted)),
              ),
              const SizedBox(width: 4),
              Opacity(
                opacity: widget.active || _h ? 1 : 0,
                child: IconBtn(Codicons.close, size: 14, tooltip: S.close, onTap: widget.onClose),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ file view

const _imageExt = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'ico'};

/// Read-only file viewer with syntax highlighting and line numbers. Reloads when the file
/// changes on disk (e.g. Claude just edited it).
class FileView extends StatefulWidget {
  const FileView({super.key, required this.path, this.line, this.onMention, this.root});
  final String path;
  final int? line;
  final String? root;
  final void Function(String path)? onMention;
  @override
  State<FileView> createState() => _FileViewState();
}

class _FileViewState extends State<FileView> {
  String? _text;
  String? _error;
  DateTime? _mtime;
  Timer? _watch;
  final _vScroll = ScrollController();
  final _hScroll = ScrollController();
  TextSpan? _span;

  bool get _isImage => _imageExt.contains(p.extension(widget.path).replaceFirst('.', '').toLowerCase());

  @override
  void initState() {
    super.initState();
    _load();
    _watch = Timer.periodic(const Duration(seconds: 2), (_) => _checkChanged());
  }

  @override
  void dispose() {
    _watch?.cancel();
    _vScroll.dispose();
    _hScroll.dispose();
    super.dispose();
  }

  void _checkChanged() {
    try {
      final m = File(widget.path).lastModifiedSync();
      if (_mtime != null && m != _mtime) _load();
    } catch (_) {}
  }

  void _load() {
    final f = File(widget.path);
    try {
      _mtime = f.lastModifiedSync();
      if (_isImage) {
        setState(() {});
        return;
      }
      final len = f.lengthSync();
      if (len > 4 * 1024 * 1024) {
        setState(() => _error = S.fileTooBig);
        return;
      }
      final bytes = f.readAsBytesSync();
      if (bytes.take(8000).contains(0)) {
        setState(() => _error = S.binaryFile);
        return;
      }
      final text = utf8.decode(bytes, allowMalformed: true).replaceAll('\r\n', '\n');
      final lang = CodeHighlighter.forPath(widget.path);
      setState(() {
        _text = text;
        _error = null;
        _span = text.length < 400000
            ? CodeHighlighter.instance.highlight(text, lang, monoText(size: 12.5, height: 1.5))
            : TextSpan(text: text, style: monoText(size: 12.5, height: 1.5));
      });
      if (widget.line != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_vScroll.hasClients) {
            final target = ((widget.line! - 5).clamp(0, 1 << 30)) * 12.5 * 1.5;
            _vScroll.jumpTo(target.clamp(0, _vScroll.position.maxScrollExtent));
          }
        });
      }
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final rel = widget.root != null && p.isWithin(widget.root!, widget.path)
        ? p.relative(widget.path, from: widget.root!)
        : widget.path;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(children: [
          Expanded(
            child: Text(rel.replaceAll('\\', ' › ').replaceAll('/', ' › '),
                overflow: TextOverflow.ellipsis, style: uiText(size: 12, color: P.fgMuted)),
          ),
          if (widget.onMention != null)
            IconBtn(Codicons.mention, size: 14, tooltip: S.mentionInChat, onTap: () => widget.onMention!(widget.path)),
          IconBtn(Codicons.linkExternal, size: 14, tooltip: S.openExternally,
              onTap: () => launchUrl(Uri.file(widget.path))),
        ]),
      ),
      Expanded(child: _body()),
    ]);
  }

  Widget _body() {
    if (_isImage) {
      return InteractiveViewer(
        maxScale: 8,
        child: Center(child: Image.file(File(widget.path), key: ValueKey(_mtime))),
      );
    }
    if (_error != null) {
      return Center(child: Text(_error!, style: uiText(color: P.fgMuted)));
    }
    final text = _text;
    if (text == null) return const SizedBox.shrink();
    final lineCount = '\n'.allMatches(text).length + 1;
    final gutter = '$lineCount'.length * 7.6 + 18;
    final numbers = List.generate(lineCount, (i) => '${i + 1}').join('\n');
    return Scrollbar(
      controller: _vScroll,
      child: SingleChildScrollView(
        controller: _vScroll,
        padding: const EdgeInsets.only(top: 4, bottom: 40),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: gutter,
            child: Text(numbers,
                textAlign: TextAlign.right, style: monoText(size: 12.5, height: 1.5, color: P.fgFaint)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Scrollbar(
              controller: _hScroll,
              child: SingleChildScrollView(
                controller: _hScroll,
                scrollDirection: Axis.horizontal,
                child: SelectionArea(child: Text.rich(_span!, softWrap: false)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
