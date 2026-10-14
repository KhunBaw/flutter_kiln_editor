import 'dart:math';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'game.dart';
import 'registry.dart';
import 'scene.dart';

final builtinBehaviors = <BehaviorDef>[
  BehaviorDef('Shape', const [
    PropDef('shape', PropKind.choice, 'rect', options: ['rect', 'oval']),
    PropDef('color', PropKind.color, '#4488FF'),
  ], (e, p) => _Shape(oval: p.string('shape') == 'oval', paint: Paint()..color = p.color('color'))),
  BehaviorDef('Sprite', const [PropDef('image', PropKind.image, '')], (e, p) async {
    final src = p.string('image');
    if (src.isEmpty) return null;
    final images = e.game.images;
    try {
      // Not Sprite.load: Flame's image cache leaks load errors as uncaught, so fetch and cache manually.
      if (!images.containsKey(src)) {
        final data = await images.bundle.load('${images.prefix}$src');
        images.add(src, await decodeImageFromList(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes)));
      }
      return SpriteComponent(sprite: Sprite(images.fromCache(src)), size: e.size);
    } catch (err) {
      // A missing image must not break the whole scene.
      debugPrint('kiln: Sprite "$src" on ${e.node.name}: $err');
      return null;
    }
  }),
  BehaviorDef(
    'Text',
    const [
      PropDef('text', PropKind.string, 'Text {score}'),
      PropDef('fontSize', PropKind.number, 24),
      PropDef('color', PropKind.color, '#FFFFFF'),
    ],
    (e, p) => _VarText(p.string('text'), TextStyle(fontSize: p.number('fontSize'), color: p.color('color')))
      ..position = e.size / 2
      ..anchor = Anchor.center,
  ),
  BehaviorDef('OnTap', const [PropDef('actions', PropKind.actions, [])], (e, p) {
    // shortcut: hit-test uses the bounding rect, also for ovals; refine if precise taps matter.
    e.tapHandlers.add(() => e.runActions(p.list('actions')));
    return null;
  }),
  BehaviorDef(
    'Timer',
    const [
      PropDef('interval', PropKind.number, 1),
      PropDef('repeat', PropKind.bool, true),
      PropDef('actions', PropKind.actions, []),
    ],
    (e, p) => TimerComponent(
      period: _minPeriod(p.number('interval')),
      repeat: p.flag('repeat'),
      onTick: () => e.runActions(p.list('actions')),
    ),
  ),
  // Marker: a top-level entity with Prefab is hidden at play time and used as a Spawner template.
  BehaviorDef('Prefab', const [], (e, p) => null),
  BehaviorDef(
    'Spawner',
    const [
      PropDef('prefab', PropKind.string, ''),
      PropDef('interval', PropKind.number, 1),
      PropDef('max', PropKind.number, 0),
    ],
    (e, p) {
      var count = 0;
      final max = p.number('max');
      return TimerComponent(
        period: _minPeriod(p.number('interval')),
        repeat: true,
        onTick: () {
          if (max > 0 && count >= max) return;
          final node = e.game.prefabs[p.string('prefab')];
          if (node == null) {
            debugPrint('kiln: Spawner on ${e.node.name}: no prefab named "${p.string('prefab')}"');
            return;
          }
          count++;
          // Random point inside the spawner's own rect, in world space.
          final at = e.absolutePositionOf(Vector2(_rng.nextDouble() * e.size.x, _rng.nextDouble() * e.size.y));
          final clone = EntityNode.fromJson(node.toJson())
            ..id = '${node.id}#$count'
            ..position = at;
          e.game.world.add(KilnEntity(clone));
        },
      );
    },
  ),
  BehaviorDef(
    'Tween',
    const [
      PropDef('kind', PropKind.choice, 'moveBy', options: ['moveBy', 'scaleBy', 'rotateBy']),
      PropDef('x', PropKind.number, 0),
      PropDef('y', PropKind.number, -50),
      PropDef('duration', PropKind.number, 1),
      PropDef('loop', PropKind.choice, 'pingpong', options: ['once', 'repeat', 'pingpong']),
    ],
    (e, p) {
      final loop = p.string('loop');
      final c = EffectController(
        duration: _minPeriod(p.number('duration')),
        infinite: loop != 'once',
        alternate: loop == 'pingpong',
      );
      final v = Vector2(p.number('x'), p.number('y'));
      return switch (p.string('kind')) {
        'scaleBy' => ScaleEffect.by(v, c),
        'rotateBy' => RotateEffect.by(v.x, c),
        _ => MoveByEffect(v, c),
      };
    },
  ),
  BehaviorDef('Condition', const [
    PropDef('variable', PropKind.string, 'score'),
    PropDef('op', PropKind.choice, '>=', options: ['==', '!=', '>', '>=', '<', '<=']),
    PropDef('value', PropKind.number, 10),
    PropDef('actions', PropKind.actions, []),
  ], (e, p) => _Condition(e, p)),
  BehaviorDef('Collider', const [
    PropDef('shape', PropKind.choice, 'rect', options: ['rect', 'circle']),
  ], (e, p) => p.string('shape') == 'circle' ? CircleHitbox() : RectangleHitbox()),
  BehaviorDef('OnCollide', const [PropDef('with', PropKind.string, ''), PropDef('actions', PropKind.actions, [])], (
    e,
    p,
  ) {
    final only = p.string('with');
    e.collideHandlers.add((other) {
      if (only.isEmpty || other.node.name == only) e.runActions(p.list('actions'));
    });
    return null;
  }),
];

final _rng = Random();

// Zero/negative periods would make repeating timers spin.
double _minPeriod(double v) => v < 0.01 ? 0.01 : v;

final builtinActions = <ActionDef>[
  ActionDef('AddVariable', const [PropDef('name', PropKind.string, 'score'), PropDef('value', PropKind.number, 1)], (
    self,
    a,
  ) {
    final vars = self.game.vars;
    final cur = vars[a.string('name')];
    vars[a.string('name')] = (cur is num ? cur : 0) + a.number('value');
  }),
  ActionDef('SetVariable', const [
    PropDef('name', PropKind.string, 'score'),
    PropDef('value', PropKind.string, ''),
  ], (self, a) => self.game.vars[a.string('name')] = a['value']),
  ActionDef('Destroy', const [], (self, a) => self.removeFromParent()),
  ActionDef('PlaySound', const [PropDef('file', PropKind.audio, '')], (self, a) {
    final file = a.string('file');
    if (file.isEmpty) return;
    final play = self.game.playSound;
    if (play != null) return play(file);
    FlameAudio.play(file).catchError((Object err) {
      debugPrint('kiln: PlaySound "$file": $err');
      return AudioPlayer();
    });
  }),
  ActionDef('LoadScene', const [PropDef('scene', PropKind.string, 'assets/scenes/level1.kiln.json')], (self, a) {
    final go = self.game.onLoadScene;
    go == null ? debugPrint('kiln: LoadScene("${a.string('scene')}") not supported here') : go(a.string('scene'));
  }),
];

/// Runs actions once each time the comparison turns true (edge-triggered, not every frame).
class _Condition extends Component {
  _Condition(this.e, this.p);

  final KilnEntity e;
  final Props p;
  bool _was = false;

  bool _test() {
    final v = e.game.vars[p.string('variable')];
    if (v is! num) return false;
    final x = p.number('value');
    return switch (p.string('op')) {
      '==' => v == x,
      '!=' => v != x,
      '>' => v > x,
      '<' => v < x,
      '<=' => v <= x,
      _ => v >= x,
    };
  }

  void _check() {
    final now = _test();
    if (now && !_was) e.runActions(p.list('actions'));
    _was = now;
  }

  @override
  void onMount() {
    if (e.game.editing) return;
    e.game.vars.addListener(_check);
    _check();
  }

  @override
  void onRemove() => e.game.vars.removeListener(_check);
}

class _Shape extends Component with ParentIsA<KilnEntity> {
  _Shape({required this.oval, required this.paint});

  final bool oval;
  final Paint paint;

  @override
  void render(Canvas canvas) {
    final rect = Offset.zero & parent.size.toSize();
    oval ? canvas.drawOval(rect, paint) : canvas.drawRect(rect, paint);
  }
}

/// Renders a template like "Score: {score}", re-rendered whenever a game variable changes.
class _VarText extends TextComponent with HasGameReference<KilnGame> {
  _VarText(this.template, TextStyle style) : super(textRenderer: TextPaint(style: style));

  final String template;
  static final _slot = RegExp(r'\{(\w+)\}');

  void _refresh() {
    text = template.replaceAllMapped(_slot, (m) {
      final v = game.vars[m[1]!];
      return switch (v) {
        double d when d == d.roundToDouble() => d.toInt().toString(),
        _ => '${v ?? ''}',
      };
    });
  }

  @override
  void onMount() {
    _refresh();
    game.vars.addListener(_refresh);
  }

  @override
  void onRemove() => game.vars.removeListener(_refresh);
}
