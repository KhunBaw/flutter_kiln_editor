import 'dart:async';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';

import 'builtins.dart';
import 'game.dart';

/// `image`/`audio` are file names under the app's `assets/images/` and `assets/audio/`.
enum PropKind { number, string, bool, color, choice, actions, image, audio }

/// Describes one editable property; the editor builds its inspector from these.
class PropDef {
  const PropDef(this.key, this.kind, this.defaultValue, {this.options = const []});

  final String key;
  final PropKind kind;
  final Object? defaultValue;
  final List<String> options;

  Map<String, Object?> toJson() => {'key': key, 'kind': kind.name, 'default': defaultValue, 'options': options};

  /// Lenient: unknown kinds become strings so a newer schema still loads.
  factory PropDef.fromJson(Object? json) {
    final m = Props(json is Map<String, Object?> ? json : const {});
    return PropDef(
      m.string('key'),
      PropKind.values.asNameMap()[m.string('kind')] ?? PropKind.string,
      m['default'],
      options: [for (final o in m.list('options')) '$o'],
    );
  }
}

typedef BehaviorFactory = FutureOr<Component?> Function(KilnEntity entity, Props props);
typedef ActionFn = void Function(KilnEntity self, Props args);

class BehaviorDef {
  const BehaviorDef(this.type, this.props, this.create);

  final String type;
  final List<PropDef> props;
  final BehaviorFactory create;
}

class ActionDef {
  const ActionDef(this.type, this.props, this.run, {this.targeted = true});

  final String type;
  final List<PropDef> props;
  final ActionFn run;

  /// False for game-wide actions (variables, events, scenes, music): they run once and ignore `target`.
  final bool targeted;
}

/// Built-ins are pre-registered; apps add custom Dart behaviors/actions with [register]/[registerAction].
class KilnRegistry {
  KilnRegistry() {
    builtinBehaviors.forEach(register);
    builtinActions.forEach(registerAction);
  }

  final Map<String, BehaviorDef> behaviors = {};
  final Map<String, ActionDef> actions = {};

  void register(BehaviorDef def) => behaviors[def.type] = def;
  void registerAction(ActionDef def) => actions[def.type] = def;

  /// What the editor needs to show app-registered behaviors/actions. Write it to `kiln.schema.json`.
  Map<String, Object?> schemaJson() => {
    'behaviors': [for (final d in behaviors.values) _schemaOf(d.type, d.props)],
    'actions': [
      for (final d in actions.values) {..._schemaOf(d.type, d.props), if (!d.targeted) 'targeted': false},
    ],
  };

  static Map<String, Object?> _schemaOf(String type, List<PropDef> props) => {
    'type': type,
    'props': [for (final p in props) p.toJson()],
  };

  /// Adds schema-only defs (no runtime code) for types not registered yet. Returns the added type names.
  List<String> loadSchema(Object? json) {
    final m = Props(json is Map<String, Object?> ? json : const {});
    final added = <String>[];
    (String, List<PropDef>)? parse(Object? raw) {
      final d = Props(raw is Map<String, Object?> ? raw : const {});
      final type = d.string('type');
      return type.isEmpty ? null : (type, d.list('props').map(PropDef.fromJson).toList());
    }

    for (final raw in m.list('behaviors')) {
      if (parse(raw) case (final type, final props) when !behaviors.containsKey(type)) {
        register(BehaviorDef(type, props, (e, p) => null));
        added.add(type);
      }
    }
    for (final raw in m.list('actions')) {
      if (parse(raw) case (final type, final props) when !actions.containsKey(type)) {
        final targeted = raw is Map && raw['targeted'] != false;
        registerAction(
          ActionDef(type, props, (self, a) => debugPrint('kiln: action "$type" has no code here'), targeted: targeted),
        );
        added.add(type);
      }
    }
    return added;
  }

  void runActions(KilnEntity self, List<Object?> list, {KilnEntity? other}) {
    for (final raw in list) {
      final args = Props(raw is Map<String, Object?> ? raw : const {});
      final def = actions[args.string('type')];
      if (def == null) {
        debugPrint('kiln: unknown action "${args.string('type')}"');
        continue;
      }
      final full = args.withDefaults(def.props);
      for (final t in def.targeted ? self.game.targets(self, args.string(targetKey), other: other) : [self]) {
        def.run(t, full);
      }
    }
  }

  /// Every action accepts this arg: empty/`self`, `other` (collision partner), an entity name, or `#tag`.
  static const targetKey = 'target';
}

/// Type-safe reads over untrusted JSON props: wrong types fall back instead of throwing.
extension type const Props(Map<String, Object?> map) {
  double number(String k) => switch (map[k]) {
    num v => v.toDouble(),
    _ => 0,
  };
  String string(String k) => switch (map[k]) {
    String v => v,
    _ => '',
  };
  bool flag(String k) => map[k] == true;
  List<Object?> list(String k) => switch (map[k]) {
    List v => v,
    _ => const [],
  };
  Object? operator [](String k) => map[k];

  /// Accepts "#RRGGBB" or "#AARRGGBB".
  Color color(String k) {
    final hex = string(k).replaceFirst('#', '');
    final v = int.tryParse(hex, radix: 16);
    if (v == null || (hex.length != 6 && hex.length != 8)) return const Color(0xFFFF00FF);
    return Color(hex.length == 6 ? 0xFF000000 | v : v);
  }

  Props withDefaults(List<PropDef> defs) => Props({for (final d in defs) d.key: d.defaultValue, ...map});
}
