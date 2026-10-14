import 'package:flame/components.dart' show Vector2;
import 'package:forge2d/forge2d.dart' as f2d;
import 'package:kiln/kiln.dart';

import 'src/physics.dart';

export 'src/physics.dart' show DragLaunch, Joint, PhysicsWorld, RigidBody, pixelsPerMeter;

/// Adds the physics behaviors to [registry]. [gravity] is m/s² downward (scene pixels are 50 per meter);
/// the first RigidBody of a scene creates its world with it. Per-body `gravityScale` tunes it.
/// Call it for the game's registry and for the editor's schema (`syncSchema`) so both see the same types.
void registerForge2d(KilnRegistry registry, {double gravity = 9.8}) {
  registry
    ..register(
      BehaviorDef(
        'RigidBody',
        const [
          PropDef('type', PropKind.choice, 'dynamic', options: ['dynamic', 'static', 'kinematic']),
          PropDef('shape', PropKind.choice, 'box', options: ['box', 'circle']),
          PropDef('density', PropKind.number, 1),
          PropDef('restitution', PropKind.number, 0.2),
          PropDef('friction', PropKind.number, 0.5),
          PropDef('gravityScale', PropKind.number, 1),
          PropDef('fixedRotation', PropKind.bool, false),
        ],
        (e, p) => RigidBody(
          type: f2d.BodyType.values.asNameMap()[p.string('type')] ?? f2d.BodyType.dynamic,
          circle: p.string('shape') == 'circle',
          density: p.number('density'),
          restitution: p.number('restitution'),
          friction: p.number('friction'),
          gravityScale: p.number('gravityScale'),
          fixedRotation: p.flag('fixedRotation'),
          gravity: gravity,
        ),
      ),
    )
    ..register(
      BehaviorDef(
        'Joint',
        const [
          PropDef('kind', PropKind.choice, 'revolute', options: ['revolute', 'distance', 'rope']),
          // Name or #tag of the other body's entity; empty pins to a fixed world point.
          PropDef('other', PropKind.string, ''),
          PropDef('anchorX', PropKind.number, 0),
          PropDef('anchorY', PropKind.number, 0),
          PropDef('otherAnchorX', PropKind.number, 0),
          PropDef('otherAnchorY', PropKind.number, 0),
          PropDef('collide', PropKind.bool, false),
          // Distance joint spring: 0 = rigid.
          PropDef('frequency', PropKind.number, 0),
          PropDef('damping', PropKind.number, 0.5),
        ],
        (e, p) => Joint(
          kind: p.string('kind'),
          other: p.string('other'),
          anchor: Vector2(p.number('anchorX'), p.number('anchorY')),
          otherAnchor: Vector2(p.number('otherAnchorX'), p.number('otherAnchorY')),
          collide: p.flag('collide'),
          frequency: p.number('frequency'),
          damping: p.number('damping'),
        ),
      ),
    )
    ..register(
      BehaviorDef(
        'DragLaunch',
        const [
          // Launch speed in px/s per px of pull.
          PropDef('power', PropKind.number, 6),
          PropDef('maxPull', PropKind.number, 120),
          // Extra px around the entity where a drag can start.
          PropDef('grab', PropKind.number, 24),
          PropDef('onLaunch', PropKind.actions, []),
        ],
        (e, p) => DragLaunch(
          power: p.number('power'),
          maxPull: p.number('maxPull'),
          grab: p.number('grab'),
          gravity: gravity,
          actions: p.list('onLaunch'),
        ),
      ),
    );
}
