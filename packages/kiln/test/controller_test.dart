import 'dart:convert';
import 'dart:io';

import 'package:flame/game.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiln/kiln.dart';
import 'package:kiln/schema_io.dart';
import 'package:kiln/types_gen.dart';

Map<String, Object?> sceneJson(String name, Map<String, Object?> vars, List<Map<String, Object?>> behaviors) => {
  'kiln': 1,
  'name': name,
  'size': [100, 100],
  'variables': vars,
  'entities': [
    {'id': 'c', 'name': 'ctl', 'behaviors': behaviors},
  ],
};

Map<String, Object?> b(String type, [Map<String, Object?> props = const {}]) => {'type': type, 'props': props};

Map<String, Object?> act(String type, [Map<String, Object?> args = const {}]) => {'type': type, ...args};

Map<String, Object?> once(List<Map<String, Object?>> actions) =>
    b('Timer', {'interval': 0.01, 'repeat': false, 'actions': actions});

/// Serves scenes from memory as Flutter assets.
void mockAssets(WidgetTester t, Map<String, Map<String, Object?>> scenes) {
  t.binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (msg) async {
    final key = utf8.decode(msg!.buffer.asUint8List());
    final s = scenes[key];
    return s == null ? null : ByteData.sublistView(utf8.encode(jsonEncode(s)));
  });
}

Future<void> settle(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('GameVariables: typed reads, seed keeps existing, reset to defaults', () {
    final v = GameVariables({'n': 2, 's': 'x', 'b': true});
    expect((v.number('n'), v.number('s'), v.string('n'), v.flag('b'), v.flag('n')), (2.0, 0.0, '2', true, false));
    v.seed({'n': 9, 'new': 1});
    expect((v['n'], v['new']), (2, 1));
    v['n'] = 5;
    v['s'] = 'y';
    v.reset({'n': 0, 's': ''}, ['n']);
    expect((v['n'], v['s']), (0, 'y'));
    v.reset({'n': 1, 's': 'z'});
    expect((v['n'], v['s']), (1, 'z'));
  });

  final events = <String>[];
  testWithGame(
    'Emit sends a templated value out; app emit stores into OnEvent.store; ResetVariables',
    () => KilnGame(
      SceneDoc.fromJson(
        sceneJson(
          'a',
          {'score': 7, 'lives': 3},
          [
            once([
              act('Emit', {'event': 'done', 'value': 'score={score}'}),
              act('Emit', {'event': 'bare'}),
            ]),
            b('OnEvent', {
              'event': 'grant',
              'store': 'bonus',
              'actions': [
                act('AddVariable', {'name': 'lives', 'value': 1}),
              ],
            }),
            b('OnEvent', {
              'event': 'restart',
              'actions': [
                act('ResetVariables', {'names': 'lives'}),
              ],
            }),
          ],
        ),
      ),
      onEmit: (n, v) => events.add('$n:$v'),
    ),
    (g) async {
      g.update(0.02);
      expect(events, ['done:score=7', 'bare:null']);
      g.emit('grant', value: 50);
      expect((g.vars['bonus'], g.vars['lives']), (50, 4));
      g.emit('restart');
      expect(g.vars['lives'], 3);
    },
  );

  testWithGame(
    'editing: emits are inert',
    () => KilnGame(SceneDoc.fromJson(sceneJson('a', {}, [])), editing: true, onEmit: (n, v) => fail('emitted')),
    (g) async => g.emit('x'),
  );

  testWidgets('controller: overrides, events out, emit in, loadScene, keepVariables=false resets', (t) async {
    mockAssets(t, {
      'a.json': sceneJson(
        'a',
        {'score': 0, 'lives': 3},
        [
          once([
            act('Emit', {'event': 'hello', 'value': '{lives}'}),
          ]),
          b('OnEvent', {
            'event': 'next',
            'actions': [
              act('AddVariable', {'name': 'score', 'value': 5}),
              act('LoadScene', {'scene': 'b.json'}),
            ],
          }),
        ],
      ),
      'b.json': sceneJson('b', {'level': 2}, []),
    });
    final c = KilnController(variables: {'lives': 9});
    addTearDown(c.dispose);
    final got = <String>[];
    await t.pumpWidget(
      MaterialApp(
        home: KilnGameWidget(asset: 'a.json', controller: c, onEvent: (n, v) => got.add('$n:$v')),
      ),
    );
    await settle(t);
    expect((c.scene, c.vars['lives'], c.vars['score']), ('a.json', 9, 0));
    await settle(t);
    expect(got, ['hello:9']);

    c.emit('next');
    await settle(t);
    expect(c.scene, 'b.json');
    expect(c.vars['score'], isNull); // fresh variables per scene
    expect((c.vars['level'], c.vars['lives']), (2, 9)); // app overrides still apply
    expect(find.byWidgetPredicate((w) => w is GameWidget), findsOneWidget);
  });

  testWidgets('controller keepVariables: values survive LoadScene, new scene adds only missing defaults', (t) async {
    mockAssets(t, {
      'keep_a.json': sceneJson('a', {'coins': 0}, []),
      'keep_b.json': sceneJson('b', {'coins': 100, 'stars': 1}, []),
    });
    final c = KilnController(keepVariables: true);
    addTearDown(c.dispose);
    await t.pumpWidget(
      MaterialApp(
        home: KilnGameWidget(asset: 'keep_a.json', controller: c),
      ),
    );
    await settle(t);
    await settle(t);
    c.vars['coins'] = 4;
    c.loadScene('keep_b.json');
    await settle(t);
    expect((c.scene, c.vars['coins'], c.vars['stars']), ('keep_b.json', 4, 1));
  });

  test('syncSchema writes once, then reports up to date, and catches drift', () {
    final dir = Directory.systemTemp.createTempSync('kiln_schema');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/kiln.schema.json';
    final reg = KilnRegistry();
    expect(syncSchema(reg, path), isTrue);
    expect(syncSchema(reg, path), isFalse);
    reg.registerAction(ActionDef('Ping', const [], (s, a) {}));
    expect(syncSchema(reg, path), isTrue);
    expect(File(path).readAsStringSync(), contains('"Ping"'));
  });

  group('generateTypes', () {
    test('list and map variables get typed accessors; a formula SetVariable is Object?', () {
      final src = generateTypes({
        'assets/scenes/a.kiln.json': {
          'variables': {'inv': <Object?>[], 'table': <String, Object?>{}},
          'entities': [
            {
              'behaviors': [
                b('OnTap', {
                  'actions': [
                    act('SetVariable', {'name': 'calc', 'value': '=1 + 2'}),
                    act('AddVariable', {'name': 'mine', 'scope': 'self'}),
                  ],
                }),
              ],
            },
          ],
        },
      });
      expect(src, contains("List<Object?> get inv => list('inv');"));
      expect(src, contains("Map<String, Object?> get table => map('table');"));
      expect(src, contains('Object? get calc'));
      expect(src, isNot(contains('get mine')));
    });
    test('scenes, events (incl. nested hurt/death), variables with inferred types', () {
      final src = generateTypes({
        'assets/scenes/level-1.kiln.json': {
          'variables': {'coins': 0, 'name': 'x', 'on': false, 'mixed': 1, 'class': 2},
          'entities': [
            {
              'behaviors': [
                b('Health', {
                  'variable': 'hp',
                  'death': [
                    act('Emit', {'event': 'game over'}),
                  ],
                }),
                b('OnEvent', {'event': 'grant', 'store': 'bonus'}),
                b('OnTap', {
                  'actions': [
                    act('SetVariable', {'name': 'label'}),
                    act('AddVariable', {'name': 'number'}),
                  ],
                }),
              ],
              'children': [
                {
                  'behaviors': [
                    b('Timer', {
                      'actions': [
                        act('Emit', {'event': 'tick'}),
                      ],
                    }),
                  ],
                },
              ],
            },
          ],
        },
        'assets/scenes/2win.kiln.json': {
          'variables': {'mixed': 'now text'},
        },
      });
      expect(src, contains("static const level1 = 'assets/scenes/level-1.kiln.json';"));
      expect(src, contains("static const v2win = 'assets/scenes/2win.kiln.json';"));
      expect(src, contains("static const gameOver = 'game over';"));
      expect(src, contains("static const grant = 'grant';"));
      expect(src, contains("static const tick = 'tick';"));
      expect(src, contains("double get coins => number('coins');"));
      expect(src, contains("String get name => string('name');"));
      expect(src, contains("bool get on => flag('on');"));
      expect(src, contains("Object? get mixed => this['mixed'];"));
      expect(src, contains("double get classVar => number('class');"));
      expect(src, contains("double get hp => number('hp');"));
      expect(src, contains("Object? get bonus => this['bonus'];"));
      expect(src, contains("String get label => string('label');"));
      expect(src, contains("double get numberVar => number('number');"));
      expect(src, contains("static Map<String, Object?> initial({Object? bonus, double? classVar, double? coins,"));
      expect(src, contains("if (classVar != null) 'class': classVar"));
      // Stable output: key order of the input does not matter.
      final x = {'assets/scenes/b.kiln.json': {}, 'assets/scenes/a.kiln.json': {}};
      expect(generateTypes(x), generateTypes(Map.fromEntries(x.entries.toList().reversed)));
    });

    test('name clashes get suffixes; quotes and dollars are escaped', () {
      final src = generateTypes({
        'assets/scenes/a.kiln.json': {
          'variables': {'my-var': 1, 'my var': 2, r"it's $x": 3},
        },
      });
      expect(src, contains("double get myVar => number('my var');")); // sorted: ' ' before '-'
      expect(src, contains("double get myVar2 => number('my-var');"));
      expect(src, contains(r"double get itSX => number('it\'s \$x');"));
    });

    test('writeProjectTypes: needs pubspec, writes once, skips bad scenes', () async {
      final dir = Directory.systemTemp.createTempSync('kiln_types');
      addTearDown(() => dir.deleteSync(recursive: true));
      await expectLater(writeProjectTypes(dir.path), throwsStateError);
      File('${dir.path}/pubspec.yaml').writeAsStringSync('name: x\n');
      Directory('${dir.path}/assets/scenes').createSync(recursive: true);
      File('${dir.path}/assets/scenes/a.kiln.json').writeAsStringSync(jsonEncode(sceneJson('a', {'score': 0}, [])));
      File('${dir.path}/assets/scenes/bad.kiln.json').writeAsStringSync('{');
      final r = await writeProjectTypes(dir.path);
      expect(r.written, isTrue);
      expect(r.skipped, ['bad.kiln.json']);
      expect(File('${dir.path}/lib/kiln.g.dart').readAsStringSync(), contains('get score'));
      expect((await writeProjectTypes(dir.path)).written, isFalse);
    });
  });
}
