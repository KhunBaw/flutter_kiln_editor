import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/foundation.dart';
import 'package:forge2d/forge2d.dart' as f2d;
import 'package:kiln/kiln.dart';

/// Scene pixels per Forge2D meter. Box2D wants bodies of 0.1-10 m, so 50 px/m suits 20-500 px entities.
const pixelsPerMeter = 50.0;

/// Fixed physics step; the world catches up in whole steps so results don't depend on the frame rate.
const _step = 1 / 60;

/// One Forge2D world per [KilnGame], created by the first RigidBody and stepped from the game's world.
class PhysicsWorld extends Component {
  PhysicsWorld(this.game, double gravity) : world = f2d.World(f2d.Vector2(0, gravity));

  static final _worlds = Expando<PhysicsWorld>('kiln_forge2d');

  /// The world of [game], created on demand with [gravity] m/s² (the first caller's value wins).
  static PhysicsWorld of(KilnGame game, double gravity) {
    final existing = _worlds[game];
    if (existing != null) return existing;
    final w = _worlds[game] = PhysicsWorld(game, gravity);
    game.world.add(w);
    return w;
  }

  final KilnGame game;
  final f2d.World world;
  final Set<RigidBody> bodies = {};
  double _acc = 0;

  @override
  void update(double dt) {
    if (game.editing) return;
    _acc = min(_acc + dt, _step * 5); // a long frame never spirals into more and more steps
    while (_acc >= _step) {
      _acc -= _step;
      for (final b in bodies) {
        b.pushToBody();
      }
      world.stepDt(_step);
      for (final b in bodies) {
        b.pullFromBody();
      }
    }
  }
}

/// Puts its entity under Forge2D. It is the entity's mover, so `vx`/`vy` (SetProp, Move8, Follow) set
/// the body's velocity; don't combine it with Velocity or Body.
class RigidBody extends Motion {
  RigidBody({
    required this.type,
    required this.circle,
    required this.density,
    required this.restitution,
    required this.friction,
    required this.gravityScale,
    required this.fixedRotation,
    required this.gravity,
  }) : super(0, 0, 0);

  final f2d.BodyType type;
  final bool circle, fixedRotation;
  final double density, restitution, friction, gravityScale, gravity;
  late final PhysicsWorld physics;
  late final f2d.Body body;
  final Vector2 _synced = Vector2.zero();

  @override
  void onMount() {
    super.onMount();
    final e = parent;
    physics = PhysicsWorld.of(e.game, gravity);
    final c = e.absoluteCenter / pixelsPerMeter;
    body = physics.world.createBody(
      f2d.BodyDef(
        type: type,
        position: f2d.Vector2(c.x, c.y),
        angle: e.absoluteAngle,
        fixedRotation: fixedRotation,
        gravityScale: f2d.Vector2(0, gravityScale),
      ),
    );
    final half = e.size / 2 / pixelsPerMeter;
    body.createFixture(
      f2d.FixtureDef(
        circle ? f2d.CircleShape(radius: min(half.x, half.y)) : (f2d.PolygonShape()..setAsBoxXY(half.x, half.y)),
        density: density,
        restitution: restitution,
        friction: friction,
      ),
    );
    physics.bodies.add(this);
  }

  @override
  void onRemove() {
    if (isMounted) {
      physics.bodies.remove(this);
      physics.world.destroyBody(body);
    }
    super.onRemove();
  }

  /// Applies what the scene changed since the last step: a written `v`, or a moved kinematic/static entity.
  void pushToBody() {
    if (v != _synced) {
      body.linearVelocity.setValues(v.x / pixelsPerMeter, v.y / pixelsPerMeter);
      body.setAwake(true);
    }
    if (body.bodyType != f2d.BodyType.dynamic) {
      final c = parent.absoluteCenter / pixelsPerMeter;
      body.setTransform(f2d.Vector2(c.x, c.y), parent.absoluteAngle);
    }
  }

  void pullFromBody() {
    final p = body.position * pixelsPerMeter;
    // Children of a transformed parent are not supported: the body lives in world space.
    parent.position.setValues(p.x, p.y);
    parent.angle = body.angle;
    _synced.setValues(body.linearVelocity.x * pixelsPerMeter, body.linearVelocity.y * pixelsPerMeter);
    v.setFrom(_synced);
    spin = body.angularVelocity;
  }

  /// Sets the body's type, e.g. a held slingshot ball becoming dynamic on release.
  void setType(f2d.BodyType t) {
    body.setType(t);
    body.setAwake(true);
  }

  @override
  void update(double dt) {} // PhysicsWorld moves the entity
}

/// Joins its entity's body to another entity's body (`other`, by name or #tag) or, with `other` empty, to a fixed
/// world point. Anchors are px offsets: `anchor` from this entity's centre, `otherAnchor` from the partner's centre
/// (or the world position when pinned to the world). `revolute` pivots at `anchor`; `distance` keeps the anchors
/// apart (springy with `frequency`); `rope` only stops them drifting farther than they start.
class Joint extends Component with ParentIsA<KilnEntity> {
  Joint({
    required this.kind,
    required this.other,
    required this.anchor,
    required this.otherAnchor,
    required this.collide,
    required this.frequency,
    required this.damping,
  });

  final String kind, other;
  final Vector2 anchor, otherAnchor;
  final bool collide;
  final double frequency, damping;
  f2d.Joint? _joint;
  PhysicsWorld? _world;
  int _tries = 0;

  RigidBody? _bodyOf(KilnEntity? e) => e?.children.whereType<RigidBody>().firstOrNull;

  // Bodies appear as their entities finish loading, so retry each frame (up to ~2 s) until both exist.
  @override
  void update(double dt) {
    if (_joint != null || _tries > 120 || parent.game.editing) return;
    _tries++;
    final mine = _bodyOf(parent);
    final partner = other.isEmpty ? null : parent.game.targets(parent, other).firstOrNull;
    final theirs = _bodyOf(partner);
    if (mine == null || (other.isNotEmpty && theirs == null)) {
      if (_tries > 120) debugPrint('kiln: Joint on ${parent.node.name}: no RigidBody to join');
      return;
    }
    final world = (_world = mine.physics).world;
    f2d.Vector2 m(Vector2 px) => f2d.Vector2(px.x / pixelsPerMeter, px.y / pixelsPerMeter);
    final a = parent.absoluteCenter + anchor;
    final b = partner == null ? otherAnchor : partner.absoluteCenter + otherAnchor;
    // A world pin is a static body at the point.
    final bBody = theirs?.body ?? world.createBody(f2d.BodyDef(position: m(b)));
    final f2d.JointDef def = switch (kind) {
      'revolute' => f2d.RevoluteJointDef()..initialize(mine.body, bBody, m(a)),
      'rope' =>
        f2d.RopeJointDef()
          ..bodyA = mine.body
          ..bodyB = bBody
          ..localAnchorA.setFrom(mine.body.localPoint(m(a)))
          ..localAnchorB.setFrom(bBody.localPoint(m(b)))
          ..maxLength = max(0.05, (a - b).length / pixelsPerMeter),
      _ =>
        f2d.DistanceJointDef()
          ..initialize(mine.body, bBody, m(a), m(b))
          ..frequencyHz = frequency
          ..dampingRatio = damping,
    };
    def.collideConnected = collide;
    world.createJoint(switch (def) {
      f2d.RevoluteJointDef() => f2d.RevoluteJoint(def),
      f2d.RopeJointDef() => f2d.RopeJoint(def),
      _ => f2d.DistanceJoint(def as f2d.DistanceJointDef),
    });
    _joint = world.joints.last;
  }

  @override
  void onRemove() {
    final j = _joint;
    if (j != null) _world?.world.destroyJoint(j);
    super.onRemove();
  }
}

/// Slingshot: drag back from the entity and let go to fire it the other way; a dotted arc previews the flight.
/// The body is held (static) until launch, then becomes dynamic.
class DragLaunch extends PositionComponent with DragCallbacks, ParentIsA<KilnEntity> {
  DragLaunch({
    required this.power,
    required this.maxPull,
    required this.grab,
    required this.gravity,
    required this.actions,
  }) : super(anchor: Anchor.center);

  final double power, maxPull, grab, gravity;
  final List<Object?> actions;
  final Vector2 _pull = Vector2.zero();
  bool _aiming = false;
  bool _launched = false;
  _Arc? _arc;

  bool get launched => _launched;

  RigidBody? get _body => parent.children.whereType<RigidBody>().firstOrNull;

  @override
  void onMount() {
    super.onMount();
    size = Vector2.all(max(parent.size.x, parent.size.y) + grab * 2);
    position = parent.size / 2;
    _body?.setType(f2d.BodyType.static);
  }

  /// Pointer-independent entry points (events call these; tests do too).
  void aimTo(Vector2 world) {
    if (_launched || parent.game.editing) return;
    _aiming = true;
    _pull.setFrom(parent.absoluteCenter - world); // points the way the shot will go
    if (_pull.length > maxPull) _pull.scaleTo(maxPull);
    var arc = _arc;
    if (arc == null) {
      _arc = arc = _Arc();
      parent.game.world.add(arc);
    }
    arc.points = _trajectory();
  }

  List<Vector2> _trajectory() {
    final v0 = _pull * power, g = Vector2(0, gravity * pixelsPerMeter * (_body?.gravityScale ?? 1));
    final c = parent.absoluteCenter;
    return [for (var i = 1; i <= 24; i++) c + v0 * (i * 0.07) + g * (0.5 * pow(i * 0.07, 2).toDouble())];
  }

  void release() {
    final b = _body;
    _arc?.removeFromParent();
    _arc = null;
    if (!_aiming || b == null || _launched) return;
    _aiming = false;
    if (_pull.length < 4) return; // a tap is not a shot
    _launched = true;
    b.setType(f2d.BodyType.dynamic);
    b.v.setFrom(_pull * power); // picked up by the next step
    parent.runActions(actions);
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    aimTo(parent.game.camera.globalToLocal(event.canvasPosition));
  }

  @override
  void onDragUpdate(DragUpdateEvent event) => aimTo(parent.game.camera.globalToLocal(event.canvasEndPosition));

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    release();
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    release();
  }

  @override
  void onRemove() {
    _arc?.removeFromParent();
    super.onRemove();
  }
}

class _Arc extends Component {
  List<Vector2> points = const [];

  @override
  void render(Canvas canvas) {
    final p = Paint()..color = const Color(0xCCE9C548);
    for (final (i, pt) in points.indexed) {
      canvas.drawCircle(Offset(pt.x, pt.y), 3.5 - i * 0.08, p);
    }
  }
}
