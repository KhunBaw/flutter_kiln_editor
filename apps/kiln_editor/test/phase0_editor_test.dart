import 'dart:io';

import 'package:flame/components.dart' show Vector2;
import 'package:flame/game.dart' show GameWidget;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiln/kiln.dart';
import 'package:kiln_editor/editor_state.dart';
import 'package:kiln_editor/main.dart';
import 'package:kiln_editor/panels.dart';

EditorState stateOf(WidgetTester t) => (t.state<State>(find.byType(EditorPage)) as dynamic).s as EditorState;

Future<EditorState> boot(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const KilnEditorApp());
  return stateOf(tester);
}

void main() {
  test('snap and view clamps', () {
    final s = EditorState();
    expect(s.snap(10.4), 10);
    s.setView(grid: 16);
    expect([s.snap(7), s.snap(9), s.snap(-9)], [0, 16, -16]);
    s.setView(zoom: 100);
    expect(s.zoom, 16);
    s.setView(zoom: 0);
    expect(s.zoom, 0.1);
  });

  test('assetFiles lists project images sorted, skips dotfiles; empty without project', () async {
    final dir = await Directory.systemTemp.createTemp('kiln_assets');
    addTearDown(() => dir.delete(recursive: true));
    final img = await Directory('${dir.path}/assets/images').create(recursive: true);
    for (final f in ['b.png', 'a.png', '.DS_Store']) {
      File('${img.path}/$f').writeAsBytesSync([0]);
    }
    final s = EditorState();
    expect(await s.assetFiles('images'), isEmpty);
    final before = s.assetsRevision;
    await s.openProject(dir.path);
    expect(s.assetsRevision, greaterThan(before));
    expect(await s.assetFiles('images'), ['a.png', 'b.png']);
    expect(await s.assetFiles('audio'), isEmpty);
  });

  testWidgets('zoom buttons, fit, and world view outline', (tester) async {
    final s = await boot(tester);
    await tester.tap(find.byTooltip('Zoom in (⌘ scroll)'));
    await tester.pump();
    expect(s.zoom, closeTo(1.25, 1e-9));
    await tester.tap(find.byTooltip('Fit the world (pan: space or middle drag, two-finger scroll)'));
    await tester.pump();
    expect((s.zoom, s.pan), (1.0, Offset.zero));

    expect(find.text('VIEW'), findsNothing);
    await tester.enterText(find.widgetWithText(Field, 'WORLD W'), '1200');
    await tester.pump();
    expect(s.doc.worldSize, Vector2(1200, 700));
    expect(find.text('VIEW'), findsOneWidget);
  });

  testWidgets('resize handle snaps to grid in one undo step; rotate handle turns', (tester) async {
    final s = await boot(tester);
    await tester.tap(find.byTooltip('Add entity'));
    await tester.pump();
    s.setView(grid: 16);
    await tester.pump();
    final e = s.selected!;
    final tl = e.position - e.size / 2;

    await tester.drag(find.byTooltip('Resize (snaps to grid)'), const Offset(60, 30));
    await tester.pump();
    expect(e.size.x, greaterThan(64));
    expect([e.size.x % 16, e.size.y % 16], [0, 0]);
    expect(e.position - e.size / 2, tl); // top-left stays put
    s.undo();
    expect(s.selected!.size, Vector2.all(64));
    await tester.pump();

    await tester.drag(find.byTooltip('Rotate (⇧ snaps to 15°)'), const Offset(200, 60));
    await tester.pump();
    expect(s.selected!.angle, greaterThan(0.5));
  });

  testWidgets('target shows for targeted actions only; tags edit as a list', (tester) async {
    final s = await boot(tester);
    await tester.tap(find.byTooltip('Add entity'));
    await tester.pump();
    s.edit(
      (_) => s.selected!.behaviors.add(
        BehaviorData('OnTap', {
          'actions': [
            {'type': 'Destroy'},
            {'type': 'AddVariable', 'name': 'score', 'value': 1},
          ],
        }),
      ),
    );
    await tester.pump();
    expect(find.widgetWithText(Field, 'TARGET'), findsOneWidget);

    await tester.enterText(find.widgetWithText(Field, 'TARGET'), '#enemy');
    await tester.pump();
    final actions = s.selected!.behaviors.last.props['actions'] as List;
    expect((actions.first as Map)['target'], '#enemy');

    await tester.enterText(find.widgetWithText(Field, 'TAGS'), 'enemy,  boss ,');
    await tester.pump();
    expect(s.selected!.tags, ['enemy', 'boss']);
  });

  testWidgets('Play: arrow keys reach the running game', (tester) async {
    final s = await boot(tester);
    s.addEntity(
      name: 'hero',
      behaviors: [
        BehaviorData('Shape'),
        BehaviorData('OnKey', {
          'key': 'ArrowRight',
          'on': 'held',
          'actions': [
            {'type': 'SetProp', 'prop': 'x', 'mode': 'add', 'value': 2},
          ],
        }),
      ],
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Play (⌘P)'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final game = tester.widget<GameWidget<KilnGame>>(find.byWidgetPredicate((w) => w is GameWidget<KilnGame>)).game!;
    final hero = game.world.children.whereType<KilnEntity>().single;
    final x0 = hero.x;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    expect(hero.x, greaterThan(x0 + 5));
    await tester.tap(find.byTooltip('Stop (⌘P)'));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Tilemap: PAINT in the inspector, pick a tile, click and drag the scene', (tester) async {
    final s = await boot(tester);
    s.addEntity(
      size: Vector2(128, 64),
      behaviors: [
        BehaviorData('Tilemap', {'tile': 32}),
      ],
    );
    await tester.pump();
    await tester.tap(find.text('PAINT'));
    await tester.pump();
    expect(s.paintId, s.selectedId);

    await tester.tap(find.text('FILL')); // fill the empty grid with tile 1
    await tester.pump();
    final view = find.byWidgetPredicate((w) => w is GameWidget);
    final tl = tester.getTopLeft(view);
    final k = (tester.getBottomRight(view) - tl).dx / s.doc.size.x; // getSize ignores the FittedBox scale
    final e = s.selected!;
    final cell0 = e.position - e.size / 2;
    Offset at(double c, double r) => tl + Offset(cell0.x + c * 32 + 6, cell0.y + r * 32 + 6) * k;

    await tester.tapAt(at(0, 0));
    await tester.pump();
    List<Object?> tiles() => Props(EditorState.tilemapOf(e)!.props).list('tiles');
    expect(tiles(), everyElement(1)); // 4 × 2 cells all filled
    expect(tiles(), hasLength(8));

    s.setPaint(brush: 0, tool: 'brush');
    await tester.dragFrom(at(0, 0), Offset(40 * k, 0));
    await tester.pump();
    expect(tiles().take(2), everyElement(0));
    s.undo(); // the whole drag is one step
    expect(Props(EditorState.tilemapOf(s.selected!)!.props).list('tiles'), everyElement(1));

    await tester.tap(find.text('DONE'));
    await tester.pump();
    expect(s.paintId, isNull);
  });
}
