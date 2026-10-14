import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiln/kiln.dart';

const _sceneJson = {
  'kiln': 1,
  'name': 'test',
  'size': [400, 400],
  'variables': {'score': 0},
  'entities': [
    {
      'id': 'b1',
      'name': 'Balloon',
      'position': [200, 200],
      'size': [100, 100],
      'behaviors': [
        {
          'type': 'Shape',
          'props': {'shape': 'oval', 'color': '#FF0000'},
        },
        {
          'type': 'OnTap',
          'props': {
            'actions': [
              {'type': 'AddVariable', 'name': 'score', 'value': 1},
              {'type': 'Destroy'},
            ],
          },
        },
      ],
    },
    {
      'id': 'hud',
      'position': [200, 30],
      'size': [200, 40],
      'behaviors': [
        {
          'type': 'Text',
          'props': {'text': 'Score: {score}'},
        },
        {'type': 'NotARealBehavior'},
      ],
    },
  ],
};

void main() {
  group('SceneDoc', () {
    test('round-trips JSON', () {
      final doc = SceneDoc.fromJson(_sceneJson);
      expect(SceneDoc.fromJson(doc.toJson()).toJson(), doc.toJson());
      expect(doc.entities.first.behaviors.last.props['actions'], hasLength(2));
    });

    test('tolerates bad fields, rejects non-objects and newer versions', () {
      final doc = SceneDoc.fromJson({
        'size': 'oops',
        'entities': [
          {
            'position': [1],
            'behaviors': 'x',
          },
          42,
        ],
      });
      expect(doc.size, Vector2(400, 700));
      expect(doc.entities, hasLength(2));
      expect(doc.entities.first.position, Vector2.zero());
      expect(() => SceneDoc.fromJson([]), throwsFormatException);
      expect(() => SceneDoc.fromJson({'kiln': 99}), throwsFormatException);
    });

    test('Props falls back on wrong types', () {
      const p = Props({'n': 'x', 'c': '#zz', 's': 3});
      expect(p.number('n'), 0);
      expect(p.string('s'), '');
      expect(p.color('c'), const Color(0xFFFF00FF));
      expect(const Props({'c': '#112233'}).color('c'), const Color(0xFF112233));
    });
  });

  testWidgets('tap adds score, destroys entity, updates text', (tester) async {
    final game = KilnGame(SceneDoc.fromJson(_sceneJson));
    await tester.binding.setSurfaceSize(const Size(400, 400));
    await tester.pumpWidget(GameWidget(game: game));
    await tester.pump();
    await tester.pump();

    final texts = game.descendants().whereType<TextComponent>();
    expect(texts.single.text, 'Score: 0');
    expect(game.world.children.whereType<KilnEntity>(), hasLength(2));

    await tester.tapAt(const Offset(200, 200));
    await tester.pump();
    await tester.pump();

    expect(game.vars['score'], 1);
    expect(texts.single.text, 'Score: 1');
    expect(game.world.children.whereType<KilnEntity>(), hasLength(1));

    // Tapping empty space must not change anything.
    await tester.tapAt(const Offset(200, 200));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(game.vars['score'], 1);
  });
}
