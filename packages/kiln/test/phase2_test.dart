import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiln/kiln.dart';
import 'package:kiln/src/builtins.dart' show Health, Motion, parsePoints;

Map<String, Object?> ent(
  String name,
  List<Map<String, Object?>> behaviors, {
  List<num> pos = const [100, 100],
  List<num> size = const [20, 20],
  List<String> tags = const [],
}) => {'id': name, 'name': name, 'position': pos, 'size': size, 'tags': tags, 'behaviors': behaviors};

Map<String, Object?> b(String type, [Map<String, Object?> props = const {}]) => {'type': type, 'props': props};

Map<String, Object?> act(String type, [Map<String, Object?> args = const {}]) => {'type': type, ...args};

SceneDoc scene(List<Map<String, Object?>> entities) => SceneDoc.fromJson({
  'size': [800, 600],
  'variables': {'score': 0, 'hurts': 0},
  'entities': entities,
});

Iterable<KilnEntity> all(KilnGame g) => g.world.descendants().whereType<KilnEntity>();
KilnEntity named(KilnGame g, String n) => all(g).firstWhere((e) => e.node.name == n);

KeyEvent down(LogicalKeyboardKey k) =>
    KeyDownEvent(physicalKey: PhysicalKeyboardKey.space, logicalKey: k, timeStamp: Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWithGame(
    'Move8: arrows steer, diagonals normalized, turn faces the move',
    () => KilnGame(
      scene([
        ent('p', [
          b('Move8', {'speed': 100, 'keys': 'arrows', 'turn': true}),
        ]),
      ]),
    ),
    (g) async {
      g.onKeyEvent(down(LogicalKeyboardKey.arrowRight), {LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.arrowDown});
      g.update(0); // Move8 sets the velocity
      g.update(1);
      final p = named(g, 'p');
      expect(p.x, closeTo(100 + 100 / sqrt2, 1e-6));
      expect(p.y, closeTo(100 + 100 / sqrt2, 1e-6));
      expect(p.angle, closeTo(pi / 4, 1e-9));
      // WASD ignored in arrows mode.
      g.onKeyEvent(down(LogicalKeyboardKey.keyD), {LogicalKeyboardKey.keyD});
      g.update(0);
      expect(p.children.whereType<Motion>().single.v, Vector2.zero());
    },
  );

  testWithGame(
    'Shoot facing: projectile launched along the angle; cooldown limits rate',
    () => KilnGame(
      scene([
        ent('Bullet', [b('Prefab')], size: [4, 4]),
        ent('gun', [
          b('OnKey', {
            'key': 'Space',
            'on': 'held',
            'actions': [
              act('Shoot', {'prefab': 'Bullet', 'speed': 100, 'cooldown': 0.5, 'offset': 10}),
            ],
          }),
        ]),
      ]),
    ),
    (g) async {
      named(g, 'gun').angle = pi / 2; // facing down
      g.onKeyEvent(down(LogicalKeyboardKey.space), {LogicalKeyboardKey.space});
      g.update(0.1);
      await g.ready();
      g.update(0.1);
      await g.ready();
      final shots = all(g).where((e) => e.node.name == 'Bullet').toList();
      expect(shots, hasLength(1)); // second press inside the cooldown
      expect(shots.single.x, closeTo(100, 1e-6));
      expect(shots.single.y, greaterThan(110));
      expect(shots.single.angle, closeTo(pi / 2, 1e-9));
      for (var i = 0; i < 5; i++) {
        g.update(0.1);
        await g.ready();
      }
      expect(all(g).where((e) => e.node.name == 'Bullet'), hasLength(2));
    },
  );

  testWithGame(
    'Shoot aims at the nearest target',
    () => KilnGame(
      scene([
        ent('Bullet', [b('Prefab')], size: [4, 4]),
        ent('gun', [
          b('Timer', {
            'interval': 0.1,
            'repeat': false,
            'actions': [
              act('Shoot', {'prefab': 'Bullet', 'aim': 'target', 'at': '#enemy', 'speed': 100}),
            ],
          }),
        ]),
        ent('far', [], pos: [100, 500], tags: ['enemy']),
        ent('near', [], pos: [300, 100], tags: ['enemy']),
      ]),
    ),
    (g) async {
      g.update(0.1);
      await g.ready();
      g.update(0.5);
      final shot = named(g, 'Bullet');
      expect(shot.y, closeTo(100, 1e-6));
      expect(shot.x, greaterThan(120));
    },
  );

  testWithGame(
    'Health: damage via OnCollide target other, grace window, death once, variable mirror, heal cap',
    () => KilnGame(
      scene([
        ent('hero', [
          b('Collider'),
          b('Health', {
            'hp': 3,
            'invulnerable': 1,
            'variable': 'hp',
            'hurt': [
              act('AddVariable', {'name': 'hurts', 'value': 1}),
            ],
            'death': [
              act('AddVariable', {'name': 'score', 'value': 100}),
              act('Destroy'),
            ],
          }),
        ]),
        ent(
          'spike',
          [
            b('Collider'),
            b('OnCollide', {
              'with': '#hero',
              'actions': [
                act('Damage', {'target': 'other', 'amount': 1}),
              ],
            }),
          ],
          pos: [110, 100],
        ),
      ]).also((d) => d.entities.first.tags.add('hero')),
    ),
    (g) async {
      g.update(0); // the spike overlaps from the start
      expect(g.vars['hp'], 2);
      final h = named(g, 'hero').children.whereType<Health>().single;
      h.damage(1); // inside the 1s grace window
      expect(g.vars['hp'], 2);
      g.update(1.1);
      h.heal(5);
      expect(g.vars['hp'], 3);
      h.damage(5);
      h.damage(5);
      await g.ready();
      expect(g.vars['hurts'], 1);
      expect(g.vars['score'], 100);
      expect(all(g).map((e) => e.node.name), ['spike']);
    },
  );

  testWithGame(
    'Follow stops at distance; LookAt faces; Patrol pingpongs',
    () => KilnGame(
      scene([
        ent('Player', [], pos: [400, 100]),
        ent('dog', [
          b('Follow', {'target': 'Player', 'speed': 200, 'stop': 50}),
          b('LookAt', {'target': 'Player'}),
        ]),
        ent(
          'guard',
          [
            b('Patrol', {'points': '100,300; 200,300', 'speed': 100, 'loop': 'pingpong'}),
          ],
          pos: [100, 300],
        ),
      ]),
    ),
    (g) async {
      for (var i = 0; i < 180; i++) {
        g.update(1 / 60);
      }
      final dog = named(g, 'dog');
      expect(dog.x, closeTo(350, 4));
      expect(dog.angle, closeTo(0, 1e-9));
      // 3s at 100px/s on a 100px leg: out (1s), back (1s), out again (1s).
      expect(named(g, 'guard').x, closeTo(200, 8)); // ±a few frames of start-up and arrival rounding
    },
  );

  testWithGame(
    'Wander moves or pauses; Burst adds particles; Velocity after Body is ignored',
    () => KilnGame(
      scene([
        ent('w', [
          b('Wander', {'speed': 50, 'interval': 1}),
        ]),
        ent('fx', [
          b('Timer', {
            'interval': 0.1,
            'repeat': false,
            'actions': [
              act('Burst', {'count': 5}),
            ],
          }),
        ]),
        ent('both', [
          b('Body'),
          b('Velocity', {'vx': 999}),
        ]),
      ]),
    ),
    (g) async {
      g.update(0.1);
      await g.ready();
      expect(g.world.children.whereType<ParticleSystemComponent>(), hasLength(1));
      expect(named(g, 'both').children.whereType<Motion>(), hasLength(1));
      final v = named(g, 'w').children.whereType<Motion>().single.v.length;
      expect(v == 0 || (v - 50).abs() < 1e-3, isTrue, reason: 'v=$v'); // float32 vectors
    },
  );

  testWithGame(
    'OffScreen ignores entities born outside until they enter; Move8 stays inside the world',
    () => KilnGame(
      scene([
        ent(
          'incoming',
          [
            b('Velocity', {'vy': 300}),
            b('OffScreen', {
              'actions': [
                act('AddVariable', {'name': 'score', 'value': 1}),
              ],
            }),
          ],
          pos: [100, -50],
        ),
        ent(
          'ship',
          [
            b('Move8', {'speed': 1000}),
          ],
          pos: [790, 100],
        ),
      ]),
    ),
    (g) async {
      g.onKeyEvent(down(LogicalKeyboardKey.arrowRight), {LogicalKeyboardKey.arrowRight});
      g.update(0.1);
      g.update(0.5);
      expect(g.vars['score'], 0); // entered, still inside
      expect(named(g, 'ship').toAbsoluteRect().right, closeTo(800, 1e-3));
      for (var i = 0; i < 30; i++) {
        g.update(0.1);
      }
      expect(g.vars['score'], 1); // left at the bottom
    },
  );

  test('parsePoints', () {
    expect(parsePoints(' 1,2 ; 3 , 4;bad; 5'), [Vector2(1, 2), Vector2(3, 4)]);
    expect(parsePoints(''), isEmpty);
  });
}

extension<T> on T {
  T also(void Function(T) f) {
    f(this);
    return this;
  }
}
