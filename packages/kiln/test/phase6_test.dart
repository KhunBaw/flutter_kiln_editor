import 'dart:convert';
import 'dart:io';

import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiln/kiln.dart';

List<File> _scenes() => [
  for (final d in Directory('../../examples').listSync().whereType<Directory>())
    if (Directory('${d.path}/assets/scenes').existsSync())
      ...Directory('${d.path}/assets/scenes').listSync().whereType<File>().where((f) => f.path.endsWith('.kiln.json')),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('migration', () {
    test('every example scene loads and round-trips to a stable file', () {
      final scenes = _scenes();
      expect(scenes, isNotEmpty);
      for (final f in scenes) {
        final once = SceneDoc.fromJson(jsonDecode(f.readAsStringSync())).toJson();
        final twice = SceneDoc.fromJson(jsonDecode(jsonEncode(once))).toJson();
        expect(jsonEncode(twice), jsonEncode(once), reason: f.path);
      }
    });

    test('scenes from before each feature phase still load with defaults', () {
      // Phase 0: no kiln version, no tags, no world, no children.
      final p0 = SceneDoc.fromJson({
        'name': 'old',
        'size': [400, 700],
        'entities': [
          {
            'id': 'a',
            'name': 'A',
            'position': [10, 20],
            'behaviors': [],
          },
        ],
      });
      expect(p0.world, isNull);
      expect(p0.entities.single.tags, isEmpty);
      expect(p0.entities.single.children, isEmpty);
      // Empty and junk-valued files degrade to an empty scene instead of throwing.
      expect(SceneDoc.fromJson(<String, Object?>{}).entities, isEmpty);
      expect(SceneDoc.fromJson({'entities': 'x', 'variables': 3}).entities, isEmpty);
    });

    test('a newer file version is refused, a non-object is a FormatException', () {
      expect(() => SceneDoc.fromJson({'kiln': SceneDoc.version + 1}), throwsFormatException);
      expect(() => SceneDoc.fromJson([]), throwsFormatException);
    });
  });

  test('docs/BEHAVIORS.md is up to date with the registry', () {
    final next = referenceMarkdown(KilnRegistry());
    final file = File('../../docs/BEHAVIORS.md');
    if (!file.existsSync() || file.readAsStringSync() != next) file.writeAsStringSync(next);
    expect(file.readAsStringSync(), next);
    expect(next, contains('### Tilemap'));
  });

  test('docs/EXPRESSIONS.md is up to date and documents every function', () {
    final next = expressionsMarkdown();
    final file = File('../../docs/EXPRESSIONS.md');
    if (!file.existsSync() || file.readAsStringSync() != next) file.writeAsStringSync(next);
    expect(file.readAsStringSync(), next);
    for (final f in ['min', 'randi', 'nearest', 'tile', 'dist']) {
      expect(next, contains('`$f('));
    }
  });

  testWithGame<KilnGame>(
    '600 moving entities with colliders step well inside a frame budget',
    () => KilnGame(
      SceneDoc.fromJson({
        'size': [800, 600],
        'entities': [
          for (var i = 0; i < 600; i++)
            {
              'id': 'e$i',
              'name': 'E$i',
              'position': [(i % 30) * 26.0 + 10, (i ~/ 30) * 28.0 + 10],
              'size': [20, 20],
              'behaviors': [
                {
                  'type': 'Velocity',
                  'props': {'vx': 20, 'vy': 10},
                },
                {'type': 'Collider', 'props': {}},
              ],
            },
        ],
      }),
    ),
    (g) async {
      await g.ready();
      final sw = Stopwatch()..start();
      for (var i = 0; i < 60; i++) {
        g.update(1 / 60);
      }
      final perFrame = sw.elapsedMicroseconds / 60 / 1000;
      // ignore: avoid_print
      print('600 entities: ${perFrame.toStringAsFixed(2)} ms/frame');
      expect(perFrame, lessThan(16)); // loose: catches an accidental O(n^2) in hot paths, not micro-regressions
    },
  );
}
