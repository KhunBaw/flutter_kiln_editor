import 'dart:async';
import 'dart:convert';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/cache.dart';
import 'package:flame/game.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'builtins.dart';
import 'controller.dart';
import 'registry.dart';
import 'scene.dart';

class GameVariables extends ChangeNotifier {
  GameVariables(Map<String, Object?> initial) : _values = {...initial};

  final Map<String, Object?> _values;

  Object? operator [](String key) => _values[key];

  void operator []=(String key, Object? value) {
    if (_values[key] == value) return;
    _values[key] = value;
    notifyListeners();
  }

  // Type-safe reads: a missing or wrong-typed value falls back instead of throwing.
  double number(String key) => switch (_values[key]) {
    num v => v.toDouble(),
    _ => 0,
  };
  String string(String key) => switch (_values[key]) {
    null => '',
    final v => '$v',
  };
  bool flag(String key) => _values[key] == true;

  /// Adds [defaults] for keys not set yet (a new scene's variables on shared state).
  void seed(Map<String, Object?> defaults) {
    var changed = false;
    for (final MapEntry(:key, :value) in defaults.entries) {
      if (_values.containsKey(key)) continue;
      _values[key] = value;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Puts [names] (all of [defaults] when empty) back to their [defaults].
  void reset(Map<String, Object?> defaults, [Iterable<String> names = const []]) {
    for (final k in names.isEmpty ? defaults.keys : names) {
      if (defaults.containsKey(k)) _values[k] = defaults[k];
    }
    notifyListeners();
  }
}

final _slot = RegExp(r'\{(\w+)\}');

/// Fills "{name}" slots with variable values; whole doubles print without ".0".
String fillTemplate(String template, GameVariables vars) => template.replaceAllMapped(_slot, (m) {
  final v = vars[m[1]!];
  return switch (v) {
    double d when d == d.roundToDouble() => d.toInt().toString(),
    _ => '${v ?? ''}',
  };
});

/// Plays a [SceneDoc]. Scene coordinates map 1:1 to a fixed-resolution camera (top-left origin).
class KilnGame extends FlameGame with HasCollisionDetection, KeyboardEvents {
  /// [bundle] overrides where images load from (the editor reads the project folder); [playSound]/[playMusic] override audio.
  KilnGame(
    this.scene, {
    KilnRegistry? registry,
    this.editing = false,
    this.onLoadScene,
    this.playSound,
    this.playMusic,
    this.onEmit,
    GameVariables? vars,
    AssetBundle? bundle,
  }) : registry = registry ?? KilnRegistry(),
       // Shared vars (kept across scenes) only gain this scene's missing defaults.
       vars = vars == null ? GameVariables(scene.variables) : (vars..seed(scene.variables)),
       super(
         camera: CameraComponent.withFixedResolution(width: scene.size.x, height: scene.size.y),
       ) {
    if (bundle != null) images = Images(bundle: bundle);
  }

  final SceneDoc scene;
  final KilnRegistry registry;
  final GameVariables vars;

  /// Editor preview: time is frozen (no timers/tweens/spawns) and prefabs stay visible.
  final bool editing;

  /// Called by the LoadScene action with the target scene asset.
  final void Function(String scene)? onLoadScene;

  /// Called by the PlaySound action with a file name under `assets/audio/`; defaults to FlameAudio.
  final void Function(String file)? playSound;

  /// Called by PlayMusic with a file under `assets/audio/` (looping), and with null to stop; defaults to FlameAudio.bgm.
  final void Function(String? file)? playMusic;
  bool musicOn = false;

  /// Every Emit, passed out to the app (see KilnController.events).
  final void Function(String event, Object? value)? onEmit;

  final Map<String, Set<void Function(Object? value)>> _events = {};
  int _emitDepth = 0;
  final Set<void Function(KeyEvent event)> keyListeners = {};

  /// Keys held right now, and how many behaviors read them each frame (Move8).
  Set<LogicalKeyboardKey> keysDown = {};
  int keyPollers = 0;

  /// Run once per frame after every component updated (camera-relative placement).
  final Set<VoidCallback> afterUpdate = {};

  /// Static colliders that Body behaviors move against.
  final Set<Solid> solids = {};
  int _spawned = 0;

  /// Top-level entities with a Prefab behavior, by name; hidden at play time and cloned by Spawner.
  late final Map<String, EntityNode> prefabs = {
    for (final e in scene.entities)
      if (e.behaviors.any((b) => b.type == 'Prefab')) e.name: e,
  };

  @override
  Future<void> onLoad() async {
    camera.viewfinder.anchor = Anchor.topLeft;
    final hidden = editing ? const <EntityNode>{} : prefabs.values.toSet();
    await world.addAll(scene.entities.where((e) => !hidden.contains(e)).map(KilnEntity.new));
  }

  @override
  void updateTree(double dt) {
    if (!editing) time += dt;
    super.updateTree(editing ? 0 : dt);
    for (final f in [...afterUpdate]) {
      f();
    }
  }

  @override
  void onRemove() {
    if (musicOn) music(null);
    super.onRemove();
  }

  void music(String? file) {
    musicOn = file != null;
    final hook = playMusic;
    if (hook != null) return hook(file);
    if (file == null) {
      FlameAudio.bgm.stop();
    } else {
      FlameAudio.bgm.play(file).catchError((Object err) => debugPrint('kiln: PlayMusic "$file": $err'));
    }
  }

  /// Seconds of play so far (frozen while editing).
  double time = 0;

  /// Entities an action addresses: empty/`self` → [self], `other` → the collision partner, `#tag` → tagged, else by name.
  List<KilnEntity> targets(KilnEntity self, String target, {KilnEntity? other}) {
    if (target.isEmpty || target == 'self') return [self];
    if (target == 'other') return [?other];
    final all = world.descendants().whereType<KilnEntity>().where((e) => !e.isRemoving);
    return target.startsWith('#')
        ? all.where((e) => e.node.tags.contains(target.substring(1))).toList()
        : all.where((e) => e.node.name == target).toList();
  }

  /// Closest entity [target] addresses (name or #tag), excluding [self].
  KilnEntity? nearest(KilnEntity self, String target) {
    KilnEntity? best;
    var bestD = double.infinity;
    for (final e in targets(self, target)) {
      if (e == self) continue;
      final d = e.absoluteCenter.distanceToSquared(self.absoluteCenter);
      if (d < bestD) (best, bestD) = (e, d);
    }
    return best;
  }

  VoidCallback on(String event, void Function(Object? value) handler) {
    _events.putIfAbsent(event, () => {}).add(handler);
    return () => _events[event]?.remove(handler);
  }

  /// Runs OnEvent listeners for [event] and tells the app ([onEmit]); inert while editing.
  void emit(String event, {Object? value}) {
    if (editing) return;
    // Guards against handlers that re-emit their own event forever.
    if (_emitDepth > 16) return debugPrint('kiln: Emit("$event") nested too deep, dropped');
    _emitDepth++;
    try {
      onEmit?.call(event, value);
      for (final h in [...?_events[event]]) {
        h(value);
      }
    } finally {
      _emitDepth--;
    }
  }

  /// Clones prefab [name] into the world at [at] (world space); null when there is no such prefab.
  KilnEntity? spawn(String name, Vector2 at, {double angle = 0}) {
    final node = prefabs[name];
    if (node == null) return null;
    _spawned++;
    final clone = EntityNode.fromJson(node.toJson())
      ..id = '${node.id}#$_spawned'
      ..position = at
      ..angle = angle;
    final e = KilnEntity(clone);
    world.add(e);
    return e;
  }

  @override
  KeyEventResult onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    if (editing) return KeyEventResult.ignored;
    keysDown = {...keysPressed};
    if (keyListeners.isEmpty && keyPollers == 0) return KeyEventResult.ignored;
    for (final l in [...keyListeners]) {
      l(event);
    }
    return KeyEventResult.handled;
  }
}

class KilnEntity extends PositionComponent
    with HasGameReference<KilnGame>, HasVisibility, TapCallbacks, CollisionCallbacks {
  KilnEntity(this.node)
    : super(position: node.position.clone(), size: node.size.clone(), angle: node.angle, anchor: Anchor.center);

  final EntityNode node;
  final List<VoidCallback> tapHandlers = [];
  final List<void Function(KilnEntity other)> collideHandlers = [];
  final List<VoidCallback> landHandlers = [];

  /// The entity's one mover (Velocity, Body, or one added by an action), set before it mounts.
  Motion? motion;

  /// Initial world velocity for a spawned projectile; applied to [motion] once behaviors load.
  Vector2? launch;

  /// Next game time each cooldown key (e.g. a Shoot prefab) is ready again.
  final Map<String, double> readyAt = {};

  @override
  Future<void> onLoad() async {
    for (final b in node.behaviors) {
      final def = game.registry.behaviors[b.type];
      if (def == null) {
        debugPrint('kiln: unknown behavior "${b.type}" on ${node.name}');
        continue;
      }
      final c = await def.create(this, Props(b.props).withDefaults(def.props));
      if (c is Motion) motion ??= c;
      if (c != null) await add(c);
    }
    if (launch case final v?) motionOf(this).v.setFrom(v);
    await addAll(node.children.map(KilnEntity.new));
  }

  /// [other] is the entity on the far side of a collision; actions can target it as `other`.
  void runActions(List<Object?> actions, {KilnEntity? other}) => game.registry.runActions(this, actions, other: other);

  @override
  void onTapDown(TapDownEvent event) {
    // Let taps fall through entities that have no OnTap behavior.
    if (tapHandlers.isEmpty) {
      event.continuePropagation = true;
      return;
    }
    for (final h in [...tapHandlers]) {
      h();
    }
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is! KilnEntity) return;
    for (final h in [...collideHandlers]) {
      h(other);
    }
  }
}

/// Embed point for apps: loads a `.kiln.json` asset and runs it.
/// Give it a [controller] to read variables, send events and change scenes from the app.
class KilnGameWidget extends StatefulWidget {
  const KilnGameWidget({super.key, required this.asset, this.registry, this.controller, this.onEvent});

  final String asset;
  final KilnRegistry? registry;
  final KilnController? controller;

  /// Shortcut for listening to [KilnController.events].
  final void Function(String event, Object? value)? onEvent;

  @override
  State<KilnGameWidget> createState() => _KilnGameWidgetState();
}

class _KilnGameWidgetState extends State<KilnGameWidget> {
  late final KilnController _c = widget.controller ?? KilnController();
  late String _asset = widget.asset;
  late Future<KilnGame> _game;
  StreamSubscription<KilnEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _c.attach(_goTo);
    _sub = _c.events.listen((e) => widget.onEvent?.call(e.name, e.value));
    _game = _load();
  }

  Future<KilnGame> _load() {
    final asset = _asset;
    return rootBundle
        .loadString(asset)
        .then((s) => _c.createGame(SceneDoc.fromJson(jsonDecode(s)), asset, registry: widget.registry));
  }

  void _goTo(String asset) => setState(() {
    _asset = asset;
    _game = _load();
  });

  @override
  void dispose() {
    _sub?.cancel();
    _c.attach(null);
    if (widget.controller == null) _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _game,
    builder: (context, snap) => switch (snap) {
      AsyncSnapshot(:final data?) => GameWidget(key: ObjectKey(data), game: data),
      AsyncSnapshot(:final error?) => Center(child: Text('Failed to load $_asset: $error')),
      _ => const SizedBox.shrink(),
    },
  );
}
