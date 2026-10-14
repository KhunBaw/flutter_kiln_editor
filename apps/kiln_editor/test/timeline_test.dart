import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiln/kiln.dart';
import 'package:kiln_editor/editor_state.dart';
import 'package:kiln_editor/main.dart';

EditorState stateOf(WidgetTester t) => (t.state<State>(find.byType(EditorPage)) as dynamic).s as EditorState;

Future<EditorState> boot(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1500, 950);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const KilnEditorApp());
  return stateOf(tester);
}

void main() {
  test('key editing: toggle, write at playhead, move, ease, delete — one undo each', () {
    final s = EditorState();
    s.addEntity(at: Vector2(100, 100));
    final e = s.selected!;
    s.addAnimator(e);
    expect(EditorState.animatorOf(e), isNotNull);

    // Diamond at t=0 records the current x; a second one at 1s records a new value.
    s.toggleKey(e, 'x');
    expect(s.keyedAtPlayhead(e, 'x'), isTrue);
    s.playhead.value = 1;
    s.setProp(e, 'x', 300); // animated, so this writes a key rather than the stored position
    expect(e.position.x, 100);
    expect(s.posed(e, 'x'), 300);
    s.playhead.value = 0.5;
    expect(s.posed(e, 'x'), 200);

    s.edit((_) => EditorState.animatorOf(e)!.props['duration'] = 2.0);
    final i = s.moveKey(e, 'x', 1, 2);
    expect(i, 1);
    s.playhead.value = 1;
    expect(s.posed(e, 'x'), 200); // 100 → 300 over 0..2s
    s.editKey(e, 'x', 0, ease: 'easeIn');
    expect(s.posed(e, 'x'), lessThan(200));

    s.undo(); // the doc is replaced on undo, so re-read the entity
    var f = s.selected!;
    expect(s.posed(f, 'x'), 200);
    s.deleteKey(f, 'x', 1);
    f = s.selected!;
    expect(s.isAnimated(f, 'x'), isTrue); // one key left
    s.deleteKey(f, 'x', 0);
    f = s.selected!;
    expect(s.isAnimated(f, 'x'), isFalse);
    expect(s.valueOf(f, 'x'), 100);
  });

  test('stored fields stay stored when nothing animates them', () {
    final s = EditorState();
    s.addEntity(at: Vector2(10, 10));
    final e = s.selected!;
    s.setProp(e, 'x', 55);
    expect(e.position.x, 55);
    s.setProp(e, 'opacity', 0.5); // no Animator: ignored
    expect(EditorState.animatorOf(e), isNull);
  });

  testWidgets('timeline: create animation, add track, scrub poses the scene', (tester) async {
    final s = await boot(tester);
    s.addEntity(at: Vector2(100, 100));
    await tester.pump();
    expect(find.text('Preview (Space)'), findsNothing);
    await tester.tap(find.text('Create animation'));
    await tester.pump();
    final e = s.selected!;
    expect(EditorState.animatorOf(e), isNotNull);

    s.addTrack(e, 'x');
    s.playhead.value = 1;
    s.setProp(e, 'x', 300);
    await tester.pump();
    expect(find.text('Position X'), findsWidgets);

    s.playhead.value = 0.5;
    await tester.pump();
    final game = tester.widget<GameWidget<KilnGame>>(find.byWidgetPredicate((w) => w is GameWidget<KilnGame>)).game!;
    final ent = game.world.descendants().whereType<KilnEntity>().first;
    expect(ent.position.x, closeTo(200, 1e-6));
  });
}
