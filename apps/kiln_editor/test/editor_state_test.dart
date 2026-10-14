import 'dart:convert';
import 'dart:io';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiln/kiln.dart';
import 'package:kiln_editor/editor_state.dart';
import 'package:kiln_editor/main.dart';
import 'package:kiln_editor/panels.dart';

void main() {
  test('undo/redo with merged keystrokes', () {
    final s = EditorState()..addEntity();
    final e = s.selected!;
    s.edit((_) => e.name = 'B', mergeKey: 'n');
    s.edit((_) => s.selected!.name = 'Ba', mergeKey: 'n');
    expect(s.selected!.name, 'Ba');

    s.undo(); // one step for both keystrokes
    expect(s.selected!.name, startsWith('Entity'));
    s.undo(); // undo add
    expect(s.doc.entities, isEmpty);
    expect(s.selectedId, isNull);
    expect(s.canUndo, isFalse);

    s.redo();
    s.redo();
    expect(s.doc.entities.single.name, 'Ba');
    expect(s.canRedo, isFalse);
  });

  test('remove nested entity', () {
    final child = EntityNode(id: 'c');
    final s = EditorState(
      SceneDoc(
        entities: [
          EntityNode(id: 'p', children: [child]),
        ],
      ),
    );
    s.removeEntity('c');
    expect(s.doc.entities.single.children, isEmpty);
  });

  test('save/load round trip; bad file keeps current scene', () async {
    final dir = await Directory.systemTemp.createTemp('kiln');
    final s = EditorState()..addEntity();
    await s.save('${dir.path}/a.kiln.json');
    expect(s.dirty, isFalse);

    final t = EditorState();
    await t.load('${dir.path}/a.kiln.json');
    expect(t.doc.entities.single.behaviors.single.type, 'Shape');

    await File('${dir.path}/bad.json').writeAsString('[1]');
    await expectLater(t.load('${dir.path}/bad.json'), throwsFormatException);
    expect(t.doc.entities, hasLength(1));
    await dir.delete(recursive: true);
  });

  test('project: schema adds custom types, import copies without clobbering', () async {
    final dir = await Directory.systemTemp.createTemp('kiln_proj');
    final app = KilnRegistry()
      ..register(BehaviorDef('Spin', const [PropDef('speed', PropKind.number, 1)], (e, p) => null));
    await File('${dir.path}/kiln.schema.json').writeAsString(jsonEncode(app.schemaJson()));

    final s = EditorState();
    expect(await s.openProject(dir.path), ['Spin']);
    expect(s.registry.behaviors['Spin']!.props.single.key, 'speed');

    final src = File('${dir.path}/pop.wav')..writeAsBytesSync([1, 2, 3]);
    expect(await s.importAsset(src.path, 'audio'), 'pop.wav');
    expect(await s.importAsset(src.path, 'audio'), 'pop.wav'); // same bytes: reuse
    src.writeAsBytesSync([9]);
    expect(await s.importAsset(src.path, 'audio'), 'pop-2.wav'); // different file, same name: keep both
    expect(File('${dir.path}/assets/audio/pop.wav').readAsBytesSync(), [1, 2, 3]);

    await expectLater(EditorState().importAsset(src.path, 'audio'), throwsStateError);
    await dir.delete(recursive: true);
  });

  testWidgets('editor: add entity, edit via inspector, undo', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const KilnEditorApp());
    await tester.tap(find.byTooltip('Add entity'));
    await tester.pump();
    expect(find.text('SHAPE'), findsWidgets);

    await tester.enterText(find.widgetWithText(Field, 'X'), '50');
    await tester.pump();
    final state = tester.state<State>(find.byType(EditorPage)) as dynamic;
    expect((state.s as EditorState).selected!.position.x, 50);

    await tester.tap(find.byTooltip('Undo (⌘Z)'));
    await tester.pump();
    expect((state.s as EditorState).selected!.position.x, 200);
    expect(find.widgetWithText(Field, '200'), findsOneWidget);

    // Drag in scene view: entity sits at scene center = GameWidget center.
    final es = state.s as EditorState;
    es.select(null);
    await tester.drag(find.byWidgetPredicate((w) => w is GameWidget), const Offset(80, 0));
    await tester.pump();
    expect(es.selected!.position.x, greaterThan(200));
    expect(es.selected!.position.x % 1, 0);
    es.undo(); // whole drag = one step
    expect(es.selected!.position.x, 200);

    // Play swaps the preview for a live game; Stop brings the editor view back.
    await tester.tap(find.byTooltip('Play (⌘P)'));
    await tester.pump();
    expect(find.byType(SceneView), findsNothing);
    await tester.tap(find.byTooltip('Stop (⌘P)'));
    await tester.pump();
    expect(find.byType(SceneView), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
  });
}
