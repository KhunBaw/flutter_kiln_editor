import 'dart:convert';
import 'dart:io';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiln/kiln.dart';

void main() {
  testWidgets('real key events reach OnKey through GameWidget focus', (tester) async {
    final doc = SceneDoc.fromJson(
      jsonDecode(File('../../examples/platformer/assets/scenes/level1.kiln.json').readAsStringSync()),
    );
    final game = KilnGame(doc);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GameWidget(game: game)),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final player = game.world.children.whereType<KilnEntity>().firstWhere((e) => e.node.name == 'Player');
    final x0 = player.x;
    debugPrint('focus=${FocusManager.instance.primaryFocus} listeners=${game.keyListeners.length}');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    debugPrint('x0=$x0 x=${player.x}');
    expect(player.x, greaterThan(x0 + 50));
  });

  testWidgets('KilnGameWidget: keys work after the scene loads', (tester) async {
    final bytes = File('../../examples/platformer/assets/scenes/level1.kiln.json').readAsBytesSync();
    tester.binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (msg) async {
      final key = utf8.decode(msg!.buffer.asUint8List());
      return key.endsWith('level1.kiln.json') ? ByteData.sublistView(bytes) : null;
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: KilnGameWidget(asset: 'assets/scenes/level1.kiln.json')),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final game = tester.widget<GameWidget<KilnGame>>(find.byWidgetPredicate((w) => w is GameWidget)).game!;
    final player = game.world.children.whereType<KilnEntity>().firstWhere((e) => e.node.name == 'Player');
    final x0 = player.x;
    debugPrint('W focus=${FocusManager.instance.primaryFocus} listeners=${game.keyListeners.length}');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    debugPrint('W x0=$x0 x=${player.x}');
    expect(player.x, greaterThan(x0 + 50));
  });
}
