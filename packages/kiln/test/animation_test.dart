import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiln/kiln.dart';

void main() {
  group('sampling', () {
    final keys = parseKeys([
      {'t': 1, 'v': 100, 'ease': 'easeIn'},
      {'t': 0, 'v': 0},
      {'t': 'bad', 'v': 1},
      {'t': 2, 'v': 0},
    ]);

    test('parseKeys sorts and drops bad entries', () {
      expect(keys.map((k) => k.t), [0, 1, 2]);
    });

    test('holds ends and interpolates linearly by default', () {
      expect(sampleKeys(keys, -1), 0);
      expect(sampleKeys(keys, 0.5), 50);
      expect(sampleKeys(keys, 9), 0);
      expect(sampleKeys(const [], 1), isNull);
    });

    test('easing is taken from the key that starts the segment', () {
      expect(sampleKeys(keys, 1.5), closeTo(100 - 100 * 0.125, 1e-9));
    });

    test('every ease maps 0→0 and 1→1', () {
      for (final e in animEases) {
        expect(ease(e, 0), closeTo(0, 1e-9), reason: e);
        expect(ease(e, 1), closeTo(1, 1e-9), reason: e);
      }
    });

    test('clipTime once/loop/pingpong', () {
      expect(clipTime(3, 2, 'once'), 2);
      expect(clipTime(3, 2, 'loop'), 1);
      expect(clipTime(3, 2, 'pingpong'), 1);
      expect(clipTime(2.5, 2, 'pingpong'), 1.5);
    });
  });

  testWithGame(
    'Animator moves the entity and Animate restarts it',
    () => KilnGame(
      SceneDoc.fromJson({
        'entities': [
          {
            'id': 'a',
            'name': 'a',
            'position': [0, 0],
            'behaviors': [
              {
                'type': 'Animator',
                'props': {
                  'duration': 1,
                  'loop': 'once',
                  'tracks': [
                    {
                      'prop': 'x',
                      'keys': [
                        {'t': 0, 'v': 0},
                        {'t': 1, 'v': 100},
                      ],
                    },
                    {
                      'prop': 'opacity',
                      'keys': [
                        {'t': 0, 'v': 1},
                        {'t': 1, 'v': 0.5},
                      ],
                    },
                  ],
                },
              },
            ],
          },
        ],
      }),
    ),
    (g) async {
      await g.ready();
      final e = g.world.children.whereType<KilnEntity>().first;
      await e.loaded;
      g.update(0.5);
      expect(e.position.x, closeTo(50, 1e-6));
      expect(e.alpha, closeTo(0.75, 1e-6));
      g.update(2);
      expect(e.position.x, 100);
      e.animator!.restart();
      expect(e.position.x, 0);
    },
  );
}
