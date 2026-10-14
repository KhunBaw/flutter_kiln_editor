import 'dart:math';
import 'dart:ui' show Image;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import 'game.dart';
import 'registry.dart';

final builtinBehaviors = <BehaviorDef>[
  BehaviorDef('Shape', const [
    PropDef('shape', PropKind.choice, 'rect', options: ['rect', 'oval']),
    PropDef('color', PropKind.color, '#4488FF'),
  ], (e, p) => _Shape(oval: p.string('shape') == 'oval', paint: Paint()..color = p.color('color'))),
  BehaviorDef('Sprite', const [PropDef('image', PropKind.image, '')], (e, p) async {
    final img = await _image(e, 'Sprite', p.string('image'));
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
      final img = await _image(e, 'SpriteAnimation', p.string('image'));
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
  BehaviorDef('OnEvent', const [
    PropDef('event', PropKind.string, 'event'),
    PropDef('actions', PropKind.actions, []),
  ], (e, p) => _OnEvent(p.string('event'), p.list('actions'))),
  BehaviorDef('OnKey', const [
    PropDef('key', PropKind.choice, 'Space', options: keyNames),
    PropDef('on', PropKind.choice, 'down', options: ['down', 'up', 'held']),
    PropDef('actions', PropKind.actions, []),
  ], (e, p) => _OnKey(_keys[p.string('key')], p.string('on'), p.list('actions'))),
  BehaviorDef('Velocity', const [
    PropDef('vx', PropKind.number, 0),
    PropDef('vy', PropKind.number, 0),
    PropDef('spin', PropKind.number, 0),
    PropDef('space', PropKind.choice, 'world', options: ['world', 'local']),
  ], (e, p) => Motion(p.number('vx'), p.number('vy'), p.number('spin'), local: p.string('space') == 'local')),
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
    (e, p) => Body(
      gravity: p.number('gravity'),
      maxFall: p.number('maxFall'),
      friction: p.number('friction'),
      coyote: p.number('coyote'),
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
  BehaviorDef('OffScreen', const [
    PropDef('area', PropKind.choice, 'view', options: ['view', 'world']),
    PropDef('margin', PropKind.number, 0),
    PropDef('actions', PropKind.actions, []),
  ], (e, p) => _OffScreen(world: p.string('area') == 'world', margin: p.number('margin'), actions: p.list('actions'))),
];

final _rng = Random();

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
Future<Image?> _image(KilnEntity e, String type, String src) async {
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
  }, targeted: false),
  ActionDef(
    'SetVariable',
    const [PropDef('name', PropKind.string, 'score'), PropDef('value', PropKind.string, '')],
    (self, a) => self.game.vars[a.string('name')] = a['value'],
    targeted: false,
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
    const [PropDef('event', PropKind.string, 'event')],
    (self, a) => self.game.emit(a.string('event')),
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
];

void _setProp(KilnEntity e, String prop, double v, {required bool add}) {
  double next(double cur) => add ? cur + v : v;
  // A pending (not yet mounted) Motion counts too, so repeated calls in one frame never stack two.
  Motion vel() => e.children.whereType<Motion>().firstOrNull ?? (e.motion ??= Motion(0, 0, 0)..addToParent(e));
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
      final me = parent.toAbsoluteRect(), r = s.parent.toAbsoluteRect();
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

class Solid extends Component with ParentIsA<KilnEntity> {
  Solid({required this.oneWay});

  final bool oneWay;

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
  _OnEvent(this.event, this.actions);

  final String event;
  final List<Object?> actions;
  VoidCallback? _off;

  @override
  void onMount() {
    super.onMount();
    if (!parent.game.editing) _off = parent.game.on(event, () => parent.runActions(actions));
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

/// Runs actions once when the entity's box stops overlapping the view (or world), grown by [margin].
class _OffScreen extends Component with ParentIsA<KilnEntity> {
  _OffScreen({required this.world, required this.margin, required this.actions});

  final bool world;
  final double margin;
  final List<Object?> actions;
  bool _out = false;

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
