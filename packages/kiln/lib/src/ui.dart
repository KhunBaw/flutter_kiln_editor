import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/text.dart';

import 'game.dart';

/// Pins a top-level entity to the screen: its position is a view offset, not a world position.
class Hud extends Component with ParentIsA<KilnEntity> {
  late final Vector2 _screen;

  @override
  void onMount() {
    super.onMount();
    final g = parent.game;
    if (g.editing) return;
    _screen = parent.position.clone();
    // Draw above world entities.
    parent.priority += 1 << 16;
    g.afterUpdate.add(_pin);
    _pin();
  }

  void _pin() => parent.position.setFrom(_screen + parent.game.camera.viewfinder.position);

  @override
  void onRemove() => parent.game.afterUpdate.remove(_pin);
}

/// Draws a rounded rect (or 9-slice image) behind children; a tap runs [actions] and flashes the pressed colour.
class UiBox extends Component with ParentIsA<KilnEntity> {
  UiBox({
    required this.color,
    required this.border,
    required this.radius,
    this.pressed,
    this.box,
    this.label = '',
    this.style,
  });

  final Color color, border;
  final Color? pressed;
  final double radius;
  final NineTileBox? box;
  final String label;
  final TextStyle? style;
  double _flash = 0;

  void press() => _flash = 0.12;

  @override
  void update(double dt) => _flash = max(0, _flash - dt);

  @override
  void render(Canvas canvas) {
    final rect = Offset.zero & parent.size.toSize();
    if (box case final b?) {
      b.drawRect(canvas, rect);
    } else {
      final rr = RRect.fromRectAndRadius(rect, Radius.circular(radius));
      canvas.drawRRect(rr, Paint()..color = _flash > 0 ? (pressed ?? color) : color);
      if (border.a > 0) {
        canvas.drawRRect(
          rr.deflate(1),
          Paint()
            ..color = border
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
    if (label.isNotEmpty && style != null) {
      TextPaint(style: style)
          .render(canvas, fillTemplate(label, parent.game.vars), parent.size / 2, anchor: Anchor.center);
    }
  }
}

/// A bar filled by `variable / max`.
class ProgressBar extends Component with ParentIsA<KilnEntity> {
  ProgressBar({required this.variable, required this.max, required this.fill, required this.back});

  final String variable;
  final double max;
  final Color fill, back;

  @override
  void render(Canvas canvas) {
    final v = parent.game.vars[variable];
    final f = v is num && max > 0 ? (v / max).clamp(0.0, 1.0).toDouble() : 0.0;
    final r = parent.size.y / 2;
    final rect = Offset.zero & parent.size.toSize();
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(r)), Paint()..color = back);
    if (f > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, rect.width * f, rect.height), Radius.circular(r)),
        Paint()..color = fill,
      );
    }
  }
}

/// Where a [Draggable] can be dropped; runs [actions] on the zone with the dropped entity as `other`.
class DropZone extends Component with ParentIsA<KilnEntity> {
  DropZone({required this.accept, required this.snap, required this.actions});

  final String accept;
  final bool snap;
  final List<Object?> actions;

  bool accepts(KilnEntity e) =>
      accept.isEmpty || e.node.name == accept || (accept.startsWith('#') && e.node.tags.contains(accept.substring(1)));

  @override
  void onMount() {
    super.onMount();
    parent.game.dropZones.add(this);
  }

  @override
  void onRemove() => parent.game.dropZones.remove(this);
}

/// Lets the player drag the entity; on release it drops onto the nearest accepting [DropZone] it overlaps.
class Draggable extends PositionComponent with DragCallbacks {
  Draggable({required this.snapBack, required this.actions}) : super(position: Vector2.zero());

  final bool snapBack;
  final List<Object?> actions;
  late KilnEntity _e;
  Vector2 _start = Vector2.zero();
  int _priority = 0;
  bool _held = false;

  // shortcut: drag assumes a top-level entity with no scale; revisit for nested draggables.
  @override
  void onMount() {
    super.onMount();
    _e = parent! as KilnEntity;
    size = _e.size;
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (_e.game.editing) return;
    _held = true;
    _start = _e.position.clone();
    _priority = _e.priority;
    _e.priority = 1 << 20;
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (_held) _e.position += event.localDelta.clone()..rotate(_e.angle);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    _drop();
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    _drop();
  }

  void _drop() {
    if (!_held) return;
    _held = false;
    _e.priority = _priority;
    final here = _e.absoluteCenter;
    DropZone? best;
    var bestD = double.infinity;
    for (final z in _e.game.dropZones) {
      if (!z.accepts(_e) || !z.parent.toAbsoluteRect().contains(here.toOffset())) continue;
      final d = z.parent.absoluteCenter.distanceToSquared(here);
      if (d < bestD) (best, bestD) = (z, d);
    }
    if (best == null) {
      if (snapBack) _e.position.setFrom(_start);
      return;
    }
    if (best.snap) _e.position.setFrom(best.parent.absoluteCenter);
    best.parent.runActions(best.actions, other: _e);
    _e.runActions(actions, other: best.parent);
  }
}

/// Builds the box for Panel: a 9-slice when [image] is set (3×3 grid of `slice` px cells), else null.
NineTileBox? nineSlice(Image? image, double slice) =>
    image == null ? null : NineTileBox(Sprite(image), tileSize: max(1, slice.round()));
