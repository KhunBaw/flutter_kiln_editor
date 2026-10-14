import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/game.dart' show GameWidget;
import 'package:flutter/widgets.dart' show Offset, Size;
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiln/kiln.dart';
import 'package:kiln_forge2d/kiln_forge2d.dart';

Map<String, Object?> ent(
  String name,
  List<Map<String, Object?>> behaviors, {
  List<num> pos = const [100, 100],
  List<num> size = const [20, 20],
}) => {'id': name, 'name': name, 'position': pos, 'size': size, 'behaviors': behaviors};

Map<String, Object?> b(String type, [Map<String, Object?> props = const {}]) => {'type': type, 'props': props};
Map<String, Object?> act(String type, [Map<String, Object?> args = const {}]) => {'type': type, ...args};

KilnGame game(List<Map<String, Object?>> entities) {
  final reg = KilnRegistry();
  registerForge2d(reg);
  return KilnGame(
    SceneDoc.fromJson({
      'size': [800, 600],
      'variables': {'shots': 0},
      'entities': entities,
    }),
    registry: reg,
  );
}

Iterable<KilnEntity> all(KilnGame g) => g.world.descendants().whereType<KilnEntity>();
KilnEntity named(KilnGame g, String n) => all(g).firstWhere((e) => e.node.name == n);

Future<void> run(KilnGame g, double seconds) async {
  for (var t = 0.0; t < seconds; t += 1 / 60) {
    g.update(1 / 60);
  }
  await g.ready();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final ground = ent(
    'ground',
    [
      b('RigidBody', {'type': 'static'}),
    ],
    pos: [400, 500],
    size: [800, 20],
  );

  testWithGame(
    'RigidBody falls under gravity and rests on a static body',
    () => game([
      ground,
      ent(
        'ball',
        [
          b('RigidBody', {'shape': 'circle', 'restitution': 0}),
        ],
        pos: [100, 100],
      ),
    ]),
    (g) async {
      await run(g, 0.5);
      expect(named(g, 'ball').y, greaterThan(100)); // falling
      await run(g, 4);
      // Ground top is y=490; the ball (r=10) rests on it.
      expect(named(g, 'ball').y, closeTo(480, 2));
      expect(named(g, 'ground').y, 500);
    },
  );

  testWithGame(
    'restitution bounces; the scene reads the body velocity through the mover',
    () => game([
      ground,
      ent(
        'ball',
        [
          b('RigidBody', {'shape': 'circle', 'restitution': 0.9}),
        ],
        pos: [100, 300],
      ),
    ]),
    (g) async {
      final rb = named(g, 'ball').children.whereType<RigidBody>().single;
      var fell = false, rose = false;
      for (var i = 0; i < 240; i++) {
        g.update(1 / 60);
        if (rb.v.y > 100) fell = true;
        if (fell && rb.v.y < -100) rose = true;
      }
      expect(rose, isTrue);
    },
  );

  testWithGame(
    'SetProp vx drives the body; gravityScale 0 floats',
    () => game([
      ent('probe', [
        b('RigidBody', {'gravityScale': 0}),
      ]),
    ]),
    (g) async {
      final e = named(g, 'probe');
      g.registry.runActions(e, [
        act('SetProp', {'prop': 'vx', 'value': 100}),
      ]);
      await run(g, 1);
      expect(e.x, closeTo(200, 3));
      expect(e.y, closeTo(100, 1));
    },
  );

  testWithGame(
    'revolute joint to the world swings a bob around its pivot',
    () => game([
      ent(
        'bob',
        [
          b('RigidBody', {'shape': 'circle'}),
          b('Joint', {'kind': 'revolute', 'anchorY': -100, 'otherAnchorX': 300, 'otherAnchorY': 200}),
        ],
        pos: [300, 300],
      ),
    ]),
    (g) async {
      final bob = named(g, 'bob');
      await g.ready();
      g.registry.runActions(bob, [
        act('SetProp', {'prop': 'vx', 'value': 150}),
      ]);
      var maxX = 0.0;
      for (var i = 0; i < 120; i++) {
        g.update(1 / 60);
        maxX = max(maxX, bob.x);
        expect((bob.absoluteCenter - Vector2(300, 200)).length, closeTo(100, 4), reason: 'frame $i');
      }
      expect(maxX, greaterThan(340));
    },
  );

  testWithGame(
    'rope joint caps the distance between two bodies',
    () => game([
      ent(
        'anchor',
        [
          b('RigidBody', {'type': 'static'}),
        ],
        pos: [300, 100],
      ),
      ent(
        'weight',
        [
          b('RigidBody', {'shape': 'circle'}),
          b('Joint', {'kind': 'rope', 'other': 'anchor'}),
        ],
        pos: [300, 200],
      ),
    ]),
    (g) async {
      final w = named(g, 'weight'), a = named(g, 'anchor');
      var far = 0.0;
      for (var i = 0; i < 240; i++) {
        g.update(1 / 60);
        far = max(far, w.absoluteCenter.distanceTo(a.absoluteCenter));
      }
      expect(far, lessThan(106)); // started 100 apart, never much farther
      expect(w.y, lessThan(215)); // hangs instead of falling away
    },
  );

  testWithGame(
    'DragLaunch holds the body, previews an arc, then fires opposite to the pull',
    () => game([
      ent(
        'ball',
        [
          b('RigidBody', {'shape': 'circle'}),
          b('DragLaunch', {
            'power': 6,
            'onLaunch': [
              act('AddVariable', {'name': 'shots'}),
            ],
          }),
        ],
        pos: [100, 400],
      ),
    ]),
    (g) async {
      final ball = named(g, 'ball');
      final drag = ball.children.whereType<DragLaunch>().single;
      await run(g, 1);
      expect(ball.y, 400); // held until launch

      int arcs() => g.world.children.where((c) => c.runtimeType.toString() == '_Arc').length;
      drag.aimTo(Vector2(40, 400));
      await g.ready();
      expect(arcs(), 1);
      drag.release();
      await g.ready();
      expect(arcs(), 0);
      expect(drag.launched, isTrue);
      expect(g.vars['shots'], 1);

      await run(g, 0.5);
      expect(ball.x, closeTo(100 + 360 * 0.5, 8)); // 60 px pull × 6
      expect(ball.y, greaterThan(400)); // gravity takes over
    },
  );

  testWithGame(
    'a tap on the slingshot is not a shot',
    () => game([
      ent(
        'ball',
        [
          b('RigidBody', {'shape': 'circle'}),
          b('DragLaunch'),
        ],
        pos: [100, 400],
      ),
    ]),
    (g) async {
      final drag = named(g, 'ball').children.whereType<DragLaunch>().single;
      await g.ready();
      drag.aimTo(Vector2(101, 400));
      drag.release();
      await run(g, 0.5);
      expect((drag.launched, named(g, 'ball').y), (false, 400));
    },
  );

  test('registerForge2d exposes the behaviors in the schema', () {
    final reg = KilnRegistry();
    registerForge2d(reg);
    final json = reg.schemaJson().toString();
    for (final t in ['RigidBody', 'Joint', 'DragLaunch']) {
      expect(json, contains(t));
    }
  });

  testWidgets('a real pointer drag on the widget slings the ball', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final g = game([
      ent(
        'ball',
        [
          b('RigidBody', {'shape': 'circle', 'gravityScale': 0}),
          b('DragLaunch', {'power': 6}),
        ],
        pos: [100, 400],
      ),
    ]);
    await tester.pumpWidget(GameWidget(game: g));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.dragFrom(const Offset(100, 400), const Offset(-60, 0));
    await tester.pump();
    expect(named(g, 'ball').children.whereType<DragLaunch>().single.launched, isTrue);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // 60 px pull × 6 = 360 px/s to the right.
    expect(named(g, 'ball').x, greaterThan(150));
  });
}
