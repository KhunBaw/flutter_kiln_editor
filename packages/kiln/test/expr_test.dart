import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiln/kiln.dart';

Map<String, Object?> ent(String name, List<Map<String, Object?>> behaviors, {List<num> pos = const [100, 100]}) => {
  'id': name,
  'name': name,
  'position': pos,
  'size': [20, 20],
  'tags': ['t'],
  'behaviors': behaviors,
};

Map<String, Object?> b(String type, [Map<String, Object?> props = const {}]) => {'type': type, 'props': props};
Map<String, Object?> act(String type, [Map<String, Object?> args = const {}]) => {'type': type, ...args};

SceneDoc scene(List<Map<String, Object?>> entities, {Map<String, Object?> prefabs = const {}}) => SceneDoc.fromJson({
  'size': [800, 600],
  'variables': {'score': 3, 'name': 'bob', 'out': 0},
  'prefabs': prefabs,
  'entities': entities,
});

Iterable<KilnEntity> all(KilnGame g) => g.world.descendants().whereType<KilnEntity>();
KilnEntity named(KilnGame g, String n) => all(g).firstWhere((e) => e.node.name == n);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWithGame(
    'evalExpr: precedence, ternary, strings, scope, queries, errors',
    () => KilnGame(
      scene([
        ent('a', []),
        ent('b', [], pos: [130, 140]),
      ]),
    ),
    (g) async {
      final a = named(g, 'a');
      Object? ev(String s) => evalExpr(s, ExprScope(g, a, other: named(g, 'b')));
      expect(ev('1 + 2 * 3'), 7);
      expect(ev('(1 + 2) * 3'), 9);
      expect(ev('-2 ^ 2'), -4);
      expect(ev('2 ^ 3 ^ 1'), 8);
      expect(ev('score > 2 ? "big" : "small"'), 'big');
      expect(ev("'hp ' + score"), 'hp 3');
      expect(ev('score == 3 && !(score != 3)'), true);
      expect(ev('self.x + other.x'), 230);
      expect(ev('other.name'), 'b');
      expect(ev("count('#t')"), 2);
      expect(ev("exists('zzz')"), false);
      expect(ev("dist(self, other)"), 50);
      expect(ev("nearest('b').y"), 140);
      expect(ev('min(score, 1) + max(2, 5) + abs(-1) + floor(1.9)'), 8);
      expect(ev('5 / 0'), 0);
      expect(ev('missing'), null);
      // errors never throw
      expect(ev('1 +'), null);
      expect(ev('nope(1)'), null);
      expect(exprError('1 +'), isNotNull);
      expect(exprError('min(1)'), contains('argument'));
      expect(exprError('self.x * 2'), isNull);
    },
  );

  testWithGame(
    'actions: "=" props, If with other, Condition frame',
    () => KilnGame(
      scene([
        ent('a', [
          b('Timer', {
            'interval': 1,
            'repeat': false,
            'actions': [
              act('SetVariable', {'name': 'out', 'value': '=score * 2'}),
              act('Spawn', {'prefab': 'P', 'x': '=self.x - 100 + 20'}),
              act('If', {
                'expr': '=score > 100',
                'then': [
                  act('SetVariable', {'name': 'branch', 'value': 'then'}),
                ],
                'else': [
                  act('SetVariable', {'name': 'branch', 'value': 'else'}),
                ],
              }),
              act('If', {
                'expr': 'score == 3',
                'then': [
                  act('SetVariable', {'name': 'bare', 'value': '=other.name'}),
                ],
              }),
            ],
          }),
          b('Condition', {
            'expr': 'self.x > 150',
            'check': 'frame',
            'actions': [
              act('SetVariable', {'name': 'fired', 'value': 1}),
            ],
          }),
        ]),
        ent('b', [], pos: [0, 0]),
        ent('P', [b('Prefab')]),
      ]),
    ),
    (g) async {
      final a = named(g, 'a');
      g.update(0.1);
      expect(g.vars['fired'], isNull);
      a.runActions([
        act('Log', {'value': '=score'}),
      ]);
      a.runActions(a.node.behaviors.first.props['actions'] as List<Object?>, other: named(g, 'b'));
      await g.ready();
      expect(g.vars['out'], 6);
      expect(g.vars['branch'], 'else');
      expect(g.vars['bare'], 'b');
      expect(all(g).where((e) => e.node.name == 'P').single.x, 120);
      a.x = 200;
      g.update(0.1);
      expect(g.vars['fired'], 1);
    },
  );
}
