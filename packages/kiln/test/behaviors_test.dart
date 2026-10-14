import 'dart:convert';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiln/kiln.dart';

Map<String, Object?> ent(String name, List<Map<String, Object?>> behaviors, {List<num> pos = const [100, 100]}) => {
  'id': name,
  'name': name,
  'position': pos,
  'size': [50, 50],
  'behaviors': behaviors,
};

Map<String, Object?> b(String type, [Map<String, Object?> props = const {}]) => {'type': type, 'props': props};

SceneDoc scene(List<Map<String, Object?>> entities) => SceneDoc.fromJson({
  'variables': {'score': 0},
  'entities': entities,
});

Iterable<KilnEntity> entities(KilnGame g) => g.world.children.whereType<KilnEntity>();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final loaded = <String>[];
  final timerScene = scene([
    ent('clock', [
      b('Timer', {
        'interval': 1,
        'actions': [
          {'type': 'AddVariable', 'name': 'score', 'value': 1},
        ],
      }),
      b('Condition', {
        'variable': 'score',
        'op': '>=',
        'value': 2,
        'actions': [
          {'type': 'LoadScene', 'scene': 'next'},
        ],
      }),
    ]),
  ]);

  testWithGame('Timer ticks, Condition fires once on edge', () => KilnGame(timerScene, onLoadScene: loaded.add), (
    g,
  ) async {
    g.update(1);
    g.update(1);
    expect(g.vars['score'], 2);
    expect(loaded, ['next']);
    g.update(1);
    expect(g.vars['score'], 3);
    expect(loaded, ['next']);
  });

  testWithGame('editing freezes time', () => KilnGame(timerScene, editing: true), (g) async {
    g.update(5);
    expect(g.vars['score'], 0);
  });

  final spawnScene = scene([
    ent('Ball', [b('Prefab'), b('Shape')]),
    ent(
      'spawner',
      [
        b('Spawner', {'prefab': 'Ball', 'interval': 0.5, 'max': 2}),
      ],
      pos: [200, 200],
    ),
  ]);

  testWithGame('Prefab hidden at play, Spawner clones it up to max', () => KilnGame(spawnScene), (g) async {
    expect(entities(g).map((e) => e.node.name), ['spawner']);
    for (var i = 0; i < 4; i++) {
      g.update(0.5);
    }
    await g.ready();
    final balls = entities(g).where((e) => e.node.name == 'Ball').toList();
    expect(balls, hasLength(2));
    for (final ball in balls) {
      // Spawner rect: center 200,200 size 50.
      expect(ball.position.x, inInclusiveRange(175, 225));
      expect(ball.position.y, inInclusiveRange(175, 225));
    }
  });

  testWithGame('Prefab visible while editing', () => KilnGame(spawnScene, editing: true), (g) async {
    expect(entities(g), hasLength(2));
  });

  testWithGame(
    'Tween moveBy once',
    () => KilnGame(
      scene([
        ent('m', [
          b('Tween', {'kind': 'moveBy', 'x': 10, 'y': 0, 'duration': 1, 'loop': 'once'}),
        ]),
      ]),
    ),
    (g) async {
      g.update(1);
      expect(entities(g).single.position.x, closeTo(110, 0.001));
    },
  );

  testWithGame(
    'OnCollide filters by name',
    () => KilnGame(
      scene([
        ent('A', [
          b('Collider'),
          b('OnCollide', {
            'with': 'B',
            'actions': [
              {'type': 'AddVariable', 'name': 'score', 'value': 1},
            ],
          }),
        ]),
        ent('B', [b('Collider')], pos: [120, 100]),
        ent('C', [b('Collider')], pos: [80, 100]),
      ]),
    ),
    (g) async {
      g.update(0);
      expect(g.vars['score'], 1);
    },
  );

  testWithGame(
    'custom behavior and action from the app',
    () => KilnGame(
      scene([
        ent('s', [
          b('Spin', {'speed': 2}),
          b('Timer', {
            'interval': 1,
            'repeat': false,
            'actions': [
              {'type': 'AddVariable', 'name': 'score', 'value': 3},
              {'type': 'Double'},
            ],
          }),
        ]),
      ]),
      registry: customRegistry,
    ),
    (g) async {
      g.update(1);
      expect(entities(g).single.angle, closeTo(2, 0.001));
      expect(g.vars['score'], 6);
    },
  );

  test('schema round trip: custom types become editable placeholders, built-ins untouched', () {
    final json = jsonDecode(jsonEncode(customRegistry.schemaJson()));
    final editor = KilnRegistry();
    final shapeBefore = editor.behaviors['Shape'];
    expect(editor.loadSchema(json), ['Spin', 'Double']);
    expect(editor.behaviors['Shape'], same(shapeBefore));
    final speed = editor.behaviors['Spin']!.props.single;
    expect((speed.key, speed.kind, speed.defaultValue), ('speed', PropKind.number, 1));
    expect(editor.loadSchema('garbage'), isEmpty);
    expect(
      editor.loadSchema({
        'behaviors': [
          {
            'type': 'X',
            'props': [
              {'key': 'k', 'kind': 'future'},
            ],
          },
        ],
      }),
      ['X'],
    );
    expect(editor.behaviors['X']!.props.single.kind, PropKind.string);
  });

  final played = <String>[];
  testWithGame(
    'PlaySound uses the game hook',
    () => KilnGame(
      scene([
        ent('s', [
          b('Timer', {
            'interval': 1,
            'repeat': false,
            'actions': [
              {'type': 'PlaySound', 'file': 'pop.wav'},
              {'type': 'PlaySound'},
            ],
          }),
        ]),
      ]),
      playSound: played.add,
    ),
    (g) async {
      g.update(1);
      expect(played, ['pop.wav']);
    },
  );

  testWithGame(
    'Sprite loads through the bundle; a missing image is skipped',
    () => KilnGame(
      scene([
        ent('ok', [
          b('Sprite', {'image': 'dot.png'}),
        ]),
        ent('missing', [
          b('Sprite', {'image': 'nope.png'}),
        ]),
      ]),
      bundle: _PngBundle(),
    ),
    (g) async {
      final byName = {for (final e in entities(g)) e.node.name: e};
      expect(byName['ok']!.children.whereType<SpriteComponent>(), hasLength(1));
      expect(byName['missing']!.children.whereType<SpriteComponent>(), isEmpty);
    },
  );
}

/// Serves a 1x1 PNG for assets/images/dot.png only.
class _PngBundle extends CachingAssetBundle {
  static final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  );

  @override
  Future<ByteData> load(String key) async =>
      key == 'assets/images/dot.png' ? ByteData.sublistView(_png) : throw Exception('not found: $key');
}

// Mirrors the README example: custom behavior + custom action registered by the app.
class Spin extends Component with ParentIsA<KilnEntity> {
  Spin(this.speed);
  final double speed;

  @override
  void update(double dt) => parent.angle += speed * dt;
}

final customRegistry = KilnRegistry()
  ..register(BehaviorDef('Spin', const [PropDef('speed', PropKind.number, 1)], (e, p) => Spin(p.number('speed'))))
  ..registerAction(
    ActionDef('Double', const [PropDef('name', PropKind.string, 'score')], (self, a) {
      final v = self.game.vars[a.string('name')];
      if (v is num) self.game.vars[a.string('name')] = v * 2;
    }),
  );
