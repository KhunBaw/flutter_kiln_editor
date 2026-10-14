import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/events.dart';

import 'builtins.dart' show motionOf;
import 'game.dart';
import 'registry.dart';

/// Screen-wide pointer (mouse or touch) in world coordinates. Created by the first OnPointer/Joystick.
/// Events keep propagating, so taps, Draggable and buttons underneath still work.
class PointerLayer extends PositionComponent with TapCallbacks, DragCallbacks, PointerMoveCallbacks {
  PointerLayer(Vector2 size) : super(size: size, priority: 1 << 30);

  KilnGame get _g => findGame()! as KilnGame;

  void _at(Vector2 canvas, String phase) {
    if (_g.editing) return;
    _g.pointerEvent(phase, _g.camera.globalToLocal(canvas));
  }

  @override
  void onTapDown(TapDownEvent event) {
    event.continuePropagation = true;
    _at(event.canvasPosition, 'down');
  }

  @override
  void onTapUp(TapUpEvent event) {
    event.continuePropagation = true;
    _at(event.canvasPosition, 'up');
  }

  // A tap that turns into a drag is cancelled here; the drag then ends with onDragEnd, so no "up" yet.
  @override
  void onDragStart(DragStartEvent event) {
    event.continuePropagation = true;
    super.onDragStart(event);
    _at(event.canvasPosition, 'down');
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    event.continuePropagation = true;
    _at(event.canvasEndPosition, 'move');
  }

  @override
  void onDragEnd(DragEndEvent event) {
    event.continuePropagation = true;
    super.onDragEnd(event);
    _g.pointerEvent('up', _g.pointer);
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    event.continuePropagation = true;
    super.onDragCancel(event);
    _g.pointerEvent('up', _g.pointer);
  }

  @override
  void onPointerMove(PointerMoveEvent event) => _at(event.canvasPosition, 'move');
}

/// Runs action lists on pointer down / move (hover or drag) / up; formulas read `pointer.x`, `pointer.y`, `pointer.down`.
class OnPointer extends Component with ParentIsA<KilnEntity> {
  OnPointer(this.p);

  final Props p;

  @override
  void onMount() {
    super.onMount();
    final g = parent.game;
    if (g.editing) return;
    g.ensurePointerLayer();
    g.pointerListeners.add(_run);
  }

  void _run(String phase) => parent.runActions(p.list(phase));

  @override
  void onRemove() => parent.game.pointerListeners.remove(_run);
}

/// On-screen stick: drag inside the entity's box. Writes -1..1 to [varX]/[varY] (0 on release) and, when [speed] > 0,
/// sets the velocity of [target] (name or #tag, empty = self) to the stick times [speed].
class Joystick extends Component with ParentIsA<KilnEntity> {
  Joystick({required this.varX, required this.varY, required this.speed, required this.target});

  final String varX, varY, target;
  final double speed;
  bool _held = false;
  Vector2 _stick = Vector2.zero();

  @override
  void onMount() {
    super.onMount();
    final g = parent.game;
    if (g.editing) return;
    g.ensurePointerLayer();
    g.pointerListeners.add(_on);
  }

  @override
  void onRemove() => parent.game.pointerListeners.remove(_on);

  double get _radius => max(1.0, min(parent.size.x, parent.size.y) / 2);

  void _on(String phase) {
    final g = parent.game;
    if (phase == 'down') {
      _held = parent.toAbsoluteRect().contains(g.pointer.toOffset());
    } else if (phase == 'up') {
      _held = false;
    }
    if (!_held) {
      if (phase != 'up') return;
      _stick = Vector2.zero();
    } else {
      _stick = (g.pointer - parent.absoluteCenter) / _radius;
      if (_stick.length > 1) _stick.normalize();
    }
    if (varX.isNotEmpty) g.vars[varX] = _stick.x;
    if (varY.isNotEmpty) g.vars[varY] = _stick.y;
    if (speed > 0) {
      for (final t in g.targets(parent, target)) {
        motionOf(t).v.setValues(_stick.x * speed, _stick.y * speed);
      }
    }
  }
}
