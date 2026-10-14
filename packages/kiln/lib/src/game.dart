import 'dart:convert';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/cache.dart';
import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

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
class KilnGame extends FlameGame with HasCollisionDetection {
  /// [bundle] overrides where images load from (the editor reads the project folder); [playSound] overrides audio.
  KilnGame(
    this.scene, {
    KilnRegistry? registry,
    this.editing = false,
    this.onLoadScene,
    this.playSound,
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
  void updateTree(double dt) => super.updateTree(editing ? 0 : dt);
}

class KilnEntity extends PositionComponent with HasGameReference<KilnGame>, TapCallbacks, CollisionCallbacks {
  KilnEntity(this.node)
    : super(position: node.position.clone(), size: node.size.clone(), angle: node.angle, anchor: Anchor.center);

  final EntityNode node;
  final List<VoidCallback> tapHandlers = [];
  final List<void Function(KilnEntity other)> collideHandlers = [];

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
