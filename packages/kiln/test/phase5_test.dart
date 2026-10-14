import 'dart:convert';
import 'dart:io';

import 'package:flame/game.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiln/kiln.dart';

Map<String, Object?> ent(
  String name,
  List<Map<String, Object?>> behaviors, {
  List<num> pos = const [100, 100],
  List<num> size = const [60, 60],
  List<String> tags = const [],
}) => {'id': name, 'name': name, 'position': pos, 'size': size, 'tags': tags, 'behaviors': behaviors};

Map<String, Object?> b(String type, [Map<String, Object?> props = const {}]) => {'type': type, 'props': props};
Map<String, Object?> act(String type, [Map<String, Object?> args = const {}]) => {'type': type, ...args};

SceneDoc scene(List<Map<String, Object?>> entities) => SceneDoc.fromJson({
  'size': [800, 600],
  'world': [2000, 600],
  'variables': {'score': 0, 'hp': 50},
  'entities': entities,
});

KilnEntity named(KilnGame g, String n) =>
    g.world.descendants().whereType<KilnEntity>().firstWhere((e) => e.node.name == n);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWithGame(
    'Hud keeps its screen position while the camera scrolls',
    () => KilnGame(
      scene([
        ent(
          'Hero',
          [
            b('Camera', {'clamp': true}),
          ],
          pos: [400, 300],
        ),
        ent('Score', [b('Hud')], pos: [50, 30]),
      ]),
    ),
    (g) async {
      final hud = named(g, 'Score');
      final hero = named(g, 'Hero');
      hero.x = 1200;
      g.update(1 / 60);
      g.update(1 / 60);
      expect(g.camera.viewfinder.position.x, greaterThan(500));
      expect(hud.x - g.camera.viewfinder.position.x, closeTo(50, 1e-3));
      expect(hud.y, closeTo(30, 1e-3));
    },
  );

  testWithGame(
    'Button runs its actions on tap',
    () => KilnGame(
      scene([
        ent('Go', [
          b('Button', {
            'actions': [
              act('AddVariable', {'name': 'score', 'value': 5}),
            ],
          }),
        ]),
      ]),
    ),
    (g) async {
      for (final h in [...named(g, 'Go').tapHandlers]) {
        h();
      }
      expect(g.vars['score'], 5);
    },
  );

  testWidgets('Draggable snaps into an accepting DropZone, otherwise returns home', (tester) async {
    final g = KilnGame(
      scene([
        ent(
          'Card',
          [
            b('Draggable', {
              'actions': [
                act('AddVariable', {'name': 'score', 'value': 1}),
              ],
            }),
          ],
          pos: [100, 100],
          tags: ['card'],
        ),
        ent(
          'Slot',
          [
            b('DropZone', {
              'accept': '#card',
              'actions': [
                act('AddVariable', {'name': 'score', 'value': 10}),
              ],
            }),
          ],
          pos: [500, 300],
          size: [120, 120],
        ),
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
    final card = named(g, 'Card');

    await tester.dragFrom(const Offset(100, 100), const Offset(0, 100)); // lands at (100,200): outside the slot
    await tester.pump(const Duration(milliseconds: 100));
    expect(card.position.x, closeTo(100, 1e-3));
    expect(card.position.y, closeTo(100, 1e-3));
    expect(g.vars['score'], 0);

    await tester.dragFrom(const Offset(100, 100), const Offset(400, 200)); // lands at (500,300): in the slot
    await tester.pump(const Duration(milliseconds: 100));
    expect(card.position.x, closeTo(500, 1e-3));
    expect(card.position.y, closeTo(300, 1e-3));
    expect(g.vars['score'], 11);
  });

  testWidgets('KilnGameWidget fade cross-fades into the new scene', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (msg) async {
      final key = utf8.decode(msg!.buffer.asUint8List());
      return key.endsWith('.kiln.json') ? ByteData.sublistView(utf8.encode(jsonEncode(scene([]).toJson()))) : null;
    });
    final c = KilnController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KilnGameWidget(asset: 'a.kiln.json', controller: c, fade: const Duration(milliseconds: 200)),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(FadeTransition), findsWidgets);
    expect(find.byType(GameWidget<KilnGame>), findsOneWidget);
  });

  testWidgets('examples/card: right cards fill their slots, a wrong drop snaps back', (tester) async {
    final g = KilnGame(
      SceneDoc.fromJson(jsonDecode(File('../../examples/card/assets/scenes/table.kiln.json').readAsStringSync())),
    );
    await tester.binding.setSurfaceSize(const Size(400, 700));
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
    Future<void> drag(String card, String slot) async {
      final from = named(g, card).position, to = named(g, slot).position;
      await tester.dragFrom(Offset(from.x, from.y), Offset(to.x - from.x, to.y - from.y));
      await tester.pump(const Duration(milliseconds: 100));
    }

    await drag('Card1', 'BlueSlot'); // red card into the blue slot
    expect(named(g, 'Card1').position.x, closeTo(80, 1e-3));
    expect(g.vars['placed'], 0);
    await drag('Card1', 'RedSlot');
    await drag('Card2', 'BlueSlot');
    await drag('Card3', 'RedSlot');
    expect(g.vars['placed'], 3);
    expect(g.vars['score'], 30);
  });
}
