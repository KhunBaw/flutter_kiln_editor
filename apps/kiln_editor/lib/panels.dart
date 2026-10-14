import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageDescriptor, ImmutableBuffer;

import 'package:file_selector/file_selector.dart';
import 'package:flame/game.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kiln/kiln.dart';

import 'editor_state.dart';
import 'project.dart';
import 'theme.dart';

/// Short codes (E1, E2…) in hierarchy order, shared by hierarchy rows and scene markers.
Map<String, String> entityCodes(SceneDoc doc) {
  final out = <String, String>{};
  void walk(List<EntityNode> list) {
    for (final e in list) {
      out[e.id] = 'E${out.length + 1}';
      walk(e.children);
    }
  }

  walk(doc.entities);
  return out;
}

class HierarchyPanel extends StatelessWidget {
  const HierarchyPanel(this.s, {super.key});

  final EditorState s;

  @override
  Widget build(BuildContext context) {
    final codes = entityCodes(s.doc);
    Iterable<Widget> rows(List<EntityNode> list, int depth) sync* {
      for (final e in list) {
        yield _Row(
          code: codes[e.id]!,
          selected: e.id == s.selectedId,
          indent: depth * 14,
          onTap: () => s.select(e.id),
          trailing: [
            for (final b in e.behaviors)
              Container(
                width: 6,
                height: 14,
                margin: const EdgeInsets.only(left: 2),
                decoration: BoxDecoration(color: Family.of(b.type).color, borderRadius: BorderRadius.circular(1)),
              ),
          ],
          child: Text(e.name, overflow: TextOverflow.ellipsis),
        );
        yield* rows(e.children, depth + 1);
      }
    }

    return Column(
      children: [
        _Header('Hierarchy', [
          IconButton(tooltip: 'Add entity', icon: const Icon(Icons.add), onPressed: s.addEntity),
          IconButton(
            tooltip: 'Delete entity',
            icon: const Icon(Icons.delete_outline),
            onPressed: s.selectedId == null ? null : () => s.removeEntity(s.selectedId!),
          ),
        ]),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              _Row(
                code: 'SC',
                selected: s.selectedId == null,
                onTap: () => s.select(null),
                trailing: [Text('${_n(s.doc.size.x)}×${_n(s.doc.size.y)}', style: T.code)],
                child: Text(s.doc.name, style: T.body.copyWith(fontWeight: FontWeight.w600)),
              ),
              ...rows(s.doc.entities, 0),
              if (s.doc.entities.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: Text('No entities yet. Add one with +.', style: TextStyle(color: Z.z8)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Project images and audio. Drag an image onto the scene to place it as a Sprite entity.
class AssetsPanel extends StatefulWidget {
  const AssetsPanel(this.s, {super.key});

  final EditorState s;

  @override
  State<AssetsPanel> createState() => _AssetsPanelState();
}

class _AssetsPanelState extends State<AssetsPanel> {
  String? _key;
  late Future<List<List<String>>> _files;

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final dir = s.projectDir;
    // Listed once per project open / import, not on every edit.
    if (_key != '$dir#${s.assetsRevision}') {
      _key = '$dir#${s.assetsRevision}';
      _files = Future.wait([s.assetFiles('images'), s.assetFiles('audio')]);
    }
    return Column(
      children: [
        const _Header('Assets', []),
        Expanded(
          child: dir == null
              ? const Padding(
                  padding: EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: Text('Open a project to see its images and audio.', style: TextStyle(color: Z.z8)),
                )
              : FutureBuilder(
                  future: _files,
                  builder: (context, snap) {
                    final [images, audio] = snap.data ?? const [<String>[], <String>[]];
                    return ListView(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      children: [
                        for (final f in images) _imageRow(dir, f),
                        for (final f in audio) _assetRow(const Icon(Icons.graphic_eq, size: 14, color: Z.z8), f),
                        if (snap.hasError)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                            child: Text(
                              'Could not list assets: ${snap.error}',
                              style: const TextStyle(color: Z.danger),
                            ),
                          )
                        else if (snap.hasData && images.isEmpty && audio.isEmpty)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(12, 10, 12, 0),
                            child: Text(
                              'No files in assets/images or assets/audio yet.',
                              style: TextStyle(color: Z.z8),
                            ),
                          ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _imageRow(String dir, String file) {
    final thumb = SizedBox.square(
      dimension: 18,
      child: Image.file(
        File('$dir/assets/images/$file'),
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined, size: 14, color: Z.z7),
      ),
    );
    return Draggable<AssetDrop>(
      data: AssetDrop(file),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Z.z4,
        shape: const RoundedRectangleBorder(
          side: BorderSide(color: Z.mark),
          borderRadius: BorderRadius.all(Radius.circular(2)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              thumb,
              const SizedBox(width: 6),
              Text(file, style: T.body),
            ],
          ),
        ),
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Tooltip(message: 'Drag onto the scene', child: _assetRow(thumb, file)),
      ),
    );
  }

  Widget _assetRow(Widget icon, String file) => SizedBox(
    height: 28,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Align(alignment: Alignment.centerLeft, child: icon),
          ),
          Expanded(child: Text(file, overflow: TextOverflow.ellipsis)),
        ],
      ),
    ),
  );
}

/// An image file name being dragged from [AssetsPanel].
class AssetDrop {
  const AssetDrop(this.image);

  final String image;
}

class _Row extends StatelessWidget {
  const _Row({
    required this.code,
    required this.selected,
    required this.onTap,
    required this.child,
    this.indent = 0,
    this.trailing = const [],
  });

  final String code;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final double indent;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Material(
        color: selected ? Z.z4 : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          hoverColor: Z.z3,
          focusColor: Z.z4,
          child: SizedBox(
            height: 30,
            child: Padding(
              padding: EdgeInsets.only(left: 12 + indent, right: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
                    child: Text(code, style: T.code.copyWith(color: selected ? Z.mark : Z.z8)),
                  ),
                  Expanded(child: child),
                  ...trailing,
                ],
              ),
            ),
          ),
        ),
      ),
      // Marker inset bar: the contract's selection mark, readable at a glance.
      if (selected) const Positioned(left: 0, top: 0, bottom: 0, width: 3, child: ColoredBox(color: Z.mark)),
    ],
  );
}

/// Frames a scene on the map board at fit scale × [zoom], shifted by [pan]. Edit and Play share it,
/// so at the default view Play never jumps.
class SceneFrame extends StatelessWidget {
  const SceneFrame({
    super.key,
    required this.size,
    required this.caption,
    required this.child,
    this.overlay,
    this.zoom = 1,
    this.pan = Offset.zero,
    this.footer = const [],
  });

  final Vector2 size;
  final String caption;

  /// Laid out at scene size, then scaled to fit.
  final Widget child;

  /// Board-level widgets in screen pixels (crisp at any scale, hit-testable past the scene edge);
  /// [origin] is the scene's top-left on the board.
  final List<Widget> Function(double scale, Offset origin)? overlay;
  final double zoom;
  final Offset pan;

  /// Board controls, bottom right.
  final List<Widget> footer;

  static const pad = 40.0;

  static double fitScale(Size box, Vector2 size) =>
      math.max(0.05, math.min((box.width - pad * 2) / size.x, (box.height - pad * 2) / size.y));

  /// Screen offset of the scene's top-left inside a board of [box].
  static Offset originOf(Size box, Vector2 size, double scale, Offset pan) =>
      Offset((box.width - size.x * scale) / 2, (box.height - size.y * scale) / 2) + pan;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: const _BoardPainter(),
    child: LayoutBuilder(
      builder: (context, box) {
        final scale = fitScale(box.biggest, size) * zoom;
        final o = originOf(box.biggest, size, scale, pan);
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: o.dx - 1,
              top: o.dy - 1,
              width: size.x * scale + 2,
              height: size.y * scale + 2,
              child: DecoratedBox(
                decoration: BoxDecoration(border: Border.all(color: Z.z5)),
                child: Padding(
                  padding: const EdgeInsets.all(1),
                  child: FittedBox(
                    child: SizedBox(width: size.x, height: size.y, child: child),
                  ),
                ),
              ),
            ),
            ...?overlay?.call(scale, o),
            Positioned(
              left: 16,
              bottom: 12,
              child: Text(
                '${caption.toUpperCase()} · ${_n(size.x)} × ${_n(size.y)} · ${(scale * 100).round()}%',
                style: T.label,
              ),
            ),
            if (footer.isNotEmpty) Positioned(right: 8, bottom: 6, child: Row(children: footer)),
          ],
        );
      },
    ),
  );
}

/// Matte map board: a dot every 24px.
class _BoardPainter extends CustomPainter {
  const _BoardPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Z.z0);
    final dot = Paint()..color = Z.z3;
    for (var y = 12.0; y < size.height; y += 24) {
      for (var x = 12.0; x < size.width; x += 24) {
        canvas.drawRect(Rect.fromLTWH(x, y, 1.5, 1.5), dot);
      }
    }
  }

  @override
  bool shouldRepaint(_BoardPainter old) => false;
}

/// Snap grid over the scene, in screen pixels; hidden when cells get too small to read.
class _GridPainter extends CustomPainter {
  const _GridPainter(this.step);

  final double step;

  @override
  void paint(Canvas canvas, Size size) {
    if (step < 6) return;
    final p = Paint()..color = Z.z10.withValues(alpha: 0.07);
    for (var x = step; x < size.width; x += step) {
      canvas.drawRect(Rect.fromLTWH(x.roundToDouble(), 0, 1, size.height), p);
    }
    for (var y = step; y < size.height; y += step) {
      canvas.drawRect(Rect.fromLTWH(0, y.roundToDouble(), size.width, 1), p);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.step != step;
}

/// Static preview: rebuilds a [KilnGame] from a copy of the doc on every change, with input disabled.
/// Frames the whole world; the view (what the camera shows at start) is outlined when the world is larger.
class SceneView extends StatefulWidget {
  const SceneView(this.s, this.registry, {super.key});

  final EditorState s;
  final KilnRegistry registry;

  @override
  State<SceneView> createState() => _SceneViewState();
}

class _SceneViewState extends State<SceneView> {
  int _rev = -1;
  late KilnGame _game;
  final _sceneKey = GlobalKey();
  String? _drag;
  int _dragCount = 0;
  Offset _dragStart = Offset.zero;
  Vector2 _dragFrom = Vector2.zero();
  Vector2 _sizeFrom = Vector2.zero();
  double _angleFrom = 0;
  Offset _handleAt = Offset.zero;

  /// Board pan in progress (space or middle button); entity drags are ignored meanwhile.
  bool _panning = false;
  double _pinchFrom = 1;
  Size _box = Size.zero;

  EditorState get s => widget.s;

  /// Scales about [focal] (board pixels) so the scene point under it stays put.
  void _zoomAt(Offset focal, double zoom) {
    final world = s.doc.worldSize;
    final fit = SceneFrame.fitScale(_box, world);
    final z = zoom.clamp(0.1, 16).toDouble();
    final o = SceneFrame.originOf(_box, world, fit * s.zoom, s.pan);
    final p = (focal - o) / (fit * s.zoom);
    final o2 = SceneFrame.originOf(_box, world, fit * z, Offset.zero);
    s.setView(zoom: z, pan: focal - o2 - p * (fit * z));
  }

  void _fit() => s.setView(zoom: 1, pan: Offset.zero);

  @override
  Widget build(BuildContext context) {
    if (_rev != s.revision) {
      _rev = s.revision;
      _game = KilnGame(
        s.copyDoc(),
        registry: widget.registry,
        editing: true,
        bundle: s.projectDir == null ? null : DirBundle(s.projectDir!),
      );
    }
    final world = s.doc.worldSize;
    final sel = s.selectedId == null ? null : _rectOf(s.doc.entities, s.selectedId!, Offset.zero);
    final code = s.selectedId == null ? null : entityCodes(s.doc)[s.selectedId];
    return LayoutBuilder(
      builder: (context, box) {
        _box = box.biggest;
        return Listener(
          onPointerDown: (e) {
            final space = HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.space);
            _panning = e.buttons == kMiddleMouseButton || (space && e.buttons == kPrimaryMouseButton);
            // Clicking the board leaves any inspector field, so Space pans instead of typing.
            FocusManager.instance.primaryFocus?.unfocus();
          },
          onPointerMove: (e) {
            if (_panning) s.setView(pan: s.pan + e.delta);
          },
          onPointerUp: (_) => _panning = false,
          onPointerCancel: (_) => _panning = false,
          onPointerSignal: (e) {
            if (e is! PointerScrollEvent) return;
            if (HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed) {
              _zoomAt(e.localPosition, s.zoom * math.pow(1.0015, -e.scrollDelta.dy));
            } else {
              s.setView(pan: s.pan - e.scrollDelta);
            }
          },
          onPointerPanZoomStart: (_) => _pinchFrom = 1,
          onPointerPanZoomUpdate: (e) {
            if (e.scale != _pinchFrom) {
              _zoomAt(e.localPosition, s.zoom * e.scale / _pinchFrom);
              _pinchFrom = e.scale;
            }
            s.setView(pan: s.pan + e.localPanDelta);
          },
          child: SceneFrame(
            size: world,
            caption: 'Scene',
            zoom: s.zoom,
            pan: s.pan,
            footer: _footer(),
            overlay: (k, o) => [
              if (s.grid > 0)
                Positioned(
                  left: o.dx,
                  top: o.dy,
                  width: world.x * k,
                  height: world.y * k,
                  child: IgnorePointer(child: CustomPaint(painter: _GridPainter(s.grid * k))),
                ),
              if (world != s.doc.size) ..._view(s.doc.size, k, o),
              if (sel != null)
                ..._selection(
                  Rect.fromLTRB(sel.left * k, sel.top * k, sel.right * k, sel.bottom * k).shift(o),
                  code,
                  k,
                ),
            ],
            child: DragTarget<AssetDrop>(
              onAcceptWithDetails: (d) => _place(d.data.image, d.offset),
              builder: (context, hover, _) => GestureDetector(
                key: _sceneKey,
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => s.select(_hit(s.doc.entities, d.localPosition, Offset.zero)),
                onPanStart: (d) {
                  if (_panning) return;
                  final id = _hit(s.doc.entities, d.localPosition, Offset.zero);
                  s.select(id);
                  _drag = id == null ? null : '$id.drag${_dragCount++}';
                  _dragStart = d.localPosition;
                  _dragFrom = s.selected?.position.clone() ?? Vector2.zero();
                },
                onPanUpdate: (d) {
                  final e = s.selected;
                  if (_panning || _drag == null || e == null) return;
                  // One undo step per drag gesture; the top-left corner snaps to the grid.
                  final o = d.localPosition - _dragStart;
                  final half = e.size / 2;
                  final p = Vector2(
                    s.snap(_dragFrom.x + o.dx - half.x) + half.x,
                    s.snap(_dragFrom.y + o.dy - half.y) + half.y,
                  );
                  if (p != e.position) s.edit((_) => e.position = p, mergeKey: _drag);
                },
                onPanEnd: (_) => _drag = null,
                child: IgnorePointer(
                  child: GameWidget(key: ValueKey(_rev), game: _game, autofocus: false),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Drops [image] where the pointer is (global [at]) as a Sprite entity at its natural size (≤ 512).
  Future<void> _place(String image, Offset at) async {
    final box = _sceneKey.currentContext?.findRenderObject() as RenderBox?;
    final dir = s.projectDir;
    if (box == null || dir == null) return;
    final p = box.globalToLocal(at);
    var size = Vector2.all(64);
    try {
      final buf = await ImmutableBuffer.fromUint8List(await File('$dir/assets/images/$image').readAsBytes());
      final desc = await ImageDescriptor.encoded(buf);
      final k = math.min(1.0, 512 / math.max(desc.width, desc.height));
      size = Vector2((desc.width * k).roundToDouble(), (desc.height * k).roundToDouble());
      desc.dispose();
      buf.dispose();
    } catch (_) {
      // Unreadable image: keep 64×64; the Sprite itself logs the load error.
    }
    final dot = image.lastIndexOf('.');
    s.addEntity(
      name: dot > 0 ? image.substring(0, dot) : image,
      at: Vector2(s.snap(p.dx - size.x / 2) + size.x / 2, s.snap(p.dy - size.y / 2) + size.y / 2),
      size: size,
      behaviors: [
        BehaviorData('Sprite', {'image': image}),
      ],
    );
  }

  List<Widget> _footer() {
    Widget btn(String label, String tip, VoidCallback onPressed) => Tooltip(
      message: tip,
      child: TextButton(onPressed: onPressed, child: Text(label)),
    );
    return [
      PopupMenuButton<double>(
        tooltip: 'Snap grid',
        position: PopupMenuPosition.over,
        initialValue: s.grid,
        onSelected: (g) => s.setView(grid: g),
        itemBuilder: (_) => [
          for (final g in const [0.0, 4.0, 8.0, 16.0, 32.0, 64.0])
            PopupMenuItem(value: g, height: 30, child: Text(g == 0 ? 'Off' : '${g.toInt()} px')),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(s.grid == 0 ? 'GRID OFF' : 'GRID ${s.grid.toInt()}', style: T.label.copyWith(color: Z.z9)),
        ),
      ),
      btn('−', 'Zoom out (⌘ scroll)', () => _zoomAt(_box.center(Offset.zero), s.zoom / 1.25)),
      btn('+', 'Zoom in (⌘ scroll)', () => _zoomAt(_box.center(Offset.zero), s.zoom * 1.25)),
      btn('FIT', 'Fit the world (pan: space or middle drag, two-finger scroll)', _fit),
    ];
  }

  /// The camera's starting view inside a larger world.
  List<Widget> _view(Vector2 view, double k, Offset o) => [
    Positioned(
      left: o.dx,
      top: o.dy,
      width: view.x * k,
      height: view.y * k,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(border: Border.all(color: Z.z7)),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 0, 4),
              child: Text('VIEW', style: T.label.copyWith(color: Z.z7)),
            ),
          ),
        ),
      ),
    ),
  ];

  /// Marker chit: a 1px rule, a code tag, a resize tab (bottom right) and a rotate tab on a stalk above.
  List<Widget> _selection(Rect r, String? code, double k) {
    final e = s.selected;
    const stalk = 18.0;
    final rot = Offset(r.center.dx, r.top - stalk);
    return [
      Positioned.fromRect(
        rect: r.inflate(1),
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(border: Border.all(color: Z.mark)),
          ),
        ),
      ),
      Positioned(
        left: r.left - 4,
        top: r.top - 4,
        child: const IgnorePointer(
          child: SizedBox.square(dimension: 8, child: ColoredBox(color: Z.mark)),
        ),
      ),
      Positioned(
        left: rot.dx - 0.5,
        top: rot.dy,
        width: 1,
        height: stalk,
        child: const IgnorePointer(child: ColoredBox(color: Z.mark)),
      ),
      if (e != null) ...[
        _handle(
          r.bottomRight,
          'Resize (snaps to grid)',
          SystemMouseCursors.resizeDownRight,
          onStart: () {
            _sizeFrom = e.size.clone();
            _dragFrom = e.position - e.size / 2;
          },
          onMove: (o) {
            final tl = _dragFrom; // top-left at drag start
            final w = math.max(1.0, s.snap(_sizeFrom.x + o.dx / k)), h = math.max(1.0, s.snap(_sizeFrom.y + o.dy / k));
            final size = Vector2(w, h);
            if (size != e.size) {
              s.edit((_) {
                e.size = size;
                e.position = tl + size / 2;
              }, mergeKey: _drag);
            }
          },
        ),
        _handle(
          rot,
          'Rotate (⇧ snaps to 15°)',
          SystemMouseCursors.grab,
          circle: true,
          onStart: () {
            _angleFrom = e.angle;
            _handleAt = rot - r.center;
          },
          onMove: (o) {
            final v = _handleAt + o;
            var a = _angleFrom + math.atan2(v.dx, -v.dy);
            if (HardwareKeyboard.instance.isShiftPressed) a = (a / (math.pi / 12)).roundToDouble() * (math.pi / 12);
            a = double.parse(a.toStringAsFixed(4));
            if (a != e.angle) s.edit((_) => e.angle = a, mergeKey: _drag);
          },
        ),
      ],
      Positioned(
        left: r.left - 1,
        top: r.top - 24 - stalk,
        child: IgnorePointer(
          child: Container(
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            color: Z.mark,
            child: Text(
              '${code ?? ''} · ${widget.s.selected?.name.toUpperCase() ?? ''}',
              style: T.head.copyWith(color: Z.z1, letterSpacing: 0.8),
            ),
          ),
        ),
      ),
    ];
  }

  /// A draggable 8px tab centred on [at]; [onMove] gets the total pointer offset in screen pixels.
  Widget _handle(
    Offset at,
    String tip,
    MouseCursor cursor, {
    required VoidCallback onStart,
    required void Function(Offset total) onMove,
    bool circle = false,
  }) {
    var total = Offset.zero;
    // 16px hit area around an 8px mark, so the tab is easy to grab at any zoom.
    return Positioned(
      left: at.dx - 8,
      top: at.dy - 8,
      child: Tooltip(
        message: tip,
        child: MouseRegion(
          cursor: cursor,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) {
              total = Offset.zero;
              _drag = '${s.selectedId}.handle${_dragCount++}';
              onStart();
            },
            onPanUpdate: (d) => onMove(total += d.delta),
            onPanEnd: (_) => _drag = null,
            child: SizedBox.square(
              dimension: 16,
              child: Center(
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: Z.mark, shape: circle ? BoxShape.circle : BoxShape.rectangle),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Topmost entity under [p]: later siblings and children draw on top, so search them first. Ignores angle.
  static String? _hit(List<EntityNode> list, Offset p, Offset origin) {
    for (final e in list.reversed) {
      final r = Rect.fromCenter(center: origin + Offset(e.position.x, e.position.y), width: e.size.x, height: e.size.y);
      final c = _hit(e.children, p, r.topLeft);
      if (c != null) return c;
      if (r.contains(p)) return e.id;
    }
    return null;
  }

  // Children are positioned relative to the parent's top-left (Flame local space). Ignores angle.
  static Rect? _rectOf(List<EntityNode> list, String id, Offset origin) {
    for (final e in list) {
      final r = Rect.fromCenter(center: origin + Offset(e.position.x, e.position.y), width: e.size.x, height: e.size.y);
      if (e.id == id) return r;
      final c = _rectOf(e.children, id, r.topLeft);
      if (c != null) return c;
    }
    return null;
  }
}

class InspectorPanel extends StatelessWidget {
  const InspectorPanel(this.s, this.registry, {super.key});

  final EditorState s;
  final KilnRegistry registry;

  @override
  Widget build(BuildContext context) {
    final e = s.selected;
    return Column(
      children: [
        _Header(e == null ? 'Scene' : 'Inspector', [
          if (e != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(entityCodes(s.doc)[e.id] ?? '', style: T.code.copyWith(color: Z.mark)),
            ),
        ]),
        Expanded(
          child: CustomScrollView(
            slivers: e == null
                ? [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
                      sliver: SliverList.list(children: _scene()),
                    ),
                  ]
                : _entity(e),
          ),
        ),
      ],
    );
  }

  List<Widget> _scene() {
    final d = s.doc;
    final vars = d.variables.entries.toList();
    return [
      Field('name', d.name, (v) => s.edit((d) => d.name = v as String, mergeKey: 'scene.name')),
      _Pair(
        Field('w', d.size.x, (v) => s.edit((d) => d.size.x = v as double, mergeKey: 'scene.w'), parse: parseNumber),
        Field('h', d.size.y, (v) => s.edit((d) => d.size.y = v as double, mergeKey: 'scene.h'), parse: parseNumber),
      ),
      // World defaults to the view; a larger world scrolls under a Camera behavior.
      _Pair(
        Field(
          'world w',
          d.worldSize.x,
          (v) => s.edit((d) => d.world = Vector2(v as double, d.worldSize.y), mergeKey: 'scene.ww'),
          parse: parseNumber,
        ),
        Field(
          'world h',
          d.worldSize.y,
          (v) => s.edit((d) => d.world = Vector2(d.worldSize.x, v as double), mergeKey: 'scene.wh'),
          parse: parseNumber,
        ),
      ),
      _Rule('Variables'),
      for (final (i, kv) in vars.indexed)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Field('name', kv.key, (v) {
                final name = v as String;
                if (name.isEmpty || d.variables.containsKey(name)) return;
                s.edit(
                  (d) => d.variables = {for (final x in d.variables.entries) x.key == kv.key ? name : x.key: x.value},
                  mergeKey: 'var$i.name',
                );
              }),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Field(
                'value',
                kv.value,
                (v) => s.edit((d) => d.variables[kv.key] = v, mergeKey: 'var$i.value'),
                parse: (t) => num.tryParse(t) ?? t,
              ),
            ),
            IconButton(
              tooltip: 'Remove variable',
              icon: const Icon(Icons.close),
              onPressed: () => s.edit((d) => d.variables.remove(kv.key)),
            ),
          ],
        ),
      if (vars.isEmpty) const Text('No variables. Text can show one as {name}.', style: TextStyle(color: Z.z8)),
      const SizedBox(height: 8),
      _AddButton(
        'Add variable',
        onPressed: () => s.edit((d) {
          var n = d.variables.length + 1;
          while (d.variables.containsKey('var$n')) {
            n++;
          }
          d.variables['var$n'] = 0;
        }),
      ),
    ];
  }

  List<Widget> _entity(EntityNode e) {
    Field n(String label, double value, void Function(double v) set) =>
        Field(label, value, (v) => s.edit((_) => set(v as double), mergeKey: '${e.id}.$label'), parse: parseNumber);
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        sliver: SliverList.list(
          children: [
            Field('name', e.name, (v) => s.edit((_) => e.name = v as String, mergeKey: '${e.id}.name')),
            _Pair(n('x', e.position.x, (v) => e.position.x = v), n('y', e.position.y, (v) => e.position.y = v)),
            _Pair(n('w', e.size.x, (v) => e.size.x = v), n('h', e.size.y, (v) => e.size.y = v)),
            _Pair(n('angle', e.angle, (v) => e.angle = v), const SizedBox()),
            Field(
              'tags',
              e.tags.join(', '),
              (v) => s.edit(
                (_) => e.tags = [
                  for (final t in (v as String).split(','))
                    if (t.trim().isNotEmpty) t.trim(),
                ],
                mergeKey: '${e.id}.tags',
              ),
              // Commit only when the parsed list differs, so typing ", " doesn't fight the field.
              parse: (t) => [
                for (final x in t.split(','))
                  if (x.trim().isNotEmpty) x.trim(),
              ].join(', '),
            ),
          ],
        ),
      ),
      for (final (i, b) in e.behaviors.indexed)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          sliver: _Counter(
            key: ValueKey('${e.id}.b$i.${b.type}'),
            type: b.type,
            factor: factorOf(b),
            onRemove: () => s.edit((_) => e.behaviors.removeAt(i)),
            children: [
              if (registry.behaviors[b.type] case final def?)
                for (final p in def.props) propEditor(s, registry, p, b.props, '${e.id}.b$i', caseNo: i + 1)
              else
                Text('No schema for "${b.type}". Kept as-is in the file.', style: const TextStyle(color: Z.z8)),
            ],
          ),
        ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
        sliver: SliverToBoxAdapter(
          child: _AddMenu('Add behavior', registry.behaviors.keys, (type) {
            final def = registry.behaviors[type]!;
            s.edit((_) => e.behaviors.add(BehaviorData(type, {for (final p in def.props) p.key: p.defaultValue})));
          }),
        ),
      ),
    ];
  }
}

/// A behavior as a die-cut counter: family field, name, and its key factors on the face.
class _Counter extends StatefulWidget {
  const _Counter({super.key, required this.type, required this.factor, required this.onRemove, required this.children});

  final String type;
  final String factor;
  final VoidCallback onRemove;
  final List<Widget> children;

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final fam = Family.of(widget.type);
    final body = _open && widget.children.isNotEmpty;
    final head = Material(
      color: Z.z1,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Z.z4),
        borderRadius: body ? const BorderRadius.vertical(top: Radius.circular(3)) : BorderRadius.circular(3),
      ),
      child: InkWell(
        onTap: () => setState(() => _open = !_open),
        hoverColor: Z.z3,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 30,
              color: fam.color,
              alignment: Alignment.center,
              child: Text(fam.letter, style: T.head.copyWith(color: Z.z1, letterSpacing: 0)),
            ),
            const SizedBox(width: 10),
            Center(
              child: Text(widget.type.toUpperCase(), style: T.head.copyWith(color: Z.z10)),
            ),
            const Spacer(),
            // Factor strip: the counter's printed stats, a compact ruled chit sized to its content.
            if (widget.factor.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: const BoxDecoration(
                    border: Border(
                      left: BorderSide(color: Z.z4),
                      right: BorderSide(color: Z.z4),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    widget.factor,
                    style: T.code.copyWith(color: Z.z10, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            Center(
              child: IconButton(tooltip: 'Remove behavior', icon: const Icon(Icons.close), onPressed: widget.onRemove),
            ),
          ],
        ),
      ),
    );
    // The header pins while its body scrolls, so a counter never loses its family mid-scroll.
    return SliverMainAxisGroup(
      slivers: [
        SliverPersistentHeader(pinned: true, delegate: _PinnedHead(head)),
        if (body)
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                color: Z.z1,
                border: Border(
                  left: BorderSide(color: Z.z4),
                  right: BorderSide(color: Z.z4),
                  bottom: BorderSide(color: Z.z4),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: widget.children),
            ),
          ),
      ],
    );
  }
}

class _PinnedHead extends SliverPersistentHeaderDelegate {
  _PinnedHead(this.child);

  final Widget child;

  @override
  double get minExtent => 34;

  @override
  double get maxExtent => 34;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => child;

  @override
  bool shouldRebuild(_PinnedHead old) => true;
}

/// `fontSize` → `FONT SIZE`.
String _label(String key) => key.replaceAllMapped(RegExp(r'(?<=[a-z])([A-Z])'), (m) => ' ${m[1]}').toUpperCase();

/// Builds an editor widget for one [PropDef]; [map] is mutated in place inside [EditorState.edit].
Widget propEditor(EditorState s, KilnRegistry reg, PropDef d, Map<String, Object?> map, String id, {int caseNo = 0}) {
  final v = map[d.key] ?? d.defaultValue;
  void set(Object? x, {bool merge = true}) => s.edit((_) => map[d.key] = x, mergeKey: merge ? '$id.${d.key}' : null);
  return switch (d.kind) {
    PropKind.number => Field(d.key, v, set, parse: parseNumber),
    PropKind.string => Field(d.key, v, set),
    PropKind.image || PropKind.audio => Builder(
      builder: (context) => Field(
        d.key,
        v,
        set,
        trailing: IconButton(
          tooltip: 'Import ${d.kind.name}',
          icon: const Icon(Icons.file_upload_outlined),
          onPressed: () async {
            final image = d.kind == PropKind.image;
            try {
              final f = await openFile(
                acceptedTypeGroups: [
                  XTypeGroup(
                    label: d.kind.name,
                    extensions: image ? ['png', 'jpg', 'jpeg', 'webp'] : ['wav', 'mp3', 'ogg', 'm4a'],
                  ),
                ],
              );
              if (f != null) set(await s.importAsset(f.path, image ? 'images' : 'audio'), merge: false);
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e')));
              }
            }
          },
        ),
      ),
    ),
    PropKind.color => Field(
      d.key,
      v,
      set,
      leading: Container(
        width: 18,
        height: 18,
        margin: const EdgeInsets.only(right: 6),
        decoration: BoxDecoration(
          color: Props({'c': v}).color('c'),
          border: Border.all(color: Z.z6),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    ),
    PropKind.bool => _Labeled(
      d.key,
      Align(
        alignment: Alignment.centerLeft,
        child: Checkbox(value: v == true, onChanged: (x) => set(x == true, merge: false)),
      ),
    ),
    PropKind.choice => _Labeled(
      d.key,
      DropdownButtonFormField<String>(
        key: ValueKey('$id.${d.key}=$v'),
        initialValue: d.options.contains(v) ? v as String : null,
        isDense: true,
        decoration: const InputDecoration(contentPadding: EdgeInsets.fromLTRB(8, 4, 4, 4)),
        dropdownColor: Z.z0,
        style: T.value,
        iconEnabledColor: Z.z8,
        items: [for (final o in d.options) DropdownMenuItem(value: o, child: Text(o))],
        onChanged: (x) => set(x, merge: false),
      ),
    ),
    PropKind.actions => _actions(s, reg, d, v is List ? v : const [], (x) => set(x, merge: false), id, caseNo),
  };
}

/// Action chains as numbered rule cases (4.1, 4.2) joined by one connector rule.
Widget _actions(
  EditorState s,
  KilnRegistry reg,
  PropDef d,
  List<Object?> list,
  void Function(List<Object?>) set,
  String id,
  int caseNo,
) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _Rule(_label(d.key)),
      for (final (i, raw) in list.indexed)
        if (raw is Map<String, Object?>)
          Container(
            margin: const EdgeInsets.only(left: 4, bottom: 2),
            padding: const EdgeInsets.only(left: 10),
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: Z.z5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 28,
                  child: Row(
                    children: [
                      SizedBox(width: 34, child: Text('$caseNo.${i + 1}', style: T.code)),
                      Expanded(
                        child: Text('${raw['type']}', style: T.body.copyWith(fontWeight: FontWeight.w600)),
                      ),
                      IconButton(
                        tooltip: 'Remove action',
                        icon: const Icon(Icons.close),
                        onPressed: () => set([...list]..removeAt(i)),
                      ),
                    ],
                  ),
                ),
                if (reg.actions[raw['type']]?.targeted ?? true) _target(s, raw, '$id.${d.key}.$i'),
                for (final p in reg.actions[raw['type']]?.props ?? const <PropDef>[])
                  propEditor(s, reg, p, raw, '$id.${d.key}.$i'),
              ],
            ),
          ),
      const SizedBox(height: 6),
      _AddMenu('Add action', reg.actions.keys, (type) {
        final def = reg.actions[type]!;
        set([
          ...list,
          {'type': type, for (final p in def.props) p.key: p.defaultValue},
        ]);
      }),
      const SizedBox(height: 6),
    ],
  );
}

/// Who an action acts on: empty = self, an entity name, or `#tag`; the menu lists what the scene has.
Widget _target(EditorState s, Map<String, Object?> raw, String id) {
  final names = <String>{}, tags = <String>{};
  void walk(List<EntityNode> list) {
    for (final e in list) {
      names.add(e.name);
      tags.addAll(e.tags);
      walk(e.children);
    }
  }

  walk(s.doc.entities);
  void set(Object? v, {bool merge = true}) => s.edit(
    (_) => (v == '' ? raw.remove(KilnRegistry.targetKey) : raw[KilnRegistry.targetKey] = v),
    mergeKey: merge ? '$id.target' : null,
  );
  return Field(
    'target',
    raw[KilnRegistry.targetKey] ?? '',
    set,
    hint: 'self',
    trailing: PopupMenuButton<String>(
      tooltip: 'Pick target',
      icon: const Icon(Icons.arrow_drop_down),
      position: PopupMenuPosition.under,
      onSelected: (v) => set(v, merge: false),
      itemBuilder: (_) => [
        const PopupMenuItem(value: '', height: 30, child: Text('self')),
        for (final n in names) PopupMenuItem(value: n, height: 30, child: Text(n)),
        for (final t in tags) PopupMenuItem(value: '#$t', height: 30, child: Text('#$t')),
      ],
    ),
  );
}

Object? parseNumber(String t) {
  final d = double.tryParse(t);
  return d != null && d.isFinite ? d : null;
}

class _Labeled extends StatelessWidget {
  const _Labeled(this.label, this.child);

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        SizedBox(
          width: 74,
          child: Text(_label(label), style: T.label, overflow: TextOverflow.ellipsis),
        ),
        Expanded(child: child),
      ],
    ),
  );
}

/// Text field that commits on every valid keystroke and re-syncs when the doc changes underneath (undo).
class Field extends StatefulWidget {
  const Field(this.label, this.value, this.onChanged, {super.key, this.parse, this.leading, this.trailing, this.hint});

  final String label;
  final Object? value;
  final ValueChanged<Object?> onChanged;

  /// Returns null for invalid input (not committed). Defaults to the raw string.
  final Object? Function(String text)? parse;
  final Widget? leading;
  final Widget? trailing;
  final String? hint;

  @override
  State<Field> createState() => _FieldState();
}

class _FieldState extends State<Field> {
  late final _c = TextEditingController(text: _fmt(widget.value));

  Object? _parse(String t) => widget.parse == null ? t : widget.parse!(t);

  static String _fmt(Object? v) => switch (v) {
    null => '',
    double d when d.isFinite && d == d.roundToDouble() => d.toInt().toString(),
    _ => '$v',
  };

  @override
  void didUpdateWidget(Field old) {
    super.didUpdateWidget(old);
    if (_parse(_c.text) != widget.value) _c.text = _fmt(widget.value);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Labeled(
    widget.label,
    Row(
      children: [
        ?widget.leading,
        Expanded(
          child: TextField(
            controller: _c,
            style: T.value,
            decoration: InputDecoration(hintText: widget.hint),
            onChanged: (t) {
              final v = _parse(t);
              if (v != null && v != widget.value) widget.onChanged(v);
            },
          ),
        ),
        ?widget.trailing,
      ],
    ),
  );
}

class _Pair extends StatelessWidget {
  const _Pair(this.a, this.b);

  final Widget a, b;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: a),
      const SizedBox(width: 12),
      Expanded(child: b),
    ],
  );
}

/// Section rule: uppercase title over a 1px line.
class _Rule extends StatelessWidget {
  const _Rule(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title.toUpperCase(), style: T.head),
        const SizedBox(height: 6),
        const Divider(),
      ],
    ),
  );
}

class _AddButton extends StatelessWidget {
  const _AddButton(this.label, {required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => _AddFrame(
    child: InkWell(onTap: onPressed, hoverColor: Z.z3, child: _AddLabel(label)),
  );
}

class _AddMenu extends StatelessWidget {
  const _AddMenu(this.label, this.types, this.onSelected);

  final String label;
  final Iterable<String> types;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final sorted = [...types]..sort((a, b) => Family.of(a).index.compareTo(Family.of(b).index));
    return _AddFrame(
      child: PopupMenuButton<String>(
        tooltip: label,
        onSelected: onSelected,
        position: PopupMenuPosition.under,
        itemBuilder: (_) => [
          for (final t in sorted)
            PopupMenuItem(
              value: t,
              height: 30,
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 14,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(color: Family.of(t).color, borderRadius: BorderRadius.circular(1)),
                  ),
                  Text(t),
                ],
              ),
            ),
        ],
        child: _AddLabel(label),
      ),
    );
  }
}

class _AddFrame extends StatelessWidget {
  const _AddFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    height: 30,
    decoration: BoxDecoration(
      border: Border.all(color: Z.z4),
      borderRadius: BorderRadius.circular(3),
    ),
    clipBehavior: Clip.antiAlias,
    child: Material(type: MaterialType.transparency, child: child),
  );
}

class _AddLabel extends StatelessWidget {
  const _AddLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.add, size: 14, color: Z.z8),
        const SizedBox(width: 6),
        Text(label.toUpperCase(), style: T.label),
      ],
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header(this.title, this.actions);

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Container(
    height: 34,
    padding: const EdgeInsets.only(left: 12, right: 6),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Z.z3)),
    ),
    child: Row(
      children: [
        Expanded(child: Text(title.toUpperCase(), style: T.head)),
        ...actions,
      ],
    ),
  );
}

String _n(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
