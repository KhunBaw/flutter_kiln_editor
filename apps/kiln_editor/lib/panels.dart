import 'dart:io';
import 'dart:math' as math;

import 'dart:ui' show ImageDescriptor, ImmutableBuffer;

import 'package:flame/game.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kiln/kiln.dart';

import 'editor_state.dart';
import 'project.dart';
import 'inspector.dart';
import 'theme.dart';
import 'widgets.dart';

class HierarchyPanel extends StatelessWidget {
  const HierarchyPanel(this.s, {super.key});

  final EditorState s;

  @override
  Widget build(BuildContext context) {
    Iterable<Widget> rows(List<EntityNode> list, int depth) sync* {
      for (final e in list) {
        final fams = <Family>[
          for (final f in {for (final b in e.behaviors) Family.of(b.type)}) f,
        ];
        yield _Row(
          selected: e.id == s.selectedId,
          indent: depth * 14,
          onTap: () => s.select(e.id),
          leading: fams.isEmpty
              ? const SizedBox(width: 20, height: 20, child: Icon(Icons.crop_square, size: 14, color: Z.z6))
              : FamilyChip(fams.first, size: 20),
          trailing: [
            for (final f in fams.skip(1))
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(left: 4),
                decoration: BoxDecoration(color: f.color, shape: BoxShape.circle),
              ),
            if (EditorState.animatorOf(e) != null)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.animation, size: 12, color: Z.z7),
              ),
          ],
          child: Text(e.name, overflow: TextOverflow.ellipsis),
        );
        yield* rows(e.children, depth + 1);
      }
    }

    return Column(
      children: [
        PanelHeader('Hierarchy', [
          IconBtn(Icons.add, 'Add entity', s.addEntity),
          IconBtn(
            Icons.delete_outline,
            'Delete entity',
            s.selectedId == null ? null : () => s.removeEntity(s.selectedId!),
          ),
        ]),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
            children: [
              _Row(
                selected: s.selectedId == null,
                onTap: () => s.select(null),
                leading: const SizedBox(
                  width: 20,
                  height: 20,
                  child: Icon(Icons.crop_landscape, size: 15, color: Z.z8),
                ),
                trailing: [Text('${_n(s.doc.size.x)} × ${_n(s.doc.size.y)}', style: T.code)],
                child: Text(s.doc.name, style: T.body.copyWith(fontWeight: FontWeight.w600)),
              ),
              ...rows(s.doc.entities, 1),
              if (s.doc.entities.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(8, 12, 8, 0),
                  child: Text('Nothing here yet. Add an entity with +.', style: T.small),
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
    Widget note(String text, {Color color = Z.z7}) => Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Text(text, style: T.small.copyWith(color: color)),
    );
    return Column(
      children: [
        const PanelHeader('Assets', []),
        Expanded(
          child: dir == null
              ? ListView(children: [note('Open a project folder to see its images and audio.')])
              : FutureBuilder(
                  future: _files,
                  builder: (context, snap) {
                    final [images, audio] = snap.data ?? const [<String>[], <String>[]];
                    return ListView(
                      padding: const EdgeInsets.all(8),
                      children: [
                        if (images.isNotEmpty)
                          Wrap(spacing: 6, runSpacing: 6, children: [for (final f in images) _imageTile(dir, f)]),
                        for (final f in audio) _audioRow(f),
                        if (snap.hasError)
                          note('Could not list assets: ${snap.error}', color: Z.danger)
                        else if (snap.hasData && images.isEmpty && audio.isEmpty)
                          note('No files in assets/images or assets/audio yet.'),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _thumb(String dir, String file, double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Z.z1,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: Z.z4),
    ),
    clipBehavior: Clip.antiAlias,
    padding: const EdgeInsets.all(4),
    child: Image.file(
      File('$dir/assets/images/$file'),
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined, size: 16, color: Z.z7),
    ),
  );

  Widget _imageTile(String dir, String file) {
    const w = 72.0;
    return Draggable<AssetDrop>(
      data: AssetDrop(file),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Z.z3,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Z.accent),
            boxShadow: Z.shadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _thumb(dir, file, 28),
              const SizedBox(width: 8),
              Text(file, style: T.body),
            ],
          ),
        ),
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Tooltip(
          message: 'Drag onto the scene',
          child: SizedBox(
            width: w,
            child: Column(
              children: [
                _thumb(dir, file, w),
                const SizedBox(height: 3),
                Text(file, style: T.small, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _audioRow(String file) => SizedBox(
    height: 28,
    child: Row(
      children: [
        const SizedBox(width: 4),
        const Icon(Icons.graphic_eq, size: 14, color: Z.z8),
        const SizedBox(width: 8),
        Expanded(child: Text(file, overflow: TextOverflow.ellipsis)),
      ],
    ),
  );
}

/// An image file name being dragged from [AssetsPanel].
class AssetDrop {
  const AssetDrop(this.image);

  final String image;
}

class _Row extends StatefulWidget {
  const _Row({
    required this.selected,
    required this.onTap,
    required this.child,
    required this.leading,
    this.indent = 0,
    this.trailing = const [],
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final Widget leading;
  final double indent;
  final List<Widget> trailing;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Container(
        height: 30,
        margin: const EdgeInsets.only(bottom: 1),
        padding: EdgeInsets.only(left: 6 + widget.indent, right: 8),
        decoration: BoxDecoration(
          color: widget.selected ? Z.accentDim : (_hover ? Z.z3 : Colors.transparent),
          borderRadius: BorderRadius.circular(5),
        ),
        child: DefaultTextStyle.merge(
          style: T.body.copyWith(color: widget.selected ? Z.z10 : Z.z9),
          child: Row(
            children: [
              widget.leading,
              const SizedBox(width: 8),
              Expanded(child: widget.child),
              ...widget.trailing,
            ],
          ),
        ),
      ),
    ),
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
                decoration: BoxDecoration(
                  border: Border.all(color: Z.z5),
                  boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 32, offset: Offset(0, 12))],
                ),
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
              child: Text('$caption · ${_n(size.x)} × ${_n(size.y)} · ${(scale * 100).round()}%', style: T.small),
            ),
            if (footer.isNotEmpty) Positioned(right: 8, bottom: 6, child: Row(children: footer)),
          ],
        );
      },
    ),
  );
}

/// Workspace backdrop: a quiet dot lattice.
class _BoardPainter extends CustomPainter {
  const _BoardPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Z.z0);
    final dot = Paint()..color = Z.z3;
    for (var y = 12.0; y < size.height; y += 20) {
      for (var x = 12.0; x < size.width; x += 20) {
        canvas.drawCircle(Offset(x, y), 0.8, dot);
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

  @override
  void initState() {
    super.initState();
    s.playhead.addListener(_onHead);
  }

  @override
  void dispose() {
    s.playhead.removeListener(_onHead);
    super.dispose();
  }

  /// Timeline scrub: re-pose live Animators in place instead of rebuilding the preview game.
  void _onHead() {
    final t = s.playhead.value;
    _game.poseTime = t;
    for (final e in _game.world.descendants().whereType<KilnEntity>()) {
      e.animator?.seek(t);
    }
    if (mounted) setState(() {});
  }

  /// Centre of [e] as the timeline poses it (stored position when it has no x/y track).
  Offset _center(EntityNode e) {
    final a = EditorState.animatorOf(e);
    if (a == null) return Offset(e.position.x, e.position.y);
    final p = samplePose(a.props['tracks'], s.playhead.value);
    return Offset(p['x'] ?? e.position.x, p['y'] ?? e.position.y);
  }

  bool get _painting => s.paintId != null && s.paintId == s.selectedId;

  void _paint(Offset p) => s.paintAt(Vector2(p.dx, p.dy), stroke: _drag);

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
      )..poseTime = s.playhead.value;
    }
    final world = s.doc.worldSize;
    final sel = s.selectedId == null ? null : _rectOf(s.doc.entities, s.selectedId!, Offset.zero);
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
                ..._selection(Rect.fromLTRB(sel.left * k, sel.top * k, sel.right * k, sel.bottom * k).shift(o), k),
            ],
            child: DragTarget<AssetDrop>(
              onAcceptWithDetails: (d) => _place(d.data.image, d.offset),
              builder: (context, hover, _) => GestureDetector(
                key: _sceneKey,
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) =>
                    _painting ? _paint(d.localPosition) : s.select(_hit(s.doc.entities, d.localPosition, Offset.zero)),
                onPanStart: (d) {
                  if (_panning) return;
                  if (_painting) {
                    _drag = 'paint${_dragCount++}';
                    return _paint(d.localPosition);
                  }
                  final id = _hit(s.doc.entities, d.localPosition, Offset.zero);
                  s.select(id);
                  _drag = id == null ? null : '$id.drag${_dragCount++}';
                  _dragStart = d.localPosition;
                  final cur = s.selected;
                  _dragFrom = cur == null ? Vector2.zero() : Vector2(s.valueOf(cur, 'x'), s.valueOf(cur, 'y'));
                },
                onPanUpdate: (d) {
                  final e = s.selected;
                  if (_panning || _drag == null || e == null) return;
                  if (_painting) return _paint(d.localPosition);
                  // One undo step per drag gesture; the top-left corner snaps to the grid.
                  final o = d.localPosition - _dragStart;
                  final half = e.size / 2;
                  final p = Vector2(
                    s.snap(_dragFrom.x + o.dx - half.x) + half.x,
                    s.snap(_dragFrom.y + o.dy - half.y) + half.y,
                  );
                  if (p.x == s.valueOf(e, 'x') && p.y == s.valueOf(e, 'y')) return;
                  if (s.isAnimated(e, 'x') || s.isAnimated(e, 'y')) {
                    s.setProp(e, 'x', p.x, mergeKey: _drag);
                    s.setProp(e, 'y', p.y, mergeKey: _drag);
                  } else {
                    s.edit((_) => e.position = p, mergeKey: _drag);
                  }
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

  List<Widget> _footer() => [
    PopupMenuButton<double>(
      tooltip: 'Snap grid',
      position: PopupMenuPosition.over,
      initialValue: s.grid,
      onSelected: (g) => s.setView(grid: g),
      itemBuilder: (_) => [
        for (final g in const [0.0, 4.0, 8.0, 16.0, 32.0, 64.0])
          PopupMenuItem(value: g, height: 30, child: Text(g == 0 ? 'Grid off' : 'Grid ${g.toInt()} px')),
      ],
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.grid_4x4, size: 15, color: s.grid == 0 ? Z.z8 : Z.accent),
            const SizedBox(width: 6),
            Text(
              s.grid == 0 ? 'Grid' : '${s.grid.toInt()} px',
              style: T.label.copyWith(color: s.grid == 0 ? Z.z8 : Z.accent),
            ),
          ],
        ),
      ),
    ),
    IconBtn(Icons.remove, 'Zoom out (⌘ scroll)', () => _zoomAt(_box.center(Offset.zero), s.zoom / 1.25)),
    IconBtn(Icons.add, 'Zoom in (⌘ scroll)', () => _zoomAt(_box.center(Offset.zero), s.zoom * 1.25)),
    IconBtn(Icons.fit_screen, 'Fit the world (pan: space or middle drag, two-finger scroll)', _fit),
  ];

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
              child: Text('VIEW', style: T.small),
            ),
          ),
        ),
      ),
    ),
  ];

  /// Selection: a 1.5px accent frame, a name tag, a resize handle (bottom right) and a rotate handle on a stalk.
  List<Widget> _selection(Rect r, double k) {
    final e = s.selected;
    const stalk = 20.0;
    final rot = Offset(r.center.dx, r.top - stalk);
    return [
      Positioned.fromRect(
        rect: r.inflate(1),
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(border: Border.all(color: Z.accent, width: 1.5)),
          ),
        ),
      ),
      Positioned(
        left: rot.dx - 0.5,
        top: rot.dy,
        width: 1,
        height: stalk,
        child: const IgnorePointer(child: ColoredBox(color: Z.accent)),
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
            _angleFrom = s.valueOf(e, 'angle');
            _handleAt = rot - r.center;
          },
          onMove: (o) {
            final v = _handleAt + o;
            var a = _angleFrom + math.atan2(v.dx, -v.dy);
            if (HardwareKeyboard.instance.isShiftPressed) a = (a / (math.pi / 12)).roundToDouble() * (math.pi / 12);
            a = double.parse(a.toStringAsFixed(4));
            if (a != s.valueOf(e, 'angle')) s.setProp(e, 'angle', a, mergeKey: _drag);
          },
        ),
      ],
      Positioned(
        left: r.left - 1,
        top: r.bottom + 8,
        child: IgnorePointer(
          child: Container(
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Z.accent, borderRadius: BorderRadius.circular(4)),
            child: Text(
              '${widget.s.selected?.name ?? ''}  ${(r.width / k).round()} × ${(r.height / k).round()}',
              style: T.head.copyWith(color: Z.z0, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
        ),
      ),
    ];
  }

  /// A draggable handle centred on [at]; [onMove] gets the total pointer offset in screen pixels.
  Widget _handle(
    Offset at,
    String tip,
    MouseCursor cursor, {
    required VoidCallback onStart,
    required void Function(Offset total) onMove,
    bool circle = false,
  }) {
    var total = Offset.zero;
    // 20px hit area around a 10px mark, so the handle is easy to grab at any zoom.
    return Positioned(
      left: at.dx - 10,
      top: at.dy - 10,
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
              dimension: 20,
              child: Center(
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Z.z10,
                    border: Border.all(color: Z.accent, width: 1.5),
                    shape: circle ? BoxShape.circle : BoxShape.rectangle,
                    borderRadius: circle ? null : BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Topmost entity under [p]: later siblings and children draw on top, so search them first. Ignores angle.
  String? _hit(List<EntityNode> list, Offset p, Offset origin) {
    for (final e in list.reversed) {
      final r = Rect.fromCenter(center: origin + _center(e), width: e.size.x, height: e.size.y);
      final c = _hit(e.children, p, r.topLeft);
      if (c != null) return c;
      if (r.contains(p)) return e.id;
    }
    return null;
  }

  // Children are positioned relative to the parent's top-left (Flame local space). Ignores angle.
  Rect? _rectOf(List<EntityNode> list, String id, Offset origin) {
    for (final e in list) {
      final r = Rect.fromCenter(center: origin + _center(e), width: e.size.x, height: e.size.y);
      if (e.id == id) return r;
      final c = _rectOf(e.children, id, r.topLeft);
      if (c != null) return c;
    }
    return null;
  }
}

String _n(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
