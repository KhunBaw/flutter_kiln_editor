import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiln/kiln.dart';
import 'package:kiln_forge2d/kiln_forge2d.dart';

KilnGame _launcher() {
  final reg = KilnRegistry();
  registerForge2d(reg);
  final doc = SceneDoc.fromJson(
    jsonDecode(File('../../examples/launcher/assets/scenes/level1.kiln.json').readAsStringSync()),
  );
  return KilnGame(doc, registry: reg);
}

KilnEntity _named(KilnGame g, String n) =>
    g.world.descendants().whereType<KilnEntity>().firstWhere((e) => e.node.name == n);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWithGame('launcher: the scene stands still until a shot, and some shot topples the pig', _launcher, (g) async {
    for (var i = 0; i < 120; i++) {
      g.update(1 / 60);
    }
    expect(g.vars['pigs'], 0); // the tower is stable on its own
    expect(_named(g, 'Pig').y, closeTo(296, 6));
  });

  // Each candidate pull (px, degrees above the horizontal, aimed down-left of the ball) is a game of its own.
  final wins = <String>[];
  for (final pull in [110.0, 90.0]) {
    for (var deg = 20; deg <= 65; deg += 5) {
      testWithGame('launcher: pull $pull at $deg°', _launcher, (g) async {
        final ball = _named(g, 'Ball');
        final a = deg * pi / 180;
        final drag = ball.children.whereType<DragLaunch>().single;
        drag.aimTo(ball.absoluteCenter - Vector2(cos(a), -sin(a)) * pull);
        drag.release();
        for (var i = 0; i < 60 * 8 && g.vars['pigs'] == 0; i++) {
          g.update(1 / 60);
        }
        expect(g.vars['shots'], 1);
        if (g.vars['pigs'] == 1) wins.add('$pull@$deg');
      });
    }
  }

  test('launcher: some pull knocks the pig down', () {
    // ignore: avoid_print
    print('winning pulls: $wins');
    expect(wins, isNotEmpty);
  });
}
