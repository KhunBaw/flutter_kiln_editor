import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiln/kiln.dart';
import 'package:kiln/src/builtins.dart' show Body;
import 'package:kiln/src/tilemap.dart';

// 8×6 cells of 32px: a walled room with a divider in columns 4, rows 1-2 (open below it).
const _rows = [
  '1 1 1 1 1 1 1 1',
  '1 0 0 0 1 0 0 1',
  '1 0 0 0 1 0 0 1',
  '1 0 0 0 0 0 0 1',
  '1 0 0 0 0 0 0 1',
  '1 1 1 1 1 1 1 1',
];
final _tiles = [for (final r in _rows) ...r.split(' ').map(int.parse)];

Map<String, Object?> ent(
  String name,
  List<Map<String, Object?>> behaviors, {
  List<num> pos = const [100, 100],
  List<num> size = const [20, 20],
  List<String> tags = const [],
}) => {'id': name, 'name': name, 'position': pos, 'size': size, 'tags': tags, 'behaviors': behaviors};

Map<String, Object?> b(String type, [Map<String, Object?> props = const {}]) => {'type': type, 'props': props};
Map<String, Object?> act(String type, [Map<String, Object?> args = const {}]) => {'type': type, ...args};

Map<String, Object?> room() => ent(
  'map',
  [
    b('Tilemap', {'tile': 32, 'cols': 8, 'tiles': _tiles, 'solid': '1'}),
  ],
  pos: [128, 96],
  size: [256, 192],
);

/// Centre of cell (c, r).
List<num> at(int c, int r) => [c * 32 + 16, r * 32 + 16];

SceneDoc scene(List<Map<String, Object?>> entities) => SceneDoc.fromJson({
  'size': [800, 600],
  'variables': {'score': 0, 'hurts': 0},
  'entities': entities,
});

Iterable<KilnEntity> all(KilnGame g) => g.world.descendants().whereType<KilnEntity>();
KilnEntity named(KilnGame g, String n) => all(g).firstWhere((e) => e.node.name == n);

KeyEvent down(LogicalKeyboardKey k) =>
    KeyDownEvent(physicalKey: PhysicalKeyboardKey.space, logicalKey: k, timeStamp: Duration.zero);

class MemoryStorage implements KilnStorage {
  final data = <String, Map<String, Object?>>{};

  @override
  Future<Map<String, Object?>?> read(String slot) async => data[slot];

  @override
  Future<void> write(String slot, Map<String, Object?> d) async => data[slot] = d;
}

Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWithGame(
    'Tilemap: a Body lands on solid tiles and is walled in by them',
    () => KilnGame(
      scene([
        room(),
        ent('p', [b('Body')], pos: at(2, 1)),
      ]),
    ),
    (g) async {
      final p = named(g, 'p');
      for (var i = 0; i < 60; i++) {
        g.update(1 / 30);
      }
      // Floor row 5 starts at y=160.
      expect(p.y + 10, closeTo(160, 1e-3));
      expect(g.tilemaps.single.rows, 6);
      p.children.whereType<Body>().single.v.x = -800;
      for (var i = 0; i < 20; i++) {
        g.update(1 / 30);
      }
      expect(p.x - 10, closeTo(32, 1e-3)); // stopped by the left wall column
    },
  );

  testWithGame('findPath routes around walls and gives up when sealed', () => KilnGame(scene([room()])), (g) async {
    final m = g.tilemaps.single;
    final path = findPath(m, (2, 1), (6, 1))!;
    expect(path.first, (2, 1));
    expect(path.last, (6, 1));
    expect(path.length, 9); // down 2, across 4, up 2, plus the start
    expect(path.any((c) => m.blocked(c.$1, c.$2)), isFalse);
    expect(findPath(m, (2, 1), (4, 1)), isNull); // goal inside a wall
    expect(findPath(m, (2, 1), (-1, 1)), isNull); // off the map
  });

  testWithGame(
    'Follow with pathfind walks around the divider to the target',
    () => KilnGame(
      scene([
        room(),
        ent('Hero', [], pos: at(6, 1)),
        ent('bat', [
          b('Follow', {'target': 'Hero', 'speed': 100, 'stop': 4, 'pathfind': true}),
          b('Velocity'),
        ], pos: at(2, 1)),
      ]),
    ),
    (g) async {
      final bat = named(g, 'bat');
      for (var i = 0; i < 300; i++) {
        g.update(1 / 30);
        // Never inside a solid cell: it detours through the open bottom rows.
        final (c, r) = g.tilemaps.single.cellAt(bat.absoluteCenter);
        expect(g.tilemaps.single.blocked(c, r), isFalse, reason: 'frame $i at ${bat.position}');
      }
      expect(bat.absoluteCenter.distanceTo(named(g, 'Hero').absoluteCenter), lessThan(8));
    },
  );

  testWithGame(
    'GridMove: steps one cell, pushes a box, refuses blocked pushes and walls',
    () => KilnGame(
      scene([
        room(),
        ent(
          'P',
          [
            b('GridMove', {
              'cell': 32,
              'time': 0,
              'push': '#box',
              'onStep': [
                act('AddVariable', {'name': 'score'}),
              ],
            }),
          ],
          pos: at(1, 3),
          size: [32, 32],
        ),
        ent('B', [], pos: at(2, 3), size: [32, 32], tags: ['box']),
        ent('B2', [], pos: at(3, 3), size: [32, 32], tags: ['box']),
      ]),
    ),
    (g) async {
      final p = named(g, 'P');
      void press(LogicalKeyboardKey k) {
        g.onKeyEvent(down(k), {k});
        g.update(0.016);
      }

      press(LogicalKeyboardKey.arrowRight); // B would hit B2: refused
      expect(p.position, Vector2(at(1, 3)[0].toDouble(), at(1, 3)[1].toDouble()));
      expect(g.vars['score'], 0);

      press(LogicalKeyboardKey.arrowUp);
      expect(p.y, at(1, 2)[1]);
      expect(g.vars['score'], 1);

      press(LogicalKeyboardKey.arrowLeft); // wall at column 0
      expect(p.x, at(1, 2)[0]);

      press(LogicalKeyboardKey.arrowDown);
      press(LogicalKeyboardKey.arrowDown);
      press(LogicalKeyboardKey.arrowDown); // row 5 is wall
      expect(p.y, at(1, 4)[1]);

      press(LogicalKeyboardKey.arrowRight); // free cell, no box
      expect(p.x, at(2, 4)[0]);
      press(LogicalKeyboardKey.arrowUp); // under B: pushes it up into the free cell
      expect(p.y, at(2, 3)[1]);
      expect(named(g, 'B').y, at(2, 2)[1]);
    },
  );

  testWithGame(
    'GridMove pushes a box and animates both over `time`',
    () => KilnGame(
      scene([
        room(),
        ent(
          'P',
          [
            b('GridMove', {'cell': 32, 'time': 0.2, 'push': '#box'}),
          ],
          pos: at(1, 3),
          size: [32, 32],
        ),
        ent('B', [], pos: at(2, 3), size: [32, 32], tags: ['box']),
      ]),
    ),
    (g) async {
      final p = named(g, 'P'), box = named(g, 'B');
      g.onKeyEvent(down(LogicalKeyboardKey.arrowRight), {LogicalKeyboardKey.arrowRight});
      g.update(0); // starts the step
      g.update(0.1);
      expect(p.x, closeTo(at(1, 3)[0] + 16, 1e-3)); // halfway
      g.onKeyEvent(down(LogicalKeyboardKey.arrowRight), {}); // released
      g.update(0.15);
      g.update(0.01);
      expect(p.x, at(2, 3)[0]);
      expect(box.x, closeTo(at(3, 3)[0], 1e-3));
    },
  );

  testWithGame(
    'OnCollide exit runs when the contact ends',
    () => KilnGame(
      scene([
        ent('a', [
          b('Collider'),
          b('OnCollide', {
            'with': 'b',
            'actions': [
              act('AddVariable', {'name': 'score'}),
            ],
            'exit': [
              act('AddVariable', {'name': 'hurts'}),
            ],
          }),
        ]),
        ent('b', [b('Collider')]),
      ]),
    ),
    (g) async {
      g.update(0.016);
      expect(g.vars['score'], 1);
      expect(g.vars['hurts'], 0);
      named(g, 'b').x = 500;
      g.update(0.016);
      g.update(0.016);
      expect(g.vars['hurts'], 1);
    },
  );

  testWithGame(
    'Dialogue: lines advance, a choice stores its number and runs the actions',
    () => KilnGame(
      scene([
        ent(
          'd',
          [
            b('Dialogue', {
              'lines': 'Hi {score}|Pick one',
              'choices': 'Yes|No',
              'variable': 'answer',
              'actions': [
                act('AddVariable', {'name': 'hurts'}),
              ],
            }),
          ],
          size: [300, 100],
        ),
      ]),
    ),
    (g) async {
      await g.ready();
      final d = named(g, 'd');
      expect(d.children.whereType<TextBoxComponent>().single.text, 'Hi 0');
      g.onKeyEvent(down(LogicalKeyboardKey.digit1), {}); // no choices on line 1
      expect(g.vars['answer'], isNull);
      g.onKeyEvent(down(LogicalKeyboardKey.enter), {});
      await g.ready();
      expect(d.children.whereType<TextBoxComponent>().single.text, 'Pick one');
      g.onKeyEvent(down(LogicalKeyboardKey.enter), {}); // choices pending: Enter does nothing
      expect(d.isVisible, isTrue);
      g.onKeyEvent(down(LogicalKeyboardKey.digit2), {});
      expect(g.vars['answer'], 2);
      expect(g.vars['hurts'], 1);
      expect(d.isVisible, isFalse);
    },
  );

  testWithGame(
    'Dialogue with `open` stays hidden until its event',
    () => KilnGame(
      scene([
        ent(
          'd',
          [
            b('Dialogue', {'lines': 'Hello', 'open': 'talk'}),
          ],
          size: [300, 100],
        ),
      ]),
    ),
    (g) async {
      await g.ready();
      final d = named(g, 'd');
      expect(d.isVisible, isFalse);
      g.emit('talk');
      expect(d.isVisible, isTrue);
      g.onKeyEvent(down(LogicalKeyboardKey.space), {});
      expect(d.isVisible, isFalse);
    },
  );

  final store = MemoryStorage();
  final events = <String>[];
  testWithGame(
    'SaveGame / LoadGame round trip through the storage hook',
    () => KilnGame(scene([ent('e', [])]), storage: store, onEmit: (name, value) => events.add('$name:$value')),
    (g) async {
      final e = named(g, 'e');
      g.vars['score'] = 7;
      g.registry.runActions(e, [
        act('SaveGame', {'slot': 's1', 'names': 'score'}),
      ]);
      await pump();
      expect(store.data['s1'], {
        'variables': {'score': 7},
      });
      g.vars['score'] = 0;
      g.vars['hurts'] = 3;
      g.registry.runActions(e, [
        act('LoadGame', {'slot': 's1'}),
        act('LoadGame', {'slot': 'nope'}),
      ]);
      await pump();
      await pump();
      expect(g.vars['score'], 7);
      expect(g.vars['hurts'], 3); // not in the save
      expect(events, containsAll(['saved:s1', 'loaded:s1', 'loadfailed:nope']));
    },
  );
}
