import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiln/kiln.dart';
import 'package:kiln/src/builtins.dart' show Body;

Map<String, Object?> ent(
  String name,
  List<Map<String, Object?>> behaviors, {
  required List<num> pos,
  List<num> size = const [20, 20],
}) => {'id': name, 'name': name, 'position': pos, 'size': size, 'behaviors': behaviors};

Map<String, Object?> b(String type, [Map<String, Object?> props = const {}]) => {'type': type, 'props': props};

Map<String, Object?> act(String type, [Map<String, Object?> args = const {}]) => {'type': type, ...args};

SceneDoc scene(List<Map<String, Object?>> entities, {List<num>? world}) => SceneDoc.fromJson({
  'size': [400, 300],
  'world': ?world,
  'variables': {'landed': 0},
  'entities': entities,
});

KilnEntity named(KilnGame g, String n) => g.world.children.whereType<KilnEntity>().firstWhere((e) => e.node.name == n);
Body body(KilnGame g, String n) => named(g, n).children.whereType<Body>().single;

void steps(KilnGame g, double seconds, {double dt = 1 / 60}) {
  for (var t = 0.0; t < seconds; t += dt) {
    g.update(dt);
  }
}

/// Floor: top edge at y=200.
final floor = ent('floor', [b('Solid')], pos: [200, 210], size: [400, 20]);

Map<String, Object?> hero({
  List<num> pos = const [100, 100],
  Map<String, Object?> props = const {},
  List<Map<String, Object?>> extra = const [],
}) => ent('hero', [b('Body', props), ...extra], pos: pos);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWithGame(
    'Body falls, lands on Solid, OnLand fires once',
    () => KilnGame(
      scene([
        floor,
        hero(
          extra: [
            b('OnLand', {
              'actions': [
                act('AddVariable', {'name': 'landed', 'value': 1}),
              ],
            }),
          ],
        ),
      ]),
    ),
    (g) async {
      steps(g, 1.5);
      final h = named(g, 'hero');
      expect(h.toAbsoluteRect().bottom, closeTo(200, 1e-6));
      expect(body(g, 'hero').onGround, isTrue);
      expect(body(g, 'hero').v.y, 0);
      expect(g.vars['landed'], 1);
    },
  );

  testWithGame(
    'walls stop horizontal motion; ceilings stop jumps',
    () => KilnGame(
      scene([
        floor,
        ent('wall', [b('Solid')], pos: [160, 150], size: [20, 100]),
        ent('ceiling', [b('Solid')], pos: [140, 130], size: [100, 20]),
        hero(pos: [100, 190]),
      ]),
    ),
    (g) async {
      steps(g, 0.1);
      body(g, 'hero').v.x = 300;
      steps(g, 0.5);
      expect(named(g, 'hero').toAbsoluteRect().right, closeTo(150, 1e-6));
      body(g, 'hero').jump(600);
      steps(g, 0.1);
      // Ceiling bottom is y=140: the head stops there.
      expect(named(g, 'hero').toAbsoluteRect().top, greaterThanOrEqualTo(140 - 1e-6));
    },
  );

  testWithGame(
    'one-way platform: pass up through it, land on it from above',
    () => KilnGame(
      scene([
        floor,
        ent(
          'ledge',
          [
            b('Solid', {'oneWay': true}),
          ],
          pos: [100, 150],
          size: [100, 10],
        ),
        hero(pos: [100, 190]),
      ]),
    ),
    (g) async {
      steps(g, 0.1);
      body(g, 'hero').jump(700);
      steps(g, 1.5);
      // Landed on the ledge top (y=145), not back on the floor.
      expect(named(g, 'hero').toAbsoluteRect().bottom, closeTo(145, 1e-6));
      expect(body(g, 'hero').onGround, isTrue);
    },
  );

  testWithGame(
    'Jump needs ground (with coyote time) unless air; Flip faces',
    () => KilnGame(
      scene([
        floor,
        hero(
          pos: [100, 190],
          extra: [
            b('OnKey', {
              'key': 'Space',
              'actions': [act('Jump')],
            }),
          ],
        ),
      ]),
    ),
    (g) async {
      steps(g, 0.1);
      final h = named(g, 'hero'), bd = body(g, 'hero');
      g.registry.runActions(h, [act('Jump')]);
      expect(bd.v.y, -600);
      g.update(1 / 60);
      g.registry.runActions(h, [act('Jump')]); // in the air: ignored
      expect(bd.v.y, greaterThan(-600));
      g.registry.runActions(h, [
        act('Jump', {'air': true, 'force': 300}),
      ]);
      expect(bd.v.y, -300);

      g.registry.runActions(h, [act('Flip')]);
      expect(h.isFlippedHorizontally, isTrue);
      g.registry.runActions(h, [
        act('Flip', {'face': 'left'}),
      ]);
      expect(h.isFlippedHorizontally, isTrue);
      g.registry.runActions(h, [
        act('Flip', {'face': 'right'}),
      ]);
      expect(h.isFlippedHorizontally, isFalse);
    },
  );

  testWithGame(
    'coyote time allows a jump just after walking off a ledge',
    () => KilnGame(
      scene([
        ent('ledge', [b('Solid')], pos: [50, 210], size: [100, 20]),
        hero(pos: [85, 190], props: {'coyote': 0.1}),
      ]),
    ),
    (g) async {
      steps(g, 0.1);
      final bd = body(g, 'hero');
      bd.v.x = 300;
      steps(g, 0.1); // off the ledge edge (x=100) for a few frames
      expect(bd.onGround, isFalse);
      expect(bd.canJump, isTrue);
      steps(g, 0.1);
      expect(bd.canJump, isFalse);
    },
  );

  testWithGame(
    'fast fall does not tunnel through a thin solid; friction stops sliding',
    () => KilnGame(
      scene([
        ent('thin', [b('Solid')], pos: [200, 200], size: [400, 2]),
        hero(pos: [100, 20], props: {'maxFall': 5000, 'gravity': 50000, 'friction': 2000}),
      ]),
    ),
    (g) async {
      steps(g, 0.2, dt: 1 / 30);
      expect(named(g, 'hero').toAbsoluteRect().bottom, closeTo(199, 1e-6));
      body(g, 'hero').v.x = 500;
      steps(g, 0.5);
      expect(body(g, 'hero').v.x, 0);
    },
  );

  testWithGame(
    'Parallax: factor 0 pins to the screen, 0.5 scrolls at half speed',
    () => KilnGame(
      scene(
        [
          ent(
            'hud',
            [
              b('Parallax', {'factorX': 0, 'factorY': 0}),
            ],
            pos: [50, 20],
          ),
          ent(
            'hills',
            [
              b('Parallax', {'factorX': 0.5}),
            ],
            pos: [300, 250],
          ),
        ],
        world: [2000, 300],
      ),
    ),
    (g) async {
      g.camera.viewfinder.position = Vector2(400, 0);
      g.update(0);
      expect(named(g, 'hud').position, Vector2(450, 20));
      expect(named(g, 'hills').position, Vector2(500, 250));
    },
  );
}
