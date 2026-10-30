import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../codicons.dart';
import '../l10n.dart';
import '../memory.dart';
import '../theme.dart';
import 'markdown.dart';
import 'widgets.dart';

/// A memory note or CLAUDE.md, rendered like Obsidian: [[links]] open other notes and the
/// notes that link here are listed at the bottom. Can be edited and saved.
class NoteView extends StatefulWidget {
  const NoteView({super.key, required this.note, required this.index, required this.onOpenNote});
  final MemoryNote note;
  final MemoryIndex index;
  final void Function(MemoryNote) onOpenNote;
  @override
  State<NoteView> createState() => _NoteViewState();
}

class _NoteViewState extends State<NoteView> {
  bool _editing = false;
  late final _ctrl = TextEditingController();
  String _body = '';
  List<MemoryNote> _back = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _body = widget.note.read().replaceAll('\r\n', '\n');
    _back = widget.index.backlinks(widget.note);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _withLinks(String md) {
    // Hide the frontmatter block; show name/description as a header instead.
    var text = md;
    if (text.startsWith('---\n')) {
      final end = text.indexOf('\n---', 4);
      if (end > 0) text = text.substring(end + 4).trimLeft();
    }
    return text.replaceAllMapped(MemoryNote.linkRe, (m) {
      final name = m.group(1)!.trim();
      final exists = widget.index.bySlug(name) != null;
      return exists ? '[$name](note:${Uri.encodeComponent(name)})' : '*$name*';
    });
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.note;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          Expanded(child: Text(n.path, overflow: TextOverflow.ellipsis, style: uiText(size: 12, color: P.fgFaint))),
          if (_editing) ...[
            VsButton(S.cancel, primary: false, dense: true, onTap: () => setState(() => _editing = false)),
            const SizedBox(width: 6),
            VsButton(S.save, dense: true, onTap: () {
              File(n.path).writeAsStringSync(_ctrl.text);
              setState(() {
                _editing = false;
                _reload();
              });
            }),
          ] else
            IconBtn(Codicons.edit, size: 15, tooltip: S.edit, onTap: () {
              _ctrl.text = _body;
              setState(() => _editing = true);
            }),
        ]),
      ),
      Expanded(
        child: _editing
            ? Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: TextField(
                  controller: _ctrl,
                  expands: true,
                  maxLines: null,
                  style: monoText(size: 12.5, height: 1.5),
                  decoration: const InputDecoration(border: InputBorder.none),
                ),
              )
            : SelectionArea(
                child: ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 32), children: [
                  Text(n.title, style: uiText(size: 20, weight: FontWeight.w600, height: 1.3)),
                  if (n.description.isNotEmpty && n.kind == NoteKind.note)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 6),
                      child: Text(n.description, style: uiText(color: P.fgMuted)),
                    ),
                  const SizedBox(height: 10),
                  MarkdownView(
                    _withLinks(_body),
                    onOpenPath: (href) {
                      if (href.startsWith('note:')) {
                        final target = widget.index.bySlug(Uri.decodeComponent(href.substring(5)));
                        if (target != null) widget.onOpenNote(target);
                      }
                    },
                  ),
                  if (_back.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Divider(color: P.border, height: 1),
                    const SizedBox(height: 10),
                    Text(S.backlinks, style: uiText(size: 12, color: P.fgFaint, weight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    for (final b in _back)
                      HoverBox(
                        onTap: () => widget.onOpenNote(b),
                        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                        child: Row(children: [
                          Icon(Codicons.note, size: 13, color: P.fgMuted),
                          const SizedBox(width: 6),
                          Text(b.title, style: uiText(color: P.link)),
                        ]),
                      ),
                  ],
                ]),
              ),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ graph

/// Force-directed graph of notes and their [[links]]. Laid out once when opened.
class MemoryGraph extends StatefulWidget {
  const MemoryGraph({super.key, required this.index, required this.onOpenNote});
  final MemoryIndex index;
  final void Function(MemoryNote) onOpenNote;
  @override
  State<MemoryGraph> createState() => _MemoryGraphState();
}

class _MemoryGraphState extends State<MemoryGraph> {
  late final List<MemoryNote> _nodes = widget.index.notes.where((n) => n.kind == NoteKind.note || n.kind == NoteKind.memoryIndex).toList();
  late final List<(int, int)> _edges = _buildEdges();
  late final List<Offset> _layoutPos = _layout();
  late final List<Offset> _pos = List.of(_layoutPos);
  int? _hover;

  List<(int, int)> _buildEdges() {
    final idx = <String, int>{for (var i = 0; i < _nodes.length; i++) _nodes[i].slug.toLowerCase(): i};
    final out = <(int, int)>{};
    for (var i = 0; i < _nodes.length; i++) {
      for (final l in _nodes[i].links()) {
        final j = idx[l.toLowerCase()];
        if (j != null && j != i) out.add(i < j ? (i, j) : (j, i));
      }
    }
    return out.toList();
  }

  List<Offset> _layout() {
    final n = _nodes.length;
    final rnd = math.Random(7);
    final pos = List.generate(n, (i) {
      final a = i / math.max(1, n) * math.pi * 2;
      return Offset(math.cos(a) * 300 + rnd.nextDouble() * 20, math.sin(a) * 300 + rnd.nextDouble() * 20);
    });
    // Fruchterman–Reingold, a few hundred iterations is plenty for ~100 notes.
    const k = 70.0;
    for (var it = 0; it < 300; it++) {
      final disp = List.filled(n, Offset.zero);
      for (var i = 0; i < n; i++) {
        for (var j = i + 1; j < n; j++) {
          var d = pos[i] - pos[j];
          var dist = d.distance;
          if (dist < 0.01) {
            d = const Offset(0.1, 0.1);
            dist = 0.14;
          }
          final f = d / dist * (k * k / dist);
          disp[i] += f;
          disp[j] -= f;
        }
      }
      for (final (a, b) in _edges) {
        final d = pos[a] - pos[b];
        final dist = math.max(d.distance, 0.01);
        final f = d / dist * (dist * dist / k);
        disp[a] -= f;
        disp[b] += f;
      }
      final t = 30 * (1 - it / 300) + 1;
      for (var i = 0; i < n; i++) {
        final d = disp[i] - pos[i] * 0.02; // gentle pull to the centre
        final len = d.distance;
        if (len > 0) pos[i] += d / len * math.min(len, t);
      }
    }
    return pos;
  }

  @override
  Widget build(BuildContext context) {
    if (_nodes.isEmpty) return Center(child: Text(S.memoryEmpty, style: uiText(color: P.fgMuted)));
    final degree = List.filled(_nodes.length, 0);
    for (final (a, b) in _edges) {
      degree[a]++;
      degree[b]++;
    }
    return LayoutBuilder(builder: (context, box) {
      // Fit the whole graph into the view: positions are scaled, labels keep their size.
      var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
      for (final o in _layoutPos) {
        minX = math.min(minX, o.dx);
        minY = math.min(minY, o.dy);
        maxX = math.max(maxX, o.dx);
        maxY = math.max(maxY, o.dy);
      }
      final bw = math.max(maxX - minX, 1.0), bh = math.max(maxY - minY, 1.0);
      final fit = math.min((box.maxWidth - 120) / bw, (box.maxHeight - 90) / bh).clamp(0.05, 1.6);
      final mid = Offset((minX + maxX) / 2, (minY + maxY) / 2);
      for (var i = 0; i < _pos.length; i++) {
        _pos[i] = (_layoutPos[i] - mid) * fit;
      }
      final center = Offset(box.maxWidth / 2, box.maxHeight / 2 - 10);
      return InteractiveViewer(
        constrained: false,
        boundaryMargin: const EdgeInsets.all(2000),
        minScale: 0.2,
        maxScale: 4,
        child: SizedBox(
          width: box.maxWidth,
          height: box.maxHeight,
          child: MouseRegion(
            onHover: (e) {
              final i = _hit(e.localPosition - center);
              if (i != _hover) setState(() => _hover = i);
            },
            child: GestureDetector(
              onTapUp: (e) {
                final i = _hit(e.localPosition - center);
                if (i != null) widget.onOpenNote(_nodes[i]);
              },
              child: CustomPaint(
                painter: _GraphPainter(_nodes, _edges, _pos, degree, _hover, center),
                size: Size(box.maxWidth, box.maxHeight),
              ),
            ),
          ),
        ),
      );
    });
  }

  int? _hit(Offset local) {
    for (var i = 0; i < _pos.length; i++) {
      if ((_pos[i] - local).distance < 12) return i;
    }
    return null;
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter(this.nodes, this.edges, this.pos, this.degree, this.hover, this.center);
  final List<MemoryNote> nodes;
  final List<(int, int)> edges;
  final List<Offset> pos;
  final List<int> degree;
  final int? hover;
  final Offset center;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(center.dx, center.dy);
    final linked = <int>{};
    if (hover != null) {
      for (final (a, b) in edges) {
        if (a == hover) linked.add(b);
        if (b == hover) linked.add(a);
      }
    }
    for (final (a, b) in edges) {
      final hot = hover != null && (a == hover || b == hover);
      canvas.drawLine(
        pos[a],
        pos[b],
        Paint()
          ..color = hot ? P.accent.withValues(alpha: 0.8) : P.fgFaint.withValues(alpha: hover == null ? 0.35 : 0.12)
          ..strokeWidth = hot ? 1.4 : 1,
      );
    }
    for (var i = 0; i < nodes.length; i++) {
      final r = 4.0 + math.min(degree[i], 10) * 0.8;
      final hot = i == hover || linked.contains(i);
      final dim = hover != null && !hot;
      canvas.drawCircle(
        pos[i],
        r,
        Paint()..color = (i == hover ? P.accent : (nodes[i].kind == NoteKind.memoryIndex ? P.focus : P.fgMuted)).withValues(alpha: dim ? 0.3 : 1),
      );
      final tp = TextPainter(
        text: TextSpan(text: nodes[i].title, style: uiText(size: 11, color: dim ? P.fgFaint.withValues(alpha: 0.5) : (hot ? P.fg : P.fgMuted))),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 160);
      tp.paint(canvas, pos[i] + Offset(-tp.width / 2, r + 3));
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPainter old) => true; // ~100 nodes: repainting is cheap
}
