import 'dart:convert';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;
import 'package:flutter_test/flutter_test.dart';
import 'package:kiln/kiln.dart';
import 'package:kiln/src/builtins.dart' show parseClips, Motion;

Map<String, Object?> ent(
  String name,
  List<Map<String, Object?>> behaviors, {
  List<num> pos = const [100, 100],
  List<String> tags = const [],
}) => {
  'id': name,
  'name': name,
  'position': pos,
  'size': [50, 50],
  'tags': tags,
  'behaviors': behaviors,
};

Map<String, Object?> b(String type, [Map<String, Object?> props = const {}]) => {'type': type, 'props': props};

Map<String, Object?> act(String type, [Map<String, Object?> args = const {}]) => {'type': type, ...args};

/// One-shot Timer that fires [actions] on the first 1s update.
Map<String, Object?> once(List<Map<String, Object?>> actions) =>
    b('Timer', {'interval': 1, 'repeat': false, 'actions': actions});

SceneDoc scene(List<Map<String, Object?>> entities, {List<num>? world}) => SceneDoc.fromJson({
  'size': [400, 300],
  'world': ?world,
  'variables': {'score': 0},
  'entities': entities,
});

Iterable<KilnEntity> all(KilnGame g) => g.world.descendants().whereType<KilnEntity>();
KilnEntity named(KilnGame g, String n) => all(g).firstWhere((e) => e.node.name == n);

KeyEvent down(LogicalKeyboardKey k) =>
    KeyDownEvent(physicalKey: PhysicalKeyboardKey.space, logicalKey: k, timeStamp: Duration.zero);
KeyEvent up(LogicalKeyboardKey k) =>
    KeyUpEvent(physicalKey: PhysicalKeyboardKey.space, logicalKey: k, timeStamp: Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('scene format', () {
    test('old scenes load with no tags and world = view', () {
      final s = SceneDoc.fromJson({
        'size': [400, 700],
        'entities': [
          {'id': 'a', 'name': 'a'},
        ],
      });
      expect(s.world, isNull);
      expect(s.worldSize, Vector2(400, 700));
      expect(s.entities.single.tags, isEmpty);
      // Untouched fields stay out of the file so old scenes round-trip unchanged.
      expect(s.toJson().containsKey('world'), isFalse);
      expect((s.toJson()['entities'] as List).single, isNot(contains('tags')));
    });

    test('world and tags round trip; bad tags dropped', () {
      final s = SceneDoc.fromJson({
        'size': [400, 300],
        'world': [2000, 300],
        'entities': [
          {
            'id': 'a',
            'tags': ['enemy', 3, '', 'boss'],
          },
        ],
      });
      expect(s.worldSize, Vector2(2000, 300));
      expect(s.entities.single.tags, ['enemy', 'boss']);
      final back = SceneDoc.fromJson(jsonDecode(jsonEncode(s.toJson())));
      expect(back.worldSize, Vector2(2000, 300));
      expect(back.entities.single.tags, ['enemy', 'boss']);
    });
  });

  testWithGame(
    'Emit reaches every OnEvent listener; self-re-emit is bounded',
    () => KilnGame(
      scene([
        ent('src', [
          once([
            act('Emit', {'event': 'hit'}),
          ]),
        ]),
        for (final n in ['a', 'b'])
          ent(n, [
            b('OnEvent', {
              'event': 'hit',
              'actions': [
                act('AddVariable', {'name': 'score', 'value': 1}),
              ],
            }),
          ]),
        ent('loop', [
          b('OnEvent', {
            'event': 'hit',
            'actions': [
              act('AddVariable', {'name': 'echo', 'value': 1}),
              act('Emit', {'event': 'hit'}),
            ],
          }),
        ]),
      ]),
    ),
    (g) async {
      g.update(1);
      expect(g.vars['echo'], 17);
      expect(g.vars['score'], 2 * 17);
    },
  );

  testWithGame(
    'target addresses self, a name or a #tag',
    () => KilnGame(
      scene([
        ent('ctl', [
          once([
            act('Destroy', {'target': '#enemy'}),
            act('SetProp', {'target': 'hero', 'prop': 'x', 'mode': 'add', 'value': 5}),
            act('SetProp', {'prop': 'visible', 'value': 0}),
          ]),
        ]),
        ent('hero', []),
        ent('e1', [], tags: ['enemy']),
        ent('e2', [], tags: ['enemy', 'boss']),
      ]),
    ),
    (g) async {
      g.update(1);
      await g.ready();
      expect(all(g).map((e) => e.node.name), unorderedEquals(['ctl', 'hero']));
      expect(named(g, 'hero').x, 105);
      expect(named(g, 'ctl').isVisible, isFalse);
    },
  );

  testWithGame(
    'SetProp vx adds one Motion and moves; Velocity local follows angle',
    () => KilnGame(
      scene([
        ent('m', [
          once([
            act('SetProp', {'prop': 'vx', 'value': 10}),
            act('SetProp', {'prop': 'vy', 'value': 20}),
          ]),
        ]),
        ent('r', [
          b('Velocity', {'vx': 10, 'space': 'local'}),
        ]),
      ]),
    ),
    (g) async {
      named(g, 'r').angle = 1.5707963267948966;
      g.update(1);
      await g.ready();
      final m = named(g, 'm');
      expect(m.children.whereType<Motion>(), hasLength(1));
      g.update(1);
      expect(m.position.x, closeTo(110, 1e-6));
      expect(m.position.y, closeTo(120, 1e-6));
      // Local +x rotated 90° points down.
      expect(named(g, 'r').position.x, closeTo(100, 1e-6));
      expect(named(g, 'r').position.y, closeTo(120, 1e-6));
    },
  );

  testWithGame(
    'Spawn places prefab at self + rotated offset with self angle',
    () => KilnGame(
      scene([
        ent('Bullet', [b('Prefab')]),
        ent('gun', [
          once([
            act('Spawn', {'prefab': 'Bullet', 'x': 10, 'y': 0}),
            act('Spawn', {'prefab': 'Missing'}),
          ]),
        ]),
      ]),
    ),
    (g) async {
      named(g, 'gun').angle = 1.5707963267948966;
      g.update(1);
      await g.ready();
      final bullet = named(g, 'Bullet');
      expect(bullet.position.x, closeTo(100, 1e-6));
      expect(bullet.position.y, closeTo(110, 1e-6));
      expect(bullet.angle, closeTo(1.5707963267948966, 1e-9));
      expect(all(g), hasLength(2));
    },
  );

  final keyScene = scene([
    ent('p', [
      b('OnKey', {
        'key': 'Space',
        'on': 'down',
        'actions': [
          act('AddVariable', {'name': 'score', 'value': 1}),
        ],
      }),
      b('OnKey', {
        'key': 'D',
        'on': 'held',
        'actions': [
          act('AddVariable', {'name': 'held', 'value': 1}),
        ],
      }),
      b('OnKey', {
        'key': 'Shift',
        'on': 'up',
        'actions': [
          act('AddVariable', {'name': 'up', 'value': 1}),
        ],
      }),
    ]),
  ]);

  testWithGame('OnKey down/held/up; Shift matches left shift', () => KilnGame(keyScene), (g) async {
    g.onKeyEvent(down(LogicalKeyboardKey.space), {});
    g.onKeyEvent(down(LogicalKeyboardKey.keyD), {});
    g.update(0.1);
    g.update(0.1);
    g.onKeyEvent(up(LogicalKeyboardKey.keyD), {});
    g.update(0.1);
    g.onKeyEvent(up(LogicalKeyboardKey.shiftLeft), {});
    expect([g.vars['score'], g.vars['held'], g.vars['up']], [1, 2, 1]);
  });

  testWithGame('OnKey and OnEvent are inert while editing', () => KilnGame(keyScene, editing: true), (g) async {
    expect(g.onKeyEvent(down(LogicalKeyboardKey.space), {}), KeyEventResult.ignored);
    expect(g.vars['score'], 0);
  });

  testWithGame(
    'Camera follows into the world and clamps at its edge',
    () => KilnGame(
      scene(
        [
          ent(
            'hero',
            [
              b('Camera'),
              b('Velocity', {'vx': 1000}),
            ],
            pos: [100, 150],
          ),
        ],
        world: [1000, 300],
      ),
    ),
    (g) async {
      expect(g.camera.viewfinder.position.x, 0); // clamped at the left edge
      g.update(0.3); // hero at x=400 → view centered → left = 200
      expect(g.camera.viewfinder.position.x, closeTo(200, 1e-6));
      g.update(1); // hero far right → clamped at world - view
      expect(g.camera.viewfinder.position.x, 600);
      expect(g.camera.viewfinder.position.y, 0);
    },
  );

  testWithGame(
    'OffScreen fires once when leaving the view',
    () => KilnGame(
      scene([
        ent(
          'b',
          [
            b('Velocity', {'vx': 200}),
            b('OffScreen', {
              'actions': [
                act('AddVariable', {'name': 'score', 'value': 1}),
              ],
            }),
          ],
          pos: [350, 150],
        ),
      ]),
    ),
    (g) async {
      g.update(0.1);
      expect(g.vars['score'], 0);
      g.update(1);
      g.update(1);
      expect(g.vars['score'], 1);
    },
  );

  final music = <String?>[];
  testWithGame(
    'PlayMusic/StopMusic use the hook; removing the game stops music',
    () => KilnGame(
      scene([
        ent('s', [
          once([
            act('PlayMusic', {'file': 'theme.mp3'}),
            act('StopMusic'),
            act('PlayMusic', {'file': 'theme.mp3'}),
            act('PlayMusic'),
          ]),
        ]),
      ]),
      playMusic: music.add,
    ),
    (g) async {
      g.update(1);
      expect(music, ['theme.mp3', null, 'theme.mp3']);
      g.onRemove();
      expect(music.last, isNull);
    },
  );

  testWithGame(
    'game-wide actions run once and ignore target',
    () => KilnGame(
      scene([
        ent('ctl', [
          once([
            act('AddVariable', {'target': '#enemy', 'name': 'score', 'value': 1}),
          ]),
        ]),
        ent('e1', [], tags: ['enemy']),
        ent('e2', [], tags: ['enemy']),
      ]),
    ),
    (g) async {
      g.update(1);
      expect(g.vars['score'], 1);
    },
  );

  test('schema keeps targeted=false for game-wide custom actions', () {
    final app = KilnRegistry()..registerAction(ActionDef('Pause', const [], (s, a) {}, targeted: false));
    final editor = KilnRegistry()..loadSchema(jsonDecode(jsonEncode(app.schemaJson())));
    expect(editor.actions['Pause']!.targeted, isFalse);
    expect(editor.actions['Destroy']!.targeted, isTrue);
  });

  test('parseClips', () {
    expect(parseClips('', 6), {'default': (0, 5)});
    expect(parseClips('idle:0-1, run: 2 - 9 ,hit:4, bad, x:9', 6), {
      'idle': (0, 1),
      'run': (2, 5),
      'hit': (4, 4),
      'x': (5, 5),
    });
    expect(parseClips('a:3-1', 6), {'a': (3, 3)});
    expect(parseClips('a:0', 0), isEmpty);
  });

  testWithGame(
    'SpriteAnimation builds clips; PlayAnim switches clip',
    () => KilnGame(
      scene([
        ent('s', [
          b('SpriteAnimation', {'image': 'dot.png', 'clips': 'idle:0, run:0', 'start': 'run'}),
          once([
            act('PlayAnim', {'clip': 'idle'}),
            act('PlayAnim', {'clip': 'nope'}),
          ]),
        ]),
        ent('missing', [
          b('SpriteAnimation', {'image': 'nope.png'}),
        ]),
      ]),
      bundle: _PngBundle(),
    ),
    (g) async {
      final anim = named(g, 's').children.whereType<SpriteAnimationGroupComponent<String>>().single;
      expect(anim.current, 'run');
      g.update(1);
      expect(anim.current, 'idle');
      expect(named(g, 'missing').children.whereType<SpriteAnimationGroupComponent<String>>(), isEmpty);
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
