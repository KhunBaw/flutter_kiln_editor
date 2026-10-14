import 'dart:math';

import 'package:flame_test/flame_test.dart';

import 'dart:ui' show Canvas, PictureRecorder;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiln/kiln.dart';
import 'package:kiln/src/builtins.dart' show seedKilnRandom;

SceneDoc scene({String slices = '', Map<String, Object?> vars = const {}, Map<String, Object?> props = const {}}) =>
    SceneDoc.fromJson({
      'size': [400, 700],
      'variables': {'result': '-', ...vars},
      'entities': [
        {
          'id': 'w',
          'name': 'Wheel',
          'position': [200, 330],
          'size': [320, 320],
          'behaviors': [
            {
              'type': 'Wheel',
              'props': {'slices': slices, 'spinTime': 2, 'minTurns': 3, ...props},
            },
          ],
        },
      ],
    });

KilnEntity wheelOf(KilnGame g) => g.world.descendants().whereType<KilnEntity>().single;

Future<void> run(KilnGame g) async {
  for (var i = 0; i < 130; i++) {
    g.update(1 / 60);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sliceList: maps with defaults, entries without a label skipped', () {
    final s = sliceList([
      {'label': 'A', 'weight': 3, 'color': '#112233'},
      {'image': 'x'},
      'junk',
      {'label': 'B'},
    ]);
    expect(s.map((x) => x.label), ['A', 'B']);
    expect(s[0].weight, 3);
    expect(s[0].color, const Color(0xFF112233));
    expect(s[1].weight, 1);
  });

  test('parseSlices: optional fields, bad weight/colour fall back, blanks skipped', () {
    final s = parseSlices('A|a.png|3|#112233; B ;;C|x|oops|nope\nD');
    expect(s.map((x) => x.label), ['A', 'B', 'C', 'D']);
    expect(s[0].image, 'a.png');
    expect(s[0].weight, 3);
    expect(s[0].color, const Color(0xFF112233));
    expect(s[1].weight, 1);
    expect(s[2].weight, 1);
    expect(s[2].color, isNot(const Color(0xFFFF00FF)));
    expect(parseSlices('  ; '), isEmpty);
  });

  group('pickWeighted', () {
    test('follows the weights', () {
      final rng = Random(1);
      final hits = List.filled(3, 0);
      for (var i = 0; i < 20000; i++) {
        hits[pickWeighted([1, 3, 6], rng)]++;
      }
      expect(hits[0] / 20000, closeTo(0.1, 0.015));
      expect(hits[1] / 20000, closeTo(0.3, 0.015));
      expect(hits[2] / 20000, closeTo(0.6, 0.015));
    });

    test('zero and negative weights never drop; all-zero falls back to uniform', () {
      final rng = Random(2);
      for (var i = 0; i < 2000; i++) {
        expect(pickWeighted([0, -5, 2], rng), 2);
      }
      expect(
        {
          for (var i = 0; i < 200; i++) pickWeighted([0, 0, 0], rng),
        },
        {0, 1, 2},
      );
    });
  });

  testWithGame<KilnGame>(
    'Wheel: ends with the chosen slice under the pointer, sets result, emits won',
    () {
      seedKilnRandom(3);
      return KilnGame(scene(slices: 'S0||0;S1||0;S2||1;S3||0'), onEmit: (n, v) => _emitted.add((n, v)));
    },
    (g) async {
      await g.ready();
      g.emit('spin');
      await run(g);
      const s = 2 * pi / 4;
      // Slice 2's centre is 2.5 slices clockwise of the top; the turn brings it back to angle 0 (±0.35 slice).
      final off = (wheelOf(g).angle + 2.5 * s) % (2 * pi);
      expect((off > pi ? off - 2 * pi : off).abs(), lessThanOrEqualTo(s * 0.36));
      expect(g.vars['result'], 'S2');
      expect(_emitted.where((e) => e.$1 == 'won').map((e) => e.$2), [2]);
    },
  );

  testWithGame<KilnGame>(
    'Wheel: the app changes slices through the variable; a spin during a spin is ignored',
    () {
      seedKilnRandom(4);
      _emitted.clear();
      return KilnGame(
        scene(slices: 'Old', vars: {'slices': 'A||0;B||1'}),
        onEmit: (n, v) => _emitted.add((n, v)),
      );
    },
    (g) async {
      await g.ready();
      g.emit('spin');
      g.update(0.5);
      g.emit('spin');
      await run(g);
      expect(_emitted.where((e) => e.$1 == 'won'), hasLength(1));
      expect(g.vars['result'], 'B');
      g.vars['slices'] = 'X||1;Y||0';
      g.emit('spin');
      await run(g);
      expect(g.vars['result'], 'X');
    },
  );

  testWithGame<KilnGame>('Wheel: with no slices anywhere a spin does nothing', () => KilnGame(scene()), (g) async {
    await g.ready();
    g.emit('spin');
    await run(g);
    expect(wheelOf(g).angle, 0);
    expect(g.vars['result'], '-');
  });

  testWithGame<KilnGame>(
    'Wheel: the spin limit refuses extra spins, counts them, and the app can raise it',
    () {
      seedKilnRandom(5);
      _emitted.clear();
      return KilnGame(
        scene(slices: 'A||1;B||1', props: {'limit': 2}),
        onEmit: (n, v) => _emitted.add((n, v)),
      );
    },
    (g) async {
      await g.ready();
      for (var i = 0; i < 3; i++) {
        g.emit('spin');
        await run(g);
      }
      expect(_emitted.where((e) => e.$1 == 'won'), hasLength(2));
      expect(_emitted.where((e) => e.$1 == 'nospins'), hasLength(1));
      expect(g.vars['spins'], 2);
      expect(g.vars['left'], 0);
      g.vars['limit'] = 3;
      g.update(0.01);
      expect(g.vars['left'], 1);
      g.emit('spin');
      await run(g);
      expect(g.vars['spins'], 3);
    },
  );

  testWithGame<KilnGame>(
    'Wheel: unlimited shows ∞; the reveal card draws through its whole life without throwing',
    () => KilnGame(scene(slices: 'A||1;B||1', props: {'revealTime': 1})),
    (g) async {
      await g.ready();
      g.update(0.01);
      expect(g.vars['left'], '∞');
      g.emit('spin');
      for (var i = 0; i < 210; i++) {
        g.update(1 / 60);
        g.render(Canvas(PictureRecorder())); // spinning, then pop-in, hold and fade of the reveal
      }
    },
  );
}

final _emitted = <(String, Object?)>[];
