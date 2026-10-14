import 'dart:math';
import 'dart:ui' show Image;

import 'package:flame/camera.dart' show Viewport;
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/particles.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import 'animation.dart';
import 'expr.dart';
import 'pointer.dart';
import 'game.dart';
import 'registry.dart';
import 'tilemap.dart';
import 'ui.dart';
import 'wheel.dart';

final builtinBehaviors = <BehaviorDef>[
  BehaviorDef('Shape', const [
    PropDef('shape', PropKind.choice, 'rect', options: ['rect', 'oval']),
    PropDef('color', PropKind.color, '#4488FF'),
  ], (e, p) => _Shape(oval: p.string('shape') == 'oval', paint: Paint()..color = p.color('color'))),
  BehaviorDef('Sprite', const [PropDef('image', PropKind.image, '')], (e, p) async {
    final img = await loadKilnImage(e, 'Sprite', p.string('image'));
    return img == null ? null : SpriteComponent(sprite: Sprite(img), size: e.size);
  }),
  BehaviorDef(
    'SpriteAnimation',
    const [
      PropDef('image', PropKind.image, ''),
      PropDef('cols', PropKind.number, 1),
      PropDef('rows', PropKind.number, 1),
      PropDef('fps', PropKind.number, 8),
      // "idle:0-3, run:4-9"; frames count left-to-right, top-to-bottom. Empty = one clip of every frame.
      PropDef('clips', PropKind.string, ''),
      PropDef('start', PropKind.string, ''),
      PropDef('loop', PropKind.bool, true),
    ],
    (e, p) async {
      final img = await loadKilnImage(e, 'SpriteAnimation', p.string('image'));
      if (img == null) return null;
      final cols = max(1, p.number('cols').round()), rows = max(1, p.number('rows').round());
      final cell = Vector2(img.width / cols, img.height / rows);
      final frames = [
        for (var r = 0; r < rows; r++)
          for (var c = 0; c < cols; c++) Sprite(img, srcPosition: Vector2(c * cell.x, r * cell.y), srcSize: cell),
      ];
      final step = 1 / max(0.1, p.number('fps'));
      final clips = {
        for (final MapEntry(:key, value: (a, b)) in parseClips(p.string('clips'), frames.length).entries)
          key: SpriteAnimation.spriteList(frames.sublist(a, b + 1), stepTime: step, loop: p.flag('loop')),
      };
      final start = p.string('start');
      return SpriteAnimationGroupComponent<String>(
        animations: clips,
        current: clips.containsKey(start) ? start : clips.keys.first,
        size: e.size,
      );
    },
  ),
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
          // Random point inside the spawner's own rect, in world space.
          final at = e.absolutePositionOf(Vector2(_rng.nextDouble() * e.size.x, _rng.nextDouble() * e.size.y));
          if (e.game.spawn(p.string('prefab'), at) == null) {
            debugPrint('kiln: Spawner on ${e.node.name}: no prefab named "${p.string('prefab')}"');
            return;
          }
          count++;
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
  BehaviorDef(
    'Animator',
    const [
      PropDef('duration', PropKind.number, 1),
      PropDef('loop', PropKind.choice, 'loop', options: animLoops),
      PropDef('autoplay', PropKind.bool, true),
      // [{prop, keys: [{t, v, ease}]}] edited in the editor's Timeline.
      PropDef('tracks', PropKind.keyframes, []),
    ],
    (e, p) {
      final a = AnimatorComponent(p);
      e.animator = a;
      return a;
    },
  ),
  BehaviorDef('Condition', const [
    PropDef('variable', PropKind.string, 'score'),
    PropDef('op', PropKind.choice, '>=', options: ['==', '!=', '>', '>=', '<', '<=']),
    PropDef('value', PropKind.number, 10),
    // Formula (e.g. "=self.x > 300 && score >= 3"); when set it replaces variable/op/value.
    PropDef('expr', PropKind.string, ''),
    // frame = re-check every update (needed for self.x, time); change = only when a variable changes.
    PropDef('check', PropKind.choice, 'change', options: ['change', 'frame']),
    PropDef('actions', PropKind.actions, []),
  ], (e, p) => _Condition(e, p)),
  BehaviorDef('StateMachine', const [
    PropDef('initial', PropKind.string, ''),
    // [{name, enter: [actions], update: [actions], exit: [actions]}]
    PropDef('states', PropKind.json, []),
    // [{from: "state" or "*", to: "state", when: "formula"}]
    PropDef('transitions', PropKind.json, []),
  ], (e, p) => StateMachine(p)),
  BehaviorDef('OnPointer', const [
    // Pointer (mouse/touch) anywhere on screen; formulas read pointer.x, pointer.y, pointer.down.
    PropDef('down', PropKind.actions, []),
    PropDef('move', PropKind.actions, []),
    PropDef('up', PropKind.actions, []),
  ], (e, p) => OnPointer(p)),
  BehaviorDef(
    'Joystick',
    const [
      // Drag inside this entity: variables get -1..1; speed > 0 also moves `target`.
      PropDef('varX', PropKind.string, 'joyX'),
      PropDef('varY', PropKind.string, 'joyY'),
      PropDef('speed', PropKind.number, 0),
      PropDef('target', PropKind.string, ''),
    ],
    (e, p) =>
        Joystick(varX: p.string('varX'), varY: p.string('varY'), speed: p.number('speed'), target: p.string('target')),
  ),
  BehaviorDef('Collider', const [
    PropDef('shape', PropKind.choice, 'rect', options: ['rect', 'circle']),
    // Solid hitboxes also collide when one box lies fully inside the other (a small marker under a crate).
  ], (e, p) => p.string('shape') == 'circle' ? CircleHitbox(isSolid: true) : RectangleHitbox(isSolid: true)),
  BehaviorDef(
    'OnCollide',
    const [
      PropDef('with', PropKind.string, ''),
      PropDef('actions', PropKind.actions, []),
      // Runs when the contact ends (or the partner is destroyed).
      PropDef('exit', PropKind.actions, []),
    ],
    (e, p) {
      final only = p.string('with');
      bool match(KilnEntity other) =>
          only.isEmpty ||
          other.node.name == only ||
          (only.startsWith('#') && other.node.tags.contains(only.substring(1)));
      e.collideHandlers.add((other) {
        if (match(other)) e.runActions(p.list('actions'), other: other);
      });
      e.separateHandlers.add((other) {
        if (match(other)) e.runActions(p.list('exit'), other: other);
      });
      return null;
    },
  ),
  BehaviorDef(
    'Tilemap',
    const [
      // Tileset image: square tiles of `tile` px laid out left-to-right, top-to-bottom. Empty draws flat colours.
      PropDef('image', PropKind.image, ''),
      PropDef('tile', PropKind.number, 32),
      PropDef('cols', PropKind.number, 10),
      // Row-major tile numbers: 0 empty, n = tileset tile n (1-based). Painted in the editor.
      PropDef('tiles', PropKind.tiles, []),
      // Tile numbers that block Body, GridMove and pathfinding, e.g. "1, 2".
      PropDef('solid', PropKind.string, '1'),
    ],
    (e, p) async => Tilemap(
      tile: max(1, p.number('tile')),
      cols: max(1, p.number('cols').round()),
      tiles: [for (final t in p.list('tiles')) t is num ? t.toInt() : 0],
      solid: parseIds(p.string('solid')),
      image: await loadKilnImage(e, 'Tilemap', p.string('image')),
    ),
  ),
  BehaviorDef(
    'GridMove',
    const [
      PropDef('cell', PropKind.number, 32),
      // Seconds per step; 0 jumps instantly.
      PropDef('time', PropKind.number, 0.12),
      PropDef('keys', PropKind.choice, 'both', options: ['both', 'arrows', 'wasd']),
      // Name or #tag of entities this one pushes one cell; blocked pushes stop the walker.
      PropDef('push', PropKind.string, ''),
      // Name or #tag of entities that can't be entered.
      PropDef('block', PropKind.string, ''),
      PropDef('onStep', PropKind.actions, []),
    ],
    (e, p) => GridMove(
      cell: max(1, p.number('cell')),
      time: max(0, p.number('time')),
      keys: p.string('keys'),
      push: p.string('push'),
      block: p.string('block'),
      actions: p.list('onStep'),
    ),
  ),
  BehaviorDef(
    'Dialogue',
    const [
      // Lines separated by "|"; "{name}" slots read variables.
      PropDef('lines', PropKind.string, 'Hello!|How are you?'),
      // Shown with the last line, picked by tap or number key: "Fine|Tired".
      PropDef('choices', PropKind.string, ''),
      // Receives the picked choice's 1-based number.
      PropDef('variable', PropKind.string, 'answer'),
      // Event that opens it; empty opens at start.
      PropDef('open', PropKind.string, ''),
      PropDef('fontSize', PropKind.number, 18),
      PropDef('color', PropKind.color, '#FFFFFF'),
      PropDef('actions', PropKind.actions, []),
    ],
    (e, p) => Dialogue(
      lines: _split(p.string('lines')),
      choices: _split(p.string('choices')),
      variable: p.string('variable'),
      open: p.string('open'),
      style: TextStyle(fontSize: p.number('fontSize'), color: p.color('color')),
      actions: p.list('actions'),
    ),
  ),
  // UI layer: Hud pins to the screen; Button/Panel/ProgressBar draw themselves.
  BehaviorDef('Hud', const [], (e, p) => Hud()),
  BehaviorDef(
    'Button',
    const [
      PropDef('label', PropKind.string, 'Button'),
      PropDef('fontSize', PropKind.number, 20),
      PropDef('textColor', PropKind.color, '#FFFFFF'),
      PropDef('color', PropKind.color, '#3A6FD8'),
      PropDef('pressedColor', PropKind.color, '#2A4F9A'),
      PropDef('radius', PropKind.number, 8),
      PropDef('actions', PropKind.actions, []),
    ],
    (e, p) {
      final box = UiBox(
        color: p.color('color'),
        pressed: p.color('pressedColor'),
        border: const Color(0x00000000),
        radius: p.number('radius'),
        label: p.string('label'),
        style: TextStyle(fontSize: p.number('fontSize'), color: p.color('textColor')),
      );
      e.tapHandlers.add(() {
        box.press();
        e.runActions(p.list('actions'));
      });
      return box;
    },
  ),
  BehaviorDef(
    'Panel',
    const [
      PropDef('color', PropKind.color, '#222A33'),
      PropDef('border', PropKind.color, '#44525F'),
      PropDef('radius', PropKind.number, 10),
      // Optional 9-slice image: a 3×3 grid of `slice`-px cells that stretches to the entity size.
      PropDef('image', PropKind.image, ''),
      PropDef('slice', PropKind.number, 16),
    ],
    (e, p) async => UiBox(
      color: p.color('color'),
      border: p.color('border'),
      radius: p.number('radius'),
      box: nineSlice(await loadKilnImage(e, 'Panel', p.string('image')), p.number('slice')),
    ),
  ),
  BehaviorDef(
    'ProgressBar',
    const [
      PropDef('variable', PropKind.string, 'hp'),
      PropDef('max', PropKind.number, 100),
      PropDef('color', PropKind.color, '#6CC070'),
      PropDef('background', PropKind.color, '#2B3138'),
    ],
    (e, p) => ProgressBar(
      variable: p.string('variable'),
      max: p.number('max'),
      fill: p.color('color'),
      back: p.color('background'),
    ),
  ),
  BehaviorDef('Draggable', const [
    PropDef('snapBack', PropKind.bool, true),
    // Runs on the dragged entity after a drop; `other` is the zone.
    PropDef('actions', PropKind.actions, []),
  ], (e, p) => Draggable(snapBack: p.flag('snapBack'), actions: p.list('actions'))),
  BehaviorDef('DropZone', const [
    // Name or #tag of entities this zone takes; empty takes any.
    PropDef('accept', PropKind.string, ''),
    PropDef('snap', PropKind.bool, true),
    // Runs on the zone after a drop; `other` is the dropped entity.
    PropDef('actions', PropKind.actions, []),
  ], (e, p) => DropZone(accept: p.string('accept'), snap: p.flag('snap'), actions: p.list('actions'))),
  BehaviorDef(
    'Wheel',
    const [
      // Slices as `label|image|weight|#colour;...`; the variable below overrides it when set (app-controlled).
      PropDef('slices', PropKind.string, 'Coins|coin.png|40;Gem|gem.png|10;Star|star.png|1'),
      PropDef('variable', PropKind.string, 'slices'),
      PropDef('resultVar', PropKind.string, 'result'),
      // Spin limit: 0 = unlimited; the number in the `limitVar` variable overrides it. Spins count into `spinsVar`; `leftVar` shows what remains.
      PropDef('limit', PropKind.number, 0),
      PropDef('limitVar', PropKind.string, 'limit'),
      PropDef('spinsVar', PropKind.string, 'spins'),
      PropDef('leftVar', PropKind.string, 'left'),
      PropDef('revealTime', PropKind.number, 2.5),
      PropDef('spinTime', PropKind.number, 4),
      PropDef('minTurns', PropKind.number, 4),
      PropDef('spinEvent', PropKind.string, 'spin'),
    ],
    (e, p) => Wheel(
      spec: p['slices'],
      variable: p.string('variable'),
      resultVar: p.string('resultVar'),
      limit: p.number('limit'),
      limitVar: p.string('limitVar'),
      spinsVar: p.string('spinsVar'),
      leftVar: p.string('leftVar'),
      revealTime: p.number('revealTime'),
      spinTime: p.number('spinTime'),
      minTurns: p.number('minTurns'),
      spinEvent: p.string('spinEvent'),
      random: _rng,
    ),
  ),
  BehaviorDef('VarSprite', const [
    PropDef('variable', PropKind.string, 'background'),
    PropDef('image', PropKind.image, ''),
  ], (e, p) => VarSprite(variable: p.string('variable'), image: p.string('image'))),
  BehaviorDef('OnEvent', const [
    PropDef('event', PropKind.string, 'event'),
    // Variable that receives the event's value (e.g. sent by the app) before the actions run.
    PropDef('store', PropKind.string, ''),
    PropDef('actions', PropKind.actions, []),
  ], (e, p) => _OnEvent(p.string('event'), p.string('store'), p.list('actions'))),
  BehaviorDef('OnKey', const [
    PropDef('key', PropKind.choice, 'Space', options: keyNames),
    PropDef('on', PropKind.choice, 'down', options: ['down', 'up', 'held']),
    PropDef('actions', PropKind.actions, []),
  ], (e, p) => _OnKey(_keys[p.string('key')], p.string('on'), p.list('actions'))),
  BehaviorDef(
    'Velocity',
    const [
      PropDef('vx', PropKind.number, 0),
      PropDef('vy', PropKind.number, 0),
      PropDef('spin', PropKind.number, 0),
      PropDef('space', PropKind.choice, 'world', options: ['world', 'local']),
    ],
    (e, p) => _oneMover(
      e,
      'Velocity',
      () => Motion(p.number('vx'), p.number('vy'), p.number('spin'), local: p.string('space') == 'local'),
    ),
  ),
  BehaviorDef('Camera', const [
    PropDef('deadzoneW', PropKind.number, 0),
    PropDef('deadzoneH', PropKind.number, 0),
    PropDef('clamp', PropKind.bool, true),
  ], (e, p) => _Camera(Vector2(p.number('deadzoneW'), p.number('deadzoneH')), clamp: p.flag('clamp'))),
  BehaviorDef(
    'Body',
    const [
      PropDef('gravity', PropKind.number, 1400),
      PropDef('maxFall', PropKind.number, 900),
      PropDef('friction', PropKind.number, 0),
      PropDef('coyote', PropKind.number, 0.1),
    ],
    (e, p) => _oneMover(
      e,
      'Body',
      () => Body(
        gravity: p.number('gravity'),
        maxFall: p.number('maxFall'),
        friction: p.number('friction'),
        coyote: p.number('coyote'),
      ),
    ),
  ),
  BehaviorDef('Solid', const [PropDef('oneWay', PropKind.bool, false)], (e, p) => Solid(oneWay: p.flag('oneWay'))),
  BehaviorDef('OnLand', const [PropDef('actions', PropKind.actions, [])], (e, p) {
    e.landHandlers.add(() => e.runActions(p.list('actions')));
    return null;
  }),
  BehaviorDef('Parallax', const [
    PropDef('factorX', PropKind.number, 0.5),
    PropDef('factorY', PropKind.number, 0),
  ], (e, p) => _Parallax(Vector2(p.number('factorX'), p.number('factorY')))),
  BehaviorDef(
    'Move8',
    const [
      PropDef('speed', PropKind.number, 220),
      PropDef('keys', PropKind.choice, 'both', options: ['both', 'arrows', 'wasd']),
      PropDef('joystick', PropKind.bool, false),
      PropDef('turn', PropKind.bool, false),
      PropDef('bounded', PropKind.bool, true),
    ],
    (e, p) => _Move8(
      p.number('speed'),
      p.string('keys'),
      joystick: p.flag('joystick'),
      turn: p.flag('turn'),
      bounded: p.flag('bounded'),
    ),
  ),
  BehaviorDef('Health', const [
    PropDef('hp', PropKind.number, 3),
    PropDef('invulnerable', PropKind.number, 0.5),
    PropDef('variable', PropKind.string, ''),
    PropDef('hurt', PropKind.actions, []),
    PropDef('death', PropKind.actions, []),
  ], (e, p) => Health(p)),
  BehaviorDef('Follow', const [
    PropDef('target', PropKind.string, 'Player'),
    PropDef('speed', PropKind.number, 100),
    PropDef('stop', PropKind.number, 0),
    // Route around solid Tilemap tiles instead of heading straight for the target.
    PropDef('pathfind', PropKind.bool, false),
  ], (e, p) => _Follow(e, p.string('target'), p.number('speed'), p.number('stop'), pathfind: p.flag('pathfind'))),
  BehaviorDef('Patrol', const [
    // World points "x,y; x,y; …" visited in order.
    PropDef('points', PropKind.string, ''),
    PropDef('speed', PropKind.number, 100),
    PropDef('loop', PropKind.choice, 'loop', options: ['loop', 'pingpong', 'once']),
  ], (e, p) => _Patrol(parsePoints(p.string('points')), p.number('speed'), p.string('loop'))),
  BehaviorDef('Wander', const [
    PropDef('speed', PropKind.number, 60),
    PropDef('interval', PropKind.number, 1.5),
  ], (e, p) => _Wander(p.number('speed'), _minPeriod(p.number('interval')))),
  BehaviorDef('LookAt', const [
    PropDef('target', PropKind.string, 'Player'),
    PropDef('offset', PropKind.number, 0),
  ], (e, p) => _LookAt(p.string('target'), p.number('offset'))),
  BehaviorDef('OffScreen', const [
    PropDef('area', PropKind.choice, 'view', options: ['view', 'world']),
    PropDef('margin', PropKind.number, 0),
    PropDef('actions', PropKind.actions, []),
  ], (e, p) => _OffScreen(world: p.string('area') == 'world', margin: p.number('margin'), actions: p.list('actions'))),
];

var _rng = Random();

@visibleForTesting
void seedKilnRandom(int seed) => _rng = Random(seed);
Random get kilnRng => _rng;

/// Parses "idle:0-3, run:4-9, hit:10" into inclusive frame ranges clamped to [0, frames).
Map<String, (int, int)> parseClips(String spec, int frames) {
  final out = <String, (int, int)>{};
  if (frames < 1) return out;
  for (final part in spec.split(',')) {
    final m = RegExp(r'^\s*(\w+)\s*:\s*(\d+)\s*(?:-\s*(\d+))?\s*$').firstMatch(part);
    if (m == null) continue;
    final a = int.parse(m[2]!).clamp(0, frames - 1);
    final b = int.parse(m[3] ?? m[2]!).clamp(a, frames - 1);
    out[m[1]!] = (a, b);
  }
  return out.isEmpty ? {'default': (0, frames - 1)} : out;
}

/// Key names offered by OnKey.
const keyNames = [
  'Space', 'Enter', 'Escape', 'Tab', 'Shift', 'Control', 'Alt', //
  'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight',
  'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
  'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
];

final Map<String, LogicalKeyboardKey> _keys = {
  'Space': LogicalKeyboardKey.space,
  'Enter': LogicalKeyboardKey.enter,
  'Escape': LogicalKeyboardKey.escape,
  'Tab': LogicalKeyboardKey.tab,
  'Shift': LogicalKeyboardKey.shift,
  'Control': LogicalKeyboardKey.control,
  'Alt': LogicalKeyboardKey.alt,
  'ArrowUp': LogicalKeyboardKey.arrowUp,
  'ArrowDown': LogicalKeyboardKey.arrowDown,
  'ArrowLeft': LogicalKeyboardKey.arrowLeft,
  'ArrowRight': LogicalKeyboardKey.arrowRight,
  for (final k in keyNames.where((k) => k.length == 1))
    k: LogicalKeyboardKey.findKeyByKeyId(k.toLowerCase().codeUnitAt(0))!,
};

/// A missing image must not break the whole scene, so failures log and return null.
Future<Image?> loadKilnImage(KilnEntity e, String type, String src) async {
  if (src.isEmpty) return null;
  final images = e.game.images;
  try {
    // Not images.load: Flame's image cache leaks load errors as uncaught, so fetch and cache manually.
    if (!images.containsKey(src)) {
      final data = await images.bundle.load('${images.prefix}$src');
      images.add(src, await decodeImageFromList(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes)));
    }
    return images.fromCache(src);
  } catch (err) {
    debugPrint('kiln: $type "$src" on ${e.node.name}: $err');
    return null;
  }
}

List<String> _split(String s) => [
  for (final x in s.split('|'))
    if (x.trim().isNotEmpty) x.trim(),
];

// Zero/negative periods would make repeating timers spin.
double _minPeriod(double v) => v < 0.01 ? 0.01 : v;

final builtinActions = <ActionDef>[
  ActionDef(
    'AddVariable',
    const [PropDef('name', PropKind.string, 'score'), PropDef('value', PropKind.number, 1), ..._scopeProps],
    (self, a) => _writeVar(self, a, (cur) => (cur is num ? cur : 0) + a.number('value')),
    targeted: false,
  ),
  ActionDef(
    'SetVariable',
    const [PropDef('name', PropKind.string, 'score'), PropDef('value', PropKind.string, ''), ..._scopeProps],
    (self, a) => _writeVar(self, a, (_) => a['value']),
    targeted: false,
  ),
  ActionDef(
    'If',
    const [
      PropDef('expr', PropKind.string, '=score > 0'),
      PropDef('then', PropKind.actions, []),
      PropDef('else', PropKind.actions, []),
    ],
    (self, a) {
      // "=..." props arrive already evaluated; a bare formula is evaluated here.
      final v = a['expr'];
      final ok = truthy(v is String ? evalExpr(v, ExprScope(self.game, self, other: self.game.registry.other)) : v);
      self.runActions(a.list(ok ? 'then' : 'else'), other: self.game.registry.other);
    },
    targeted: false,
  ),
  ActionDef(
    'Log',
    const [PropDef('value', PropKind.string, '')],
    (self, a) => debugPrint('kiln: ${a['value']}'),
    targeted: false,
  ),
  ActionDef('SetState', const [PropDef('state', PropKind.string, '')], (self, a) {
    final m = self.children.whereType<StateMachine>().firstOrNull;
    m == null ? debugPrint('kiln: SetState on ${self.node.name}: no StateMachine') : m.go(a.string('state'));
  }),
  ActionDef(
    'SetTile',
    const [PropDef('c', PropKind.number, 0), PropDef('r', PropKind.number, 0), PropDef('tile', PropKind.number, 1)],
    (self, a) {
      final m = self.children.whereType<Tilemap>().firstOrNull;
      m == null
          ? debugPrint('kiln: SetTile on ${self.node.name}: no Tilemap')
          : m.setTile(a.number('c').floor(), a.number('r').floor(), a.number('tile').floor());
    },
  ),
  ActionDef(
    'FillTiles',
    const [
      PropDef('c', PropKind.number, 0),
      PropDef('r', PropKind.number, 0),
      PropDef('w', PropKind.number, 1),
      PropDef('h', PropKind.number, 1),
      PropDef('tile', PropKind.number, 0),
    ],
    (self, a) {
      final m = self.children.whereType<Tilemap>().firstOrNull;
      if (m == null) return debugPrint('kiln: FillTiles on ${self.node.name}: no Tilemap');
      final c0 = a.number('c').floor(), r0 = a.number('r').floor();
      for (var r = r0; r < r0 + min(a.number('h').floor(), m.rows); r++) {
        for (var c = c0; c < c0 + min(a.number('w').floor(), m.cols); c++) {
          m.setTile(c, r, a.number('tile').floor());
        }
      }
    },
  ),
  ActionDef('CameraShake', const [PropDef('strength', PropKind.number, 8), PropDef('time', PropKind.number, 0.3)], (
    self,
    a,
  ) {
    if (!self.game.editing) self.game.camera.viewport.add(_Shake(a.number('strength'), max(0.01, a.number('time'))));
  }, targeted: false),
  ..._dataActions,
  ActionDef(
    'Animate',
    const [
      PropDef('mode', PropKind.choice, 'restart', options: ['restart', 'pause', 'resume']),
    ],
    (self, a) {
      final an = self.animator;
      if (an == null) return debugPrint('kiln: Animate on ${self.node.name}: no Animator behavior');
      switch (a.string('mode')) {
        case 'pause':
          an.pause();
        case 'resume':
          an.resume();
        default:
          an.restart();
      }
    },
  ),
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
  }, targeted: false),
  ActionDef('LoadScene', const [PropDef('scene', PropKind.string, 'assets/scenes/level1.kiln.json')], (self, a) {
    final go = self.game.onLoadScene;
    go == null ? debugPrint('kiln: LoadScene("${a.string('scene')}") not supported here') : go(a.string('scene'));
  }, targeted: false),
  ActionDef(
    'Emit',
    // value: optional text sent with the event; "{name}" slots read variables.
    const [PropDef('event', PropKind.string, 'event'), PropDef('value', PropKind.string, '')],
    (self, a) => self.game.emit(
      a.string('event'),
      value: switch (a['value']) {
        null || '' => null,
        String s => fillTemplate(s, self.game.vars),
        final v => v, // a "=formula" result keeps its type
      },
    ),
    targeted: false,
  ),
  ActionDef(
    'ResetVariables',
    // Comma list; empty resets every variable this scene defines.
    const [PropDef('names', PropKind.string, '')],
    (self, a) => self.game.vars.reset(self.game.scene.variables, [
      for (final n in a.string('names').split(','))
        if (n.trim().isNotEmpty) n.trim(),
    ]),
    targeted: false,
  ),
  ActionDef('SetProp', const [
    PropDef(
      'prop',
      PropKind.choice,
      'x',
      options: ['x', 'y', 'angle', 'width', 'height', 'visible', 'vx', 'vy', 'spin'],
    ),
    PropDef('mode', PropKind.choice, 'set', options: ['set', 'add']),
    PropDef('value', PropKind.number, 0),
  ], (self, a) => _setProp(self, a.string('prop'), a.number('value'), add: a.string('mode') == 'add')),
  ActionDef(
    'Spawn',
    const [
      PropDef('prefab', PropKind.string, ''),
      PropDef('x', PropKind.number, 0),
      PropDef('y', PropKind.number, 0),
      PropDef('angle', PropKind.number, 0),
    ],
    (self, a) {
      // Offset and angle are relative to self, so a rotated shooter fires along its facing.
      final at = self.absolutePositionOf(self.size / 2 + Vector2(a.number('x'), a.number('y')));
      if (self.game.spawn(a.string('prefab'), at, angle: self.absoluteAngle + a.number('angle')) == null) {
        debugPrint('kiln: Spawn on ${self.node.name}: no prefab named "${a.string('prefab')}"');
      }
    },
  ),
  ActionDef('Jump', const [PropDef('force', PropKind.number, 600), PropDef('air', PropKind.bool, false)], (self, a) {
    final body = self.children.whereType<Body>().firstOrNull;
    if (body != null && (a.flag('air') || body.canJump)) body.jump(a.number('force'));
  }),
  ActionDef(
    'Shoot',
    const [
      PropDef('prefab', PropKind.string, 'Bullet'),
      PropDef('speed', PropKind.number, 600),
      PropDef('aim', PropKind.choice, 'facing', options: ['facing', 'target']),
      PropDef('at', PropKind.string, ''),
      PropDef('cooldown', PropKind.number, 0.2),
      PropDef('offset', PropKind.number, 20),
      PropDef('spread', PropKind.number, 0),
    ],
    (self, a) {
      final g = self.game, prefab = a.string('prefab');
      final key = 'shoot:$prefab';
      if (g.time < (self.readyAt[key] ?? 0)) return;
      self.readyAt[key] = g.time + a.number('cooldown');
      final aimed = a.string('aim') == 'target' ? g.nearest(self, a.string('at')) : null;
      var dir = aimed == null
          ? Vector2(cos(self.absoluteAngle), sin(self.absoluteAngle))
          : (aimed.absoluteCenter - self.absoluteCenter);
      if (dir.isZero()) dir = Vector2(1, 0);
      dir.normalize();
      // Spread: a random turn within ±spread/2 radians.
      if (a.number('spread') != 0) dir.rotate((_rng.nextDouble() - 0.5) * a.number('spread'));
      final shot = g.spawn(prefab, self.absoluteCenter + dir * a.number('offset'), angle: atan2(dir.y, dir.x));
      if (shot == null) return debugPrint('kiln: Shoot on ${self.node.name}: no prefab named "$prefab"');
      shot.launch = dir * a.number('speed');
    },
  ),
  ActionDef('Damage', const [PropDef('amount', PropKind.number, 1)], (self, a) {
    for (final h in self.children.whereType<Health>()) {
      h.damage(a.number('amount'));
    }
  }),
  ActionDef('Heal', const [PropDef('amount', PropKind.number, 1)], (self, a) {
    for (final h in self.children.whereType<Health>()) {
      h.heal(a.number('amount'));
    }
  }),
  ActionDef(
    'Burst',
    const [
      PropDef('count', PropKind.number, 12),
      PropDef('speed', PropKind.number, 140),
      PropDef('life', PropKind.number, 0.5),
      PropDef('size', PropKind.number, 3),
      PropDef('color', PropKind.color, '#E9C548'),
    ],
    (self, a) {
      final paint = Paint()..color = a.color('color');
      final speed = a.number('speed'), r = max(0.5, a.number('size'));
      self.game.world.add(
        ParticleSystemComponent(
          position: self.absoluteCenter,
          particle: Particle.generate(
            count: a.number('count').round().clamp(1, 500),
            lifespan: max(0.05, a.number('life')),
            generator: (i) => AcceleratedParticle(
              speed: (Vector2(1, 0)..rotate(_rng.nextDouble() * 2 * pi)) * (speed * (0.4 + _rng.nextDouble() * 0.6)),
              child: CircleParticle(radius: r, paint: paint),
            ),
          ),
        ),
      );
    },
  ),
  ActionDef(
    'Flip',
    const [
      PropDef('face', PropKind.choice, 'toggle', options: ['toggle', 'left', 'right']),
    ],
    (self, a) {
      final left = self.isFlippedHorizontally;
      final want = switch (a.string('face')) {
        'left' => true,
        'right' => false,
        _ => !left,
      };
      if (want != left) self.flipHorizontallyAroundCenter();
    },
  ),
  ActionDef('PlayAnim', const [PropDef('clip', PropKind.string, '')], (self, a) {
    for (final g in self.children.whereType<SpriteAnimationGroupComponent<String>>()) {
      if (g.animations?.containsKey(a.string('clip')) ?? false) g.current = a.string('clip');
    }
  }),
  ActionDef('PlayMusic', const [PropDef('file', PropKind.audio, '')], (self, a) {
    if (a.string('file').isNotEmpty) self.game.music(a.string('file'));
  }, targeted: false),
  ActionDef('StopMusic', const [], (self, a) => self.game.music(null), targeted: false),
  ActionDef(
    'SaveGame',
    // names: comma list of variables; empty saves them all.
    const [PropDef('slot', PropKind.string, 'save'), PropDef('names', PropKind.string, '')],
    (self, a) {
      final g = self.game, slot = a.string('slot');
      g.storage
          .write(slot, g.vars.snapshot(_names(a.string('names'))))
          .then((_) => g.emit('saved', value: slot))
          .catchError((Object err) => debugPrint('kiln: SaveGame "$slot": $err'));
    },
    targeted: false,
  ),
  ActionDef(
    'LoadGame',
    // Emits "loaded" (slot) when variables are back, or "loadfailed" when the slot is empty or unreadable.
    const [PropDef('slot', PropKind.string, 'save'), PropDef('names', PropKind.string, '')],
    (self, a) {
      final g = self.game, slot = a.string('slot'), names = _names(a.string('names'));
      g.storage
          .read(slot)
          .then((data) {
            if (data == null || data['variables'] is! Map) return g.emit('loadfailed', value: slot);
            g.vars.restore((data['variables'] as Map).cast<String, Object?>(), names);
            g.emit('loaded', value: slot);
          })
          .catchError((Object err) {
            debugPrint('kiln: LoadGame "$slot": $err');
            g.emit('loadfailed', value: slot);
          });
    },
    targeted: false,
  ),
];

List<String> _names(String s) => [
  for (final n in s.split(','))
    if (n.trim().isNotEmpty) n.trim(),
];

void _setProp(KilnEntity e, String prop, double v, {required bool add}) {
  double next(double cur) => add ? cur + v : v;
  Motion vel() => motionOf(e);
  switch (prop) {
    case 'x':
      e.x = next(e.x);
    case 'y':
      e.y = next(e.y);
    case 'angle':
      e.angle = next(e.angle);
    case 'width':
      e.width = max(0, next(e.width));
    case 'height':
      e.height = max(0, next(e.height));
    case 'visible':
      e.isVisible = next(e.isVisible ? 1 : 0) != 0;
    case 'vx':
      final l = vel();
      l.v.x = next(l.v.x);
    case 'vy':
      final l = vel();
      l.v.y = next(l.v.y);
    case 'spin':
      final l = vel();
      l.spin = next(l.spin);
  }
}

/// Kinematic platformer body: gravity, then axis-separated AABB moves against [Solid]s (angles ignored).
/// It is a [Motion], so SetProp vx/vy drive it and a separate Velocity is not needed.
class Body extends Motion {
  Body({required this.gravity, required this.maxFall, required this.friction, required this.coyote}) : super(0, 0, 0);

  final double gravity, maxFall, friction, coyote;
  bool onGround = false;
  double _air = double.infinity;

  /// Grounded, or left the ground less than [coyote] seconds ago.
  bool get canJump => _air <= coyote;

  void jump(double force) {
    v.y = -force;
    _air = double.infinity;
    onGround = false;
  }

  @override
  void update(double dt) {
    v.y = min(v.y + gravity * dt, maxFall);
    if (onGround && friction > 0) v.x = v.x.sign * max(0, v.x.abs() - friction * dt);
    final was = onGround;
    onGround = false;
    final d = v * dt;
    // Sub-steps keep fast bodies from tunnelling through thin solids.
    final steps = max(1, (max(d.x.abs(), d.y.abs()) / 8).ceil());
    for (var i = 0; i < steps; i++) {
      _move(0, d.x / steps);
      _move(1, d.y / steps);
    }
    _air = onGround ? 0 : _air + dt;
    if (onGround && !was) {
      for (final h in [...parent.landHandlers]) {
        h();
      }
    }
    parent.angle += spin * dt;
  }

  void _move(int axis, double delta) {
    if (delta == 0) return;
    final before = parent.toAbsoluteRect();
    axis == 0 ? parent.x += delta : parent.y += delta;
    for (final s in parent.game.solids) {
      if (s.parent == parent) continue;
      for (final r in s.hits(parent.toAbsoluteRect())) {
        final me = parent.toAbsoluteRect();
        if (!me.overlaps(r)) continue;
        if (axis == 0) {
          if (s.oneWay) continue;
          parent.x += delta > 0 ? r.left - me.right : r.right - me.left;
          v.x = 0;
        } else if (delta > 0) {
          // One-way platforms only stop bodies that were above them before this step.
          if (s.oneWay && before.bottom > r.top + 0.01) continue;
          parent.y += r.top - me.bottom;
          v.y = 0;
          onGround = true;
        } else if (!s.oneWay) {
          parent.y += r.bottom - me.top;
          v.y = 0;
        }
      }
    }
  }
}

class Solid extends Component with ParentIsA<KilnEntity> {
  Solid({required this.oneWay});

  final bool oneWay;

  /// Boxes (world space) that block bodies near [area]; a tilemap returns its solid cells.
  Iterable<Rect> hits(Rect area) => [parent.toAbsoluteRect()];

  @override
  void onMount() {
    super.onMount();
    parent.game.solids.add(this);
  }

  @override
  void onRemove() => parent.game.solids.remove(this);
}

/// Offsets its entity by the camera scroll × (1 − factor): 0 pins it to the screen (HUD), 1 is normal world.
class _Parallax extends Component with ParentIsA<KilnEntity> {
  _Parallax(this.factor);

  final Vector2 factor;
  Vector2 _base = Vector2.zero();

  // Runs after the whole tree updated, so it reads this frame's camera (no one-frame jitter).
  void _apply() {
    final cam = parent.game.camera.viewfinder.position;
    parent.position.setValues(_base.x + cam.x * (1 - factor.x), _base.y + cam.y * (1 - factor.y));
  }

  @override
  void onMount() {
    super.onMount();
    _base = parent.position.clone();
    parent.game.afterUpdate.add(_apply);
  }

  @override
  void onRemove() => parent.game.afterUpdate.remove(_apply);
}

/// Parses "x,y; x,y" into points; malformed pairs are skipped.
List<Vector2> parsePoints(String spec) => [
  for (final pair in spec.split(';'))
    if (pair.split(',').map((v) => double.tryParse(v.trim())).toList() case [final x?, final y?]) Vector2(x, y),
];

/// Hit points with a grace window after each hit; mirrors hp into a game variable when one is named.
class Health extends Component with ParentIsA<KilnEntity> {
  Health(Props p)
    : hp = max(1, p.number('hp')),
      maxHp = max(1, p.number('hp')),
      invulnerable = max(0, p.number('invulnerable')),
      variable = p.string('variable'),
      hurt = p.list('hurt'),
      death = p.list('death');

  double hp;
  final double maxHp, invulnerable;
  final String variable;
  final List<Object?> hurt, death;
  double _safeUntil = -1;

  bool get dead => hp <= 0;

  void _sync() {
    if (variable.isNotEmpty) parent.game.vars[variable] = hp;
  }

  @override
  void onMount() {
    super.onMount();
    _sync();
  }

  void damage(double n) {
    final g = parent.game;
    if (dead || n <= 0 || g.time < _safeUntil) return;
    hp = max(0, hp - n);
    _safeUntil = g.time + invulnerable;
    _sync();
    parent.runActions(dead ? death : hurt);
  }

  void heal(double n) {
    if (dead || n <= 0) return;
    hp = min(maxHp, hp + n);
    _sync();
  }
}

/// Keyboard (and optional on-screen joystick) steering at a fixed speed; `turn` faces the move direction.
class _Move8 extends Component with ParentIsA<KilnEntity> {
  _Move8(this.speed, String keys, {required this.joystick, required this.turn, required this.bounded})
    : _dirs = [
        if (keys != 'wasd') ...[
          (LogicalKeyboardKey.arrowLeft, -1, 0),
          (LogicalKeyboardKey.arrowRight, 1, 0),
          (LogicalKeyboardKey.arrowUp, 0, -1),
          (LogicalKeyboardKey.arrowDown, 0, 1),
        ],
        if (keys != 'arrows') ...[
          (LogicalKeyboardKey.keyA, -1, 0),
          (LogicalKeyboardKey.keyD, 1, 0),
          (LogicalKeyboardKey.keyW, 0, -1),
          (LogicalKeyboardKey.keyS, 0, 1),
        ],
      ];

  final double speed;
  final bool joystick, turn, bounded;
  final List<(LogicalKeyboardKey, int, int)> _dirs;

  // After movement this frame: keep the whole box inside the world.
  void _clamp() {
    final r = parent.toAbsoluteRect(), w = parent.game.scene.worldSize;
    final dx = r.left < 0 ? -r.left : (r.right > w.x ? w.x - r.right : 0.0);
    final dy = r.top < 0 ? -r.top : (r.bottom > w.y ? w.y - r.bottom : 0.0);
    if (dx != 0 || dy != 0) parent.position.add(Vector2(dx, dy));
  }

  JoystickComponent? _stick;

  @override
  void onMount() {
    super.onMount();
    final g = parent.game;
    if (g.editing) return;
    g.keyPollers++;
    if (bounded) g.afterUpdate.add(_clamp);
    if (joystick) {
      g.camera.viewport.add(
        _stick = JoystickComponent(
          knob: CircleComponent(radius: 22, paint: Paint()..color = const Color(0x99E8E6DC)),
          background: CircleComponent(radius: 56, paint: Paint()..color = const Color(0x33E8E6DC)),
          margin: const EdgeInsets.only(left: 36, bottom: 36),
        ),
      );
    }
  }

  @override
  void onRemove() {
    if (!parent.game.editing) parent.game.keyPollers--;
    parent.game.afterUpdate.remove(_clamp);
    _stick?.removeFromParent();
  }

  @override
  void update(double dt) {
    final g = parent.game;
    if (g.editing) return;
    final dir = Vector2.zero();
    for (final (k, x, y) in _dirs) {
      if (g.keysDown.contains(k)) dir.add(Vector2(x.toDouble(), y.toDouble()));
    }
    if (_stick case final s? when !s.relativeDelta.isZero()) dir.setFrom(s.relativeDelta);
    if (dir.length > 1) dir.normalize();
    motionOf(parent).v.setFrom(dir * speed);
    if (turn && !dir.isZero()) parent.angle = atan2(dir.y, dir.x);
  }
}

/// Steers toward the nearest [target] (name or #tag) until within [stop] pixels.
class _Follow extends Component with ParentIsA<KilnEntity> {
  _Follow(KilnEntity e, this.target, this.speed, this.stop, {required this.pathfind}) : _walker = PathWalker(e);

  final String target;
  final double speed, stop;
  final bool pathfind;
  final PathWalker _walker;

  @override
  void update(double dt) {
    final g = parent.game;
    if (g.editing) return;
    final t = g.nearest(parent, target);
    final m = g.tilemaps.firstOrNull;
    if (pathfind && m != null && t != null) {
      final reach = max(stop, 0.5);
      final near = t.absoluteCenter.distanceTo(parent.absoluteCenter) <= reach;
      motionOf(parent).v.setFrom(near ? Vector2.zero() : _walker.steer(m, t.absoluteCenter, 0.5, dt, speed) * speed);
      return;
    }
    final d = t == null ? Vector2.zero() : t.absoluteCenter - parent.absoluteCenter;
    motionOf(parent).v.setFrom(d.length > max(stop, 0.5) ? (d..normalize()) * speed : Vector2.zero());
  }
}

/// Walks between world points; `once` stops at the last one.
class _Patrol extends Component with ParentIsA<KilnEntity> {
  _Patrol(this.points, this.speed, this.mode);

  final List<Vector2> points;
  final double speed;
  final String mode;
  int _i = 0, _step = 1;

  @override
  void update(double dt) {
    if (parent.game.editing || points.isEmpty) return;
    final m = motionOf(parent);
    final d = points[_i] - parent.absoluteCenter;
    // Arrived (or would overshoot this frame): advance to the next point.
    if (d.length <= max(speed * dt, 0.5)) {
      parent.position.add(d); // land exactly on the point so legs don't drift
      if (points.length == 1 || (mode == 'once' && _i == points.length - 1)) {
        m.v.setZero();
        return;
      }
      if (mode == 'pingpong' && (_i + _step < 0 || _i + _step >= points.length)) _step = -_step;
      _i = (_i + _step) % points.length;
    }
    final to = points[_i] - parent.absoluteCenter;
    m.v.setFrom(to.isZero() ? Vector2.zero() : (to..normalize()) * speed);
  }
}

/// Picks a new random heading (or a pause) every [interval] seconds.
class _Wander extends Component with ParentIsA<KilnEntity> {
  _Wander(this.speed, this.interval);

  final double speed, interval;
  double _next = 0;

  @override
  void update(double dt) {
    final g = parent.game;
    if (g.editing || g.time < _next) return;
    _next = g.time + interval;
    // One in four turns is a pause, so wanderers don't look like billiard balls.
    motionOf(parent).v
        .setFrom(_rng.nextInt(4) == 0 ? Vector2.zero() : (Vector2(1, 0)..rotate(_rng.nextDouble() * 2 * pi)) * speed);
  }
}

/// Turns to face the nearest [target]; [offset] (radians) corrects art that doesn't point right.
class _LookAt extends Component with ParentIsA<KilnEntity> {
  _LookAt(this.target, this.offset);

  final String target;
  final double offset;

  @override
  void update(double dt) {
    final g = parent.game;
    if (g.editing) return;
    final t = g.nearest(parent, target);
    if (t == null) return;
    final d = t.absoluteCenter - parent.absoluteCenter;
    if (!d.isZero()) parent.angle = atan2(d.y, d.x) + offset;
  }
}

/// Two movers would both integrate position, so only the first Velocity/Body on an entity counts.
Motion? _oneMover(KilnEntity e, String type, Motion Function() make) {
  if (e.motion == null) return make();
  debugPrint('kiln: $type on ${e.node.name} ignored: the entity already has a Velocity or Body');
  return null;
}

/// The entity's mover, adding a still one if it has none. Pending ones count, so a frame never stacks two.
Motion motionOf(KilnEntity e) => e.motion ??= Motion(0, 0, 0)..addToParent(e);

/// Moves its entity each frame; `local` velocity is rotated by the entity's angle.
class Motion extends Component with ParentIsA<KilnEntity> {
  Motion(double vx, double vy, this.spin, {this.local = false}) : v = Vector2(vx, vy);

  final Vector2 v;
  double spin;
  final bool local;

  @override
  void update(double dt) {
    parent.position.add((local ? (v.clone()..rotate(parent.angle)) : v) * dt);
    parent.angle += spin * dt;
  }
}

class _OnEvent extends Component with ParentIsA<KilnEntity> {
  _OnEvent(this.event, this.store, this.actions);

  final String event, store;
  final List<Object?> actions;
  VoidCallback? _off;

  @override
  void onMount() {
    super.onMount();
    if (parent.game.editing) return;
    _off = parent.game.on(event, (value) {
      if (store.isNotEmpty) parent.game.vars[store] = value;
      parent.runActions(actions);
    });
  }

  @override
  void onRemove() => _off?.call();
}

class _OnKey extends Component with ParentIsA<KilnEntity> {
  _OnKey(this.logical, this.when, this.actions);

  final LogicalKeyboardKey? logical;
  final String when;
  final List<Object?> actions;
  bool _held = false;

  bool _matches(LogicalKeyboardKey k) => k == logical || k.synonyms.contains(logical);

  void _onKey(KeyEvent ev) {
    if (!_matches(ev.logicalKey)) return;
    switch (ev) {
      case KeyDownEvent():
        _held = true;
        if (when == 'down') parent.runActions(actions);
      case KeyUpEvent():
        _held = false;
        if (when == 'up') parent.runActions(actions);
      default:
    }
  }

  @override
  void update(double dt) {
    if (_held && when == 'held') parent.runActions(actions);
  }

  @override
  void onMount() {
    super.onMount();
    if (logical != null && !parent.game.editing) parent.game.keyListeners.add(_onKey);
  }

  @override
  void onRemove() => parent.game.keyListeners.remove(_onKey);
}

/// Scrolls the view to keep its entity inside a centered deadzone; `clamp` keeps the view inside the world.
class _Camera extends Component with ParentIsA<KilnEntity> {
  // Updates after sibling movers so the view never lags a frame behind.
  _Camera(this.deadzone, {required this.clamp}) : super(priority: 1 << 30);

  final Vector2 deadzone;
  final bool clamp;

  void _follow({bool snap = false}) {
    final g = parent.game;
    final view = g.scene.size;
    final at = g.camera.viewfinder.position.clone();
    final c = parent.absoluteCenter;
    final dz = snap ? Vector2.zero() : deadzone;
    for (final i in [0, 1]) {
      final lo = at[i] + (view[i] - dz[i]) / 2, hi = lo + dz[i];
      if (c[i] < lo) at[i] -= lo - c[i];
      if (c[i] > hi) at[i] += c[i] - hi;
      if (clamp) at[i] = at[i].clamp(0, max(0, g.scene.worldSize[i] - view[i]));
    }
    g.camera.viewfinder.position = at;
  }

  @override
  void onMount() {
    super.onMount();
    if (!parent.game.editing) _follow(snap: true);
  }

  @override
  void update(double dt) {
    if (!parent.game.editing) _follow();
  }
}

/// Runs actions once each time the entity's box leaves the view (or world), grown by [margin].
class _OffScreen extends Component with ParentIsA<KilnEntity> {
  _OffScreen({required this.world, required this.margin, required this.actions});

  final bool world;
  final double margin;
  final List<Object?> actions;

  /// Starts "out" so things spawned off-screen (incoming enemies) fire only after they enter and leave.
  bool _out = true;

  @override
  void update(double dt) {
    final g = parent.game;
    if (g.editing) return;
    final origin = world ? Vector2.zero() : g.camera.viewfinder.position;
    final size = world ? g.scene.worldSize : g.scene.size;
    final area = Rect.fromLTWH(origin.x, origin.y, size.x, size.y).inflate(margin);
    final out = !area.overlaps(parent.toAbsoluteRect());
    if (out && !_out) parent.runActions(actions);
    _out = out;
  }
}

/// Runs actions once each time the comparison turns true (edge-triggered, not every frame).
class _Condition extends Component {
  _Condition(this.e, this.p);

  final KilnEntity e;
  final Props p;
  bool _was = false;

  bool _test() {
    // Props resolve "=..." only inside actions, so a behavior formula is evaluated here.
    final src = p.string('expr').replaceFirst(RegExp(r'^\s*='), '');
    if (src.isNotEmpty) return truthy(evalExpr(src, ExprScope(e.game, e)));
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
  void update(double dt) {
    if (!e.game.editing && p.string('check') == 'frame') _check();
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

  void _refresh() => text = fillTemplate(template, game.vars);

  @override
  void onMount() {
    _refresh();
    game.vars.addListener(_refresh);
  }

  @override
  void onRemove() => game.vars.removeListener(_refresh);
}

/// Cap on loop passes per Repeat/ForEach call so a bad count cannot freeze the game.
const _maxLoop = 10000;

void _loop(KilnEntity self, Props a, int n, Map<String, Object?> Function(int i) locals) {
  if (n > _maxLoop) debugPrint('kiln: loop of $n passes cut to $_maxLoop');
  final reg = self.game.registry, body = a.list('actions');
  for (var i = 0; i < min(n, _maxLoop); i++) {
    reg.withLocals(locals(i), () => self.runActions(body, other: reg.other));
  }
}

/// Edits the list variable [name] by assigning a new list.
void _editList(KilnEntity self, Props a, void Function(List<Object?> l) edit) {
  final name = a.string('name');
  final l = [...self.game.vars.list(name)];
  edit(l);
  self.game.vars[name] = l;
}

int? _at(Props a, int length) {
  final i = a.number('index').floor();
  return i >= 0 && i < length ? i : null;
}

final _dataActions = <ActionDef>[
  ActionDef(
    'ListAdd',
    const [
      PropDef('name', PropKind.string, 'items'),
      PropDef('value', PropKind.string, ''),
      // -1 appends.
      PropDef('index', PropKind.number, -1),
    ],
    (self, a) => _editList(self, a, (l) {
      final i = a.number('index').floor();
      l.insert(i >= 0 && i <= l.length ? i : l.length, a['value']);
    }),
    targeted: false,
  ),
  ActionDef(
    'ListRemove',
    const [PropDef('name', PropKind.string, 'items'), PropDef('index', PropKind.number, 0)],
    (self, a) => _editList(self, a, (l) {
      if (_at(a, l.length) case final i?) l.removeAt(i);
    }),
    targeted: false,
  ),
  ActionDef(
    'ListSet',
    const [
      PropDef('name', PropKind.string, 'items'),
      PropDef('index', PropKind.number, 0),
      PropDef('value', PropKind.string, ''),
    ],
    (self, a) => _editList(self, a, (l) {
      if (_at(a, l.length) case final i?) l[i] = a['value'];
    }),
    targeted: false,
  ),
  ActionDef(
    'ListClear',
    const [PropDef('name', PropKind.string, 'items')],
    (self, a) => _editList(self, a, (l) => l.clear()),
    targeted: false,
  ),
  ActionDef(
    'MapSet',
    const [
      PropDef('name', PropKind.string, 'table'),
      PropDef('key', PropKind.string, ''),
      PropDef('value', PropKind.string, ''),
    ],
    (self, a) =>
        self.game.vars[a.string('name')] = {...self.game.vars.map(a.string('name')), a.string('key'): a['value']},
    targeted: false,
  ),
  ActionDef(
    'Repeat',
    const [PropDef('count', PropKind.number, 3), PropDef('actions', PropKind.actions, [])],
    (self, a) => _loop(self, a, a.number('count').floor(), (i) => {'i': i.toDouble()}),
    targeted: false,
  ),
  ActionDef(
    'ForEach',
    // list: name of a list variable (or a "=formula" giving a list); runs once per item with `item` and `i`.
    const [PropDef('list', PropKind.string, 'items'), PropDef('actions', PropKind.actions, [])],
    (self, a) {
      final src = a['list'];
      final l = src is List ? src : self.game.vars.list('$src');
      _loop(self, a, l.length, (i) => {'item': l[i], 'i': i.toDouble()});
    },
    targeted: false,
  ),
];

// global = game variable; self / target = entity variables (`entity` names the target: name, #tag or other).
const _scopeProps = [
  PropDef('scope', PropKind.choice, 'global', options: ['global', 'self', 'target']),
  PropDef('entity', PropKind.string, ''),
];

void _writeVar(KilnEntity self, Props a, Object? Function(Object? cur) next) {
  final name = a.string('name');
  switch (a.string('scope')) {
    case 'self':
      self.vars[name] = next(self.vars[name]);
    case 'target':
      for (final t in self.game.targets(self, a.string('entity'), other: self.game.registry.other)) {
        t.vars[name] = next(t.vars[name]);
      }
    default:
      self.game.vars[name] = next(self.game.vars[name]);
  }
}

/// States with enter/update/exit action lists and `when`-guarded transitions; the current state is `self.state`
/// (and `self.stateTime` seconds) in formulas. Only one transition fires per frame.
class StateMachine extends Component with ParentIsA<KilnEntity> {
  StateMachine(Props p)
    : _states = {
        for (final s in p.list('states'))
          if (s is Map<String, Object?>) '${s['name']}': Props(s),
      },
      _transitions = p.list('transitions'),
      _initial = p.string('initial');

  final Map<String, Props> _states;
  final List<Object?> _transitions;
  final String _initial;
  String state = '';

  @override
  void onMount() {
    super.onMount();
    if (parent.game.editing) return;
    go(_initial.isNotEmpty ? _initial : (_states.keys.firstOrNull ?? ''));
  }

  void go(String to) {
    if (!_states.containsKey(to)) return debugPrint('kiln: StateMachine on ${parent.node.name}: no state "$to"');
    if (_states[state] case final s?) parent.runActions(s.list('exit'));
    state = to;
    parent.vars
      ..['state'] = to
      ..['stateTime'] = 0.0;
    parent.runActions(_states[to]!.list('enter'));
  }

  @override
  void update(double dt) {
    if (parent.game.editing || state.isEmpty) return;
    parent.vars['stateTime'] = (parent.vars['stateTime'] as num? ?? 0) + dt;
    parent.runActions(_states[state]?.list('update') ?? const []);
    for (final raw in _transitions) {
      final t = Props(raw is Map<String, Object?> ? raw : const {});
      final from = t.string('from');
      if (from.isNotEmpty && from != '*' && from != state) continue;
      final src = t.string('when').replaceFirst(RegExp(r'^\s*='), '');
      if (src.isNotEmpty && truthy(evalExpr(src, ExprScope(parent.game, parent)))) {
        return go(t.string('to'));
      }
    }
  }
}

/// Offsets the viewport by a decaying random amount, then puts it back.
class _Shake extends Component {
  _Shake(this.strength, this.time);

  final double strength, time;
  late final Vector2 _base;
  late final Viewport _view;
  double _t = 0;

  @override
  void onMount() {
    super.onMount();
    _view = parent! as Viewport;
    _base = _view.position.clone();
  }

  @override
  void update(double dt) {
    _t += dt;
    final double k = 1.0 - min(1.0, _t / time);
    _view.position = _base + Vector2((_rng.nextDouble() - 0.5) * 2, (_rng.nextDouble() - 0.5) * 2) * strength * k;
    if (_t >= time) {
      _view.position = _base;
      removeFromParent();
    }
  }
}
