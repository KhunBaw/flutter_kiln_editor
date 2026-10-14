import 'dart:async';

import 'package:flutter/foundation.dart';

import 'game.dart';
import 'registry.dart';
import 'scene.dart';

/// Something a scene's Emit action sent out to the app.
class KilnEvent {
  const KilnEvent(this.name, this.value);

  final String name;
  final Object? value;

  @override
  String toString() => 'KilnEvent($name, $value)';
}

/// The app's handle on a running Kiln game: variables, two-way events and scene changes.
/// Pass it to [KilnGameWidget]; notifies when the running game (scene) changes.
class KilnController extends ChangeNotifier {
  /// [variables] override the scene's starting values. With [keepVariables] one set of variables
  /// lives across LoadScene (each new scene only adds its missing defaults; use ResetVariables to restart).
  KilnController({Map<String, Object?> variables = const {}, this.keepVariables = false}) : _overrides = {...variables};

  final bool keepVariables;
  final Map<String, Object?> _overrides;
  final _events = StreamController<KilnEvent>.broadcast();
  GameVariables? _shared;
  KilnGame? _game;
  String? _scene;
  void Function(String asset)? _loader;

  KilnGame? get game => _game;

  /// Asset path of the running scene.
  String? get scene => _scene;

  /// The running game's variables (before the first scene loads: the app's starting values).
  GameVariables get vars => _game?.vars ?? (_shared ??= GameVariables(_overrides));

  /// Every Emit from the scene (game → app).
  Stream<KilnEvent> get events => _events.stream;

  /// Sends [event] into the game (app → game); OnEvent behaviors react, `store` keeps [value].
  void emit(String event, [Object? value]) => _game?.emit(event, value: value);

  /// Switches scene like the LoadScene action.
  void loadScene(String asset) {
    final load = _loader;
    load == null ? debugPrint('kiln: loadScene("$asset") before a KilnGameWidget attached') : load(asset);
  }

  /// Wired by [KilnGameWidget]; apps don't call this.
  void attach(void Function(String asset)? loader) => _loader = loader;

  /// Builds the game for [doc]; used by [KilnGameWidget].
  KilnGame createGame(SceneDoc doc, String asset, {KilnRegistry? registry}) {
    final vars = keepVariables
        ? (_shared ??= GameVariables(_overrides))
        : GameVariables({...doc.variables, ..._overrides});
    final g = KilnGame(
      doc,
      registry: registry,
      vars: vars,
      onLoadScene: loadScene,
      onEmit: (name, value) => _events.add(KilnEvent(name, value)),
    );
    _game = g;
    _scene = asset;
    notifyListeners();
    return g;
  }

  @override
  void dispose() {
    _events.close();
    super.dispose();
  }
}
