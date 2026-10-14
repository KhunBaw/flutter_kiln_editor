import 'package:flame/game.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiln/kiln.dart';

Map<String, Object?> ent(
  String name,
  List<Map<String, Object?>> behaviors, {
  List<num> pos = const [100, 100],
  List<num> size = const [20, 20],
}) => {'id': name, 'name': name, 'position': pos, 'size': size, 'behaviors': behaviors};

Map<String, Object?> b(String type, [Map<String, Object?> props = const {}]) => {'type': type, 'props': props};
Map<String, Object?> act(String type, [Map<String, Object?> args = const {}]) => {'type': type, ...args};

SceneDoc scene(List<Map<String, Object?>> entities) => SceneDoc.fromJson({
  'size': [800, 600],
  'variables': {'score': 0},
  'entities': entities,
});

KilnEntity named(KilnGame g, String n) =>
    g.world.descendants().whereType<KilnEntity>().firstWhere((e) => e.node.name == n);

Map<String, Object?> grid() => ent(
  'map',
  [
    b('Tilemap', {
      'tile': 32,
      'cols': 3,
      'tiles': [1, 0, 0, 0, 2, 0],
      'solid': '1',
    }),
  ],
  pos: [96, 64],
  size: [96, 64],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWithGame(
    'tiles: SetTile, FillTiles, tile() / cellX() / cellY() formulas, bounds',
    () => KilnGame(scene([grid()])),
    (g) async {
      final m = named(g, 'map');
      Object? ev(String s) => evalExpr(s, ExprScope(g, m));
      expect(ev('tile(0, 0) * 10 + tile(1, 1)'), 12);
      expect(ev('tile(9, 9)'), -1);
      expect(ev('cellX(120) + cellY(100) * 10'), 22); // origin is the entity's top-left (48, 32)
      m.runActions([
        act('SetTile', {'c': 2, 'r': 0, 'tile': 5}),
        act('SetTile', {'c': 7, 'r': 7, 'tile': 5}), // outside: ignored
        act('FillTiles', {'c': 0, 'r': 1, 'w': 9, 'h': 9, 'tile': 3}), // clipped to the grid
      ]);
      expect(ev('tile(2, 0)'), 5);
      expect(ev('tile(0, 1) + tile(2, 1)'), 6);
      expect(ev('tile(0, 0)'), 1);
    },
  );

  testWithGame(
    'CameraShake moves the viewport then restores it; no-op while editing',
    () => KilnGame(scene([ent('a', [])])),
    (g) async {
      final base = g.camera.viewport.position.clone();
      named(g, 'a').runActions([
        act('CameraShake', {'strength': 20, 'time': 0.2}),
      ]);
      g.update(0.05);
      await g.ready();
      g.update(0.05);
      expect(g.camera.viewport.position, isNot(base));
      g.update(0.5);
      g.update(0.01);
      expect(g.camera.viewport.position, base);
    },
  );

  testWidgets('OnPointer + Joystick: real taps and drags reach them and still reach entities underneath', (
    tester,
  ) async {
    final g = KilnGame(
      scene([
        ent('probe', [
          b('OnPointer', {
            'down': [
              act('SetVariable', {'name': 'dx', 'value': '=pointer.x'}),
              act('AddVariable', {'name': 'downs'}),
            ],
            'move': [
              act('SetVariable', {'name': 'mx', 'value': '=pointer.x'}),
            ],
            'up': [
              act('AddVariable', {'name': 'ups'}),
            ],
          }),
        ]),
        ent(
          'btn',
          [
            b('OnTap', {
              'actions': [
                act('AddVariable', {'name': 'taps'}),
              ],
            }),
          ],
          pos: [600, 100],
          size: [80, 80],
        ),
        ent(
          'stick',
          [
            b('Joystick', {'speed': 100, 'target': 'ship'}),
          ],
          pos: [100, 500],
          size: [100, 100],
        ),
        ent('ship', [], pos: [400, 300]),
      ]),
    );
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GameWidget(game: g),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    await tester.tapAt(const Offset(600, 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(g.vars['taps'], 1); // the entity under the pointer layer still gets the tap
    expect(g.vars['downs'], 1);
    expect(g.vars['ups'], 1);
    expect(g.vars['dx'], closeTo(600, 1));

    await tester.dragFrom(const Offset(100, 500), const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 100));
    expect(g.vars['downs'], 2);
    expect(g.vars['ups'], 2);
    expect(g.vars['mx'], greaterThanOrEqualTo(140)); // the test drag adds touch slop
    expect(g.vars['joyX'], 0); // released
    expect(g.pointerDown, false);

    final gesture = await tester.startGesture(const Offset(100, 500));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 50));
    expect(g.vars['joyX'], closeTo(0.8, 0.05)); // 40px of a 50px radius
    expect(named(g, 'ship').motion!.v.x, closeTo(80, 5));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 50));
    expect(named(g, 'ship').motion!.v.x, 0);
  });
}
