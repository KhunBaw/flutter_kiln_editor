import 'dart:convert';
import 'dart:io';

import 'package:flame_test/flame_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiln/kiln.dart';
import 'package:kiln/src/builtins.dart' show Body, seedKilnRandom;

const _examples = [
  '../../examples/tap_game/assets/scenes',
  '../../examples/platformer/assets/scenes',
  '../../examples/shooter/assets/scenes',
];
const _scenes = '../../examples/tap_game/assets/scenes';

SceneDoc _load(String name, [String dir = _scenes]) =>
    SceneDoc.fromJson(jsonDecode(File('$dir/$name').readAsStringSync()));

KeyEvent _key(LogicalKeyboardKey k, {bool down = true}) => down
    ? KeyDownEvent(physicalKey: PhysicalKeyboardKey.space, logicalKey: k, timeStamp: Duration.zero)
    : KeyUpEvent(physicalKey: PhysicalKeyboardKey.space, logicalKey: k, timeStamp: Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every example scene loads and every behavior/action type is registered', () {
    final reg = KilnRegistry();
    final files = [
      for (final d in _examples)
        ...Directory(d).listSync().whereType<File>().where((f) => f.path.endsWith('.kiln.json')),
    ];
    expect(files, isNotEmpty);
    for (final f in files) {
      final doc = SceneDoc.fromJson(jsonDecode(f.readAsStringSync()));
      void walk(List<EntityNode> list) {
        for (final e in list) {
          for (final b in e.behaviors) {
            expect(reg.behaviors, contains(b.type), reason: '${f.path}: ${e.name}');
            for (final a in Props(b.props).list('actions')) {
              expect(reg.actions, contains((a as Map)['type']), reason: '${f.path}: ${e.name}');
            }
          }
          walk(e.children);
        }
      }

      walk(doc.entities);
    }
  });

  final sounds = <String>[];
  testWithGame(
    'sandbox: Space fires a bullet that hits a target; ArrowRight scrolls the camera',
    () => KilnGame(_load('sandbox.kiln.json'), playSound: sounds.add),
    (g) async {
      g.onKeyEvent(_key(LogicalKeyboardKey.space), {});
      g.onKeyEvent(_key(LogicalKeyboardKey.space, down: false), {});
      await g.ready(); // let the spawned bullet load (a real game gets this between frames)
      for (var i = 0; i < 20; i++) {
        g.update(0.05);
      }
      await g.ready();
      expect(sounds, ['pop.wav']);
      expect(g.vars['score'], 1);
      expect(g.world.children.whereType<KilnEntity>().where((e) => e.node.name == 'Bullet'), isEmpty);

      g.onKeyEvent(_key(LogicalKeyboardKey.arrowRight), {});
      for (var i = 0; i < 30; i++) {
        g.update(0.1);
      }
      g.onKeyEvent(_key(LogicalKeyboardKey.arrowRight, down: false), {});
      g.update(0.1);
      final player = g.world.children.whereType<KilnEntity>().firstWhere((e) => e.node.name == 'Player');
      expect(player.x, closeTo(200 + 220 * 3, 1e-6));
      // Deadzone 120 wide: the player rests 60px right of the view centre.
      expect(g.camera.viewfinder.position.x, closeTo(player.x - 200 - 60, 1e-6));
    },
  );

  final loads = <String>[];
  testWithGame(
    'platformer: a run-right-and-hop bot reaches the flag; falling in a pit restarts',
    () => KilnGame(_load('level1.kiln.json', _examples[1]), onLoadScene: loads.add),
    (g) async {
      final player = g.world.children.whereType<KilnEntity>().firstWhere((e) => e.node.name == 'Player');
      final body = player.children.whereType<Body>().single;
      bool solidAt(Rect probe) => g.solids.any((s) => s.parent.toAbsoluteRect().overlaps(probe));
      g.onKeyEvent(_key(LogicalKeyboardKey.arrowRight), {});
      for (var t = 0.0; t < 20 && loads.isEmpty; t += 1 / 60) {
        final r = player.toAbsoluteRect();
        // Hop when the ground ends just ahead or something blocks the way.
        final gap = !solidAt(Rect.fromLTWH(r.right + 30, r.bottom + 2, 4, 4));
        final wall = solidAt(Rect.fromLTWH(r.right + 2, r.top, 24, r.height - 2));
        if (body.onGround && (gap || wall)) {
          g.onKeyEvent(_key(LogicalKeyboardKey.space), {});
          g.onKeyEvent(_key(LogicalKeyboardKey.space, down: false), {});
        }
        g.update(1 / 60);
        await g.ready();
      }
      expect(loads, ['assets/scenes/win.kiln.json']);
      expect(g.vars['coins'], greaterThan(0)); // ground-level coins; ledges are optional

      loads.clear();
      g.onKeyEvent(_key(LogicalKeyboardKey.arrowRight, down: false), {});
      body.v.setZero();
      player.position.setValues(750, 200); // over the first pit
      for (var i = 0; i < 120 && loads.isEmpty; i++) {
        g.update(1 / 60);
      }
      expect(loads, ['assets/scenes/level1.kiln.json']);
    },
  );

  final shooterLoads = <String>[];
  testWithGame(
    'shooter: a fire-and-track bot scores; enemy fire and rams cost hp',
    () {
      seedKilnRandom(4); // bot gets hit only on some seeds
      return KilnGame(_load('level1.kiln.json', _examples[2]), onLoadScene: shooterLoads.add);
    },
    (g) async {
      final player = g.world.children.whereType<KilnEntity>().firstWhere((e) => e.node.name == 'Player');
      expect(g.vars['hp'], 3);
      for (var t = 0.0; t < 25 && shooterLoads.isEmpty; t += 1 / 60) {
        final foe = g.nearest(player, '#enemy');
        final keys = {LogicalKeyboardKey.space};
        if (foe != null && (foe.x - player.x).abs() > 6) {
          keys.add(foe.x < player.x ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowRight);
        }
        g.onKeyEvent(_key(LogicalKeyboardKey.space), keys);
        g.update(1 / 60);
        await g.ready();
      }
      expect(g.vars['score'], greaterThan(50));
      // The bot never dodges, so it gets hit; dying sends it to the lose scene.
      expect((g.vars['hp'] as num) < 3 || shooterLoads.isNotEmpty, isTrue);
      if (shooterLoads.isNotEmpty) expect(shooterLoads, ['assets/scenes/lose.kiln.json']);
    },
  );
}
