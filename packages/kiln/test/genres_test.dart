// Each genre is built from scene data alone (no Dart behaviors) and played by a bot.
import 'package:flame/components.dart' show Vector2;
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiln/kiln.dart';

Map<String, Object?> ent(
  String name,
  List<Map<String, Object?>> behaviors, {
  List<num> pos = const [100, 100],
  List<num> size = const [20, 20],
  List<String> tags = const [],
  Map<String, Object?> vars = const {},
}) => {
  'id': name,
  'name': name,
  'position': pos,
  'size': size,
  'tags': tags,
  'behaviors': behaviors,
  if (vars.isNotEmpty) 'variables': vars,
};

Map<String, Object?> b(String type, [Map<String, Object?> props = const {}]) => {'type': type, 'props': props};
Map<String, Object?> act(String type, [Map<String, Object?> args = const {}]) => {'type': type, ...args};

SceneDoc scene(Map<String, Object?> variables, List<Map<String, Object?>> entities) => SceneDoc.fromJson({
  'size': [800, 600],
  'variables': variables,
  'entities': entities,
});

Iterable<KilnEntity> all(KilnGame g) => g.world.descendants().whereType<KilnEntity>();
KilnEntity named(KilnGame g, String n) => all(g).firstWhere((e) => e.node.name == n);
void tap(KilnEntity e) {
  for (final h in [...e.tapHandlers]) {
    h();
  }
}

class MemoryStorage implements KilnStorage {
  final data = <String, Map<String, Object?>>{};
  @override
  Future<Map<String, Object?>?> read(String slot) async => data[slot];
  @override
  Future<void> write(String slot, Map<String, Object?> d) async => data[slot] = d;
}

Future<void> settle() async {
  for (var i = 0; i < 3; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWithGame(
    'idle: price formula grows with owned, a Timer pays out, an unaffordable buy does nothing',
    () => KilnGame(
      scene(
        {'coins': 0, 'owned': 0},
        [
          ent('cookie', [
            b('OnTap', {
              'actions': [
                act('AddVariable', {'name': 'coins', 'value': '=1 + owned'}),
              ],
            }),
          ]),
          ent('shop', [
            b('OnTap', {
              'actions': [
                act('If', {
                  'expr': '=coins >= floor(10 * 1.15 ^ owned)',
                  'then': [
                    act('AddVariable', {'name': 'coins', 'value': '=-floor(10 * 1.15 ^ owned)'}),
                    act('AddVariable', {'name': 'owned', 'value': 1}),
                  ],
                }),
              ],
            }),
          ]),
          ent('farm', [
            b('Timer', {
              'interval': 1,
              'actions': [
                act('AddVariable', {'name': 'coins', 'value': '=owned'}),
              ],
            }),
          ]),
        ],
      ),
    ),
    (g) async {
      final cookie = named(g, 'cookie'), shop = named(g, 'shop');
      tap(shop);
      expect(g.vars['owned'], 0); // 0 coins
      for (var i = 0; i < 10; i++) {
        tap(cookie);
      }
      tap(shop); // price 10
      expect([g.vars['coins'], g.vars['owned']], [0, 1]);
      for (var i = 0; i < 5; i++) {
        tap(cookie); // 2 each
      }
      tap(shop); // price floor(11.5) = 11 > 10
      expect([g.vars['coins'], g.vars['owned']], [10, 1]);
      tap(cookie);
      tap(shop);
      expect([g.vars['coins'], g.vars['owned']], [1, 2]); // 12 - floor(11.5)
      g.update(1.01);
      g.update(1.01);
      expect(g.vars['coins'], 5); // 1 + 2 owned x 2 ticks
    },
  );

  Map<String, Object?> board() => ent(
    'board',
    [
      b('Tilemap', {
        'tile': 32,
        'cols': 4,
        'solid': '',
        'tiles': [1, 1, 2, 3, 2, 3, 3, 3, 1, 2, 1, 2, 3, 1, 2, 1],
      }),
      b('OnPointer', {
        'down': [
          act('SetTile', {
            'c': '=cellX(pointer.x)',
            'r': '=cellY(pointer.y)',
            'tile': '=tile(cellX(pointer.x), cellY(pointer.y)) % 3 + 1',
          }),
          act('Emit', {'event': 'check'}),
        ],
      }),
      b('OnEvent', {
        'event': 'check',
        'actions': [
          // rows: runs of three
          act('Repeat', {
            'count': 4,
            'var': 'r',
            'actions': [
              act('Repeat', {
                'count': 2,
                'var': 'c',
                'actions': [
                  act('If', {
                    'expr': '=tile(c, r) > 0 && tile(c, r) == tile(c + 1, r) && tile(c, r) == tile(c + 2, r)',
                    'then': [
                      act('FillTiles', {'c': '=c', 'r': '=r', 'w': 3, 'h': 1, 'tile': 0}),
                      act('AddVariable', {'name': 'score', 'value': 3}),
                    ],
                  }),
                ],
              }),
            ],
          }),
        ],
      }),
      b('OnEvent', {
        'event': 'gravity',
        'actions': [
          act('Repeat', {
            'count': 3,
            'var': 'pass',
            'actions': [
              act('Repeat', {
                'count': 3,
                'var': 'r',
                'actions': [
                  act('Repeat', {
                    'count': 4,
                    'var': 'c',
                    'actions': [
                      act('If', {
                        'expr': '=tile(c, r) > 0 && tile(c, r + 1) == 0',
                        'then': [
                          act('SetTile', {'c': '=c', 'r': '=r + 1', 'tile': '=tile(c, r)'}),
                          act('SetTile', {'c': '=c', 'r': '=r', 'tile': 0}),
                        ],
                      }),
                    ],
                  }),
                ],
              }),
            ],
          }),
        ],
      }),
    ],
    pos: [64, 64],
    size: [128, 128],
  );

  testWithGame(
    'puzzle: match-3 clears runs, gravity refills, a click cycles a tile',
    () => KilnGame(scene({'score': 0}, [board()])),
    (g) async {
      Object? tileAt(int c, int r) => evalExpr('tile($c, $r)', ExprScope(g, named(g, 'board')));
      g.emit('check');
      expect(g.vars['score'], 3);
      expect([tileAt(0, 1), tileAt(1, 1), tileAt(2, 1), tileAt(3, 1)], [2, 0, 0, 0]);
      g.emit('gravity');
      expect([tileAt(1, 1), tileAt(1, 0), tileAt(3, 1), tileAt(3, 0)], [1, 0, 3, 0]);
      g.emit('check'); // nothing left to clear
      expect(g.vars['score'], 3);
    },
  );

  testWithGame(
    'puzzle: clicking cell (0,1) turns 2 into 3 and completes a row',
    () => KilnGame(scene({'score': 0}, [board()])),
    (g) async {
      g.pointerEvent('down', Vector2(16, 48)); // cell (0,1)
      expect(g.vars['score'], 3);
      expect(evalExpr('tile(0, 1) * 10 + tile(3, 1)', ExprScope(g, named(g, 'board'))), 3);
    },
  );

  testWithGame(
    'strategy: waves come from a list, a tower picks the nearest enemy, bolts kill them',
    () => KilnGame(
      scene(
        {
          'score': 0,
          'waves': <Object?>[2, 3],
        },
        [
          ent(
            'tower',
            [
              b('Timer', {
                'interval': 0.2,
                'actions': [
                  act('If', {
                    'expr': "=count('#enemy') > 0 && dist(self, nearest('#enemy')) < 250",
                    'then': [
                      act('Shoot', {'prefab': 'Bolt', 'aim': 'target', 'at': '#enemy', 'speed': 600, 'cooldown': 0}),
                    ],
                  }),
                ],
              }),
            ],
            pos: [100, 100],
          ),
          ent(
            'director',
            [
              b('OnEvent', {
                'event': 'wave',
                'actions': [
                  act('If', {
                    'expr': '=len(waves) > 0',
                    'then': [
                      act('Repeat', {
                        'count': '=waves[0]',
                        'var': 'k',
                        'actions': [
                          act('Spawn', {'prefab': 'Enemy', 'x': '=k * 30', 'y': 0}),
                        ],
                      }),
                      act('ListRemove', {'name': 'waves', 'index': 0}),
                    ],
                  }),
                ],
              }),
            ],
            pos: [160, 100],
          ),
          ent(
            'Enemy',
            [
              b('Prefab'),
              b('Collider'),
              b('Health', {
                'hp': 2,
                'death': [
                  act('AddVariable', {'name': 'score', 'value': 1}),
                  act('Destroy'),
                ],
              }),
            ],
            tags: ['enemy'],
            pos: [0, 0],
          ),
          ent(
            'Bolt',
            [
              b('Prefab'),
              b('Collider'),
              b('OnCollide', {
                'with': '#enemy',
                'actions': [
                  act('Damage', {'target': 'other', 'amount': 1}),
                  act('Destroy'),
                ],
              }),
            ],
            size: [10, 10],
            pos: [0, 0],
          ),
        ],
      ),
    ),
    (g) async {
      int enemies() =>
          all(g)
              .where((e) => e.node.tags.contains('enemy') && e.node.name == 'Enemy' && e.node.id.contains('#'))
              .length;
      Future<void> run(double seconds) async {
        for (var t = 0.0; t < seconds; t += 0.05) {
          g.update(0.05);
          await g.ready();
        }
      }

      g.emit('wave');
      await g.ready();
      expect(enemies(), 2);
      expect(g.vars.list('waves'), [3]);
      await run(4);
      expect(enemies(), 0);
      expect(g.vars['score'], 2);

      g.emit('wave');
      await g.ready();
      expect(enemies(), 3);
      await run(6);
      expect(g.vars['score'], 5);
      g.emit('wave'); // wave table is empty
      await g.ready();
      expect(enemies(), 0);
    },
  );

  testWithGame(
    'rpg: shop buys from a list of maps, inventory ForEach, save and load restore lists',
    () => KilnGame(
      scene(
        {
          'gold': 50,
          'pick': 0,
          'inventory': <Object?>[],
          'items': <Object?>[
            {'name': 'Potion', 'price': 20},
            {'name': 'Sword', 'price': 40},
          ],
        },
        [
          ent('shop', [
            b('OnEvent', {
              'event': 'buy',
              'store': 'pick',
              'actions': [
                act('If', {
                  'expr': '=gold >= items[pick].price',
                  'then': [
                    act('AddVariable', {'name': 'gold', 'value': '=-items[pick].price'}),
                    act('ListAdd', {'name': 'inventory', 'value': '=items[pick].name'}),
                  ],
                  'else': [
                    act('Emit', {'event': 'poor'}),
                  ],
                }),
              ],
            }),
            b('OnEvent', {
              'event': 'tally',
              'actions': [
                act('SetVariable', {'name': 'potions', 'value': 0}),
                act('ForEach', {
                  'list': 'inventory',
                  'var': 'it',
                  'actions': [
                    act('If', {
                      'expr': "=it == 'Potion'",
                      'then': [
                        act('AddVariable', {'name': 'potions', 'value': 1}),
                      ],
                    }),
                  ],
                }),
              ],
            }),
          ]),
        ],
      ),
      storage: store,
      onEmit: (name, value) => events.add(name),
    ),
    (g) async {
      g.emit('buy', value: 0.0);
      g.emit('buy', value: 1.0); // 30 gold left, sword costs 40
      g.emit('buy', value: 0.0);
      g.emit('tally');
      expect(g.vars['gold'], 10);
      expect(g.vars.list('inventory'), ['Potion', 'Potion']);
      expect(g.vars['potions'], 2);
      expect(events.where((e) => e == 'poor').length, 1);

      g.registry.runActions(named(g, 'shop'), [
        act('SaveGame', {'slot': 'rpg', 'names': 'gold,inventory'}),
      ]);
      await settle();
      g.vars['gold'] = 0;
      g.vars['inventory'] = <Object?>[];
      g.registry.runActions(named(g, 'shop'), [
        act('LoadGame', {'slot': 'rpg'}),
      ]);
      await settle();
      expect(g.vars['gold'], 10);
      expect(g.vars.list('inventory'), ['Potion', 'Potion']);
    },
  );

  testWithGame(
    'action: a boss StateMachine with its own hp attacks on a cycle and dies at 0 hp',
    () => KilnGame(
      scene(
        {'playerHp': 10},
        [
          ent(
            'boss',
            [
              b('StateMachine', {
                'initial': 'idle',
                'states': [
                  {'name': 'idle'},
                  {
                    'name': 'attack',
                    'enter': [
                      act('AddVariable', {'name': 'playerHp', 'value': -2}),
                    ],
                  },
                  {
                    'name': 'dead',
                    'enter': [
                      act('Emit', {'event': 'bossdead'}),
                      act('Destroy'),
                    ],
                  },
                ],
                'transitions': [
                  {'from': '*', 'to': 'dead', 'when': '=self.hp <= 0'},
                  {'from': 'idle', 'to': 'attack', 'when': '=self.stateTime >= 1'},
                  {'from': 'attack', 'to': 'idle', 'when': '=self.stateTime >= 0.5'},
                ],
              }),
              b('OnEvent', {
                'event': 'hit',
                'actions': [
                  act('AddVariable', {'name': 'hp', 'value': -1, 'scope': 'self'}),
                ],
              }),
            ],
            vars: {'hp': 3},
          ),
        ],
      ),
      onEmit: (name, value) => events.add(name),
    ),
    (g) async {
      await g.ready();
      final boss = named(g, 'boss');
      void steps(int n) {
        for (var i = 0; i < n; i++) {
          g.update(0.25);
        }
      }

      steps(4);
      expect([boss.vars['state'], g.vars['playerHp']], ['attack', 8]);
      steps(2);
      expect(boss.vars['state'], 'idle');
      steps(4);
      expect([boss.vars['state'], g.vars['playerHp']], ['attack', 6]);

      for (var i = 0; i < 3; i++) {
        g.emit('hit');
      }
      expect(boss.vars['hp'], 0);
      steps(1);
      await g.ready();
      expect(events, contains('bossdead'));
      expect(all(g).where((e) => e.node.name == 'boss'), isEmpty);
      expect(g.vars['playerHp'], 6);
    },
  );
}

final store = MemoryStorage();
final events = <String>[];
