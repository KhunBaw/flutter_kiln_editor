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
}

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
    AssetBundle? bundle,
  }) : registry = registry ?? KilnRegistry(),
       vars = GameVariables(scene.variables),
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

  final Map<String, Set<VoidCallback>> _events = {};
  int _emitDepth = 0;
  final Set<void Function(KeyEvent event)> keyListeners = {};

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

  /// Entities an action addresses: empty/`self` → [self], `#tag` → tagged, else by name.
  List<KilnEntity> targets(KilnEntity self, String target) {
    if (target.isEmpty || target == 'self') return [self];
    final all = world.descendants().whereType<KilnEntity>().where((e) => !e.isRemoving);
    return target.startsWith('#')
        ? all.where((e) => e.node.tags.contains(target.substring(1))).toList()
        : all.where((e) => e.node.name == target).toList();
  }

  VoidCallback on(String event, VoidCallback handler) {
    _events.putIfAbsent(event, () => {}).add(handler);
    return () => _events[event]?.remove(handler);
  }

  void emit(String event) {
    // Guards against handlers that re-emit their own event forever.
    if (_emitDepth > 16) return debugPrint('kiln: Emit("$event") nested too deep, dropped');
    _emitDepth++;
    try {
      for (final h in [...?_events[event]]) {
        h();
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
    if (editing || keyListeners.isEmpty) return KeyEventResult.ignored;
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

  /// Set when an action adds a Motion at runtime, before it mounts.
  Motion? motion;

  @override
  Future<void> onLoad() async {
    for (final b in node.behaviors) {
      final def = game.registry.behaviors[b.type];
      if (def == null) {
        debugPrint('kiln: unknown behavior "${b.type}" on ${node.name}');
        continue;
      }
      final c = await def.create(this, Props(b.props).withDefaults(def.props));
      if (c != null) await add(c);
    }
    await addAll(node.children.map(KilnEntity.new));
  }

  void runActions(List<Object?> actions) => game.registry.runActions(this, actions);

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
class KilnGameWidget extends StatefulWidget {
  const KilnGameWidget({super.key, required this.asset, this.registry});

  final String asset;
  final KilnRegistry? registry;

  @override
  State<KilnGameWidget> createState() => _KilnGameWidgetState();
}

class _KilnGameWidgetState extends State<KilnGameWidget> {
  late String _asset = widget.asset;
  late Future<KilnGame> _game = _load();

  Future<KilnGame> _load() => rootBundle
      .loadString(_asset)
      .then((s) => KilnGame(SceneDoc.fromJson(jsonDecode(s)), registry: widget.registry, onLoadScene: _goTo));

  void _goTo(String asset) => setState(() {
    _asset = asset;
    _game = _load();
  });

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
