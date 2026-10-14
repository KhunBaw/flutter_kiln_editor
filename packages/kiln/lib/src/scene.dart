import 'package:flame/components.dart';

/// Scene file format. Bump [SceneDoc.version] and migrate in [SceneDoc.fromJson] on breaking changes.
class SceneDoc {
  SceneDoc({
    this.name = 'scene',
    Vector2? size,
    this.world,
    Map<String, Object?>? variables,
    List<EntityNode>? entities,
  }) : size = size ?? Vector2(400, 700),
       variables = variables ?? {},
       entities = entities ?? [];

  static const version = 1;

  String name;

  /// The view (screen) size; the camera shows this much of the world.
  Vector2 size;

  /// World size when it is larger than the view; null means the world is the view.
  Vector2? world;
  Map<String, Object?> variables;
  List<EntityNode> entities;

  Vector2 get worldSize => world ?? size;

  factory SceneDoc.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('Scene must be a JSON object');
    }
    final v = json['kiln'];
    if (v is int && v > version) {
      throw FormatException('Scene version $v is newer than supported ($version)');
    }
    return SceneDoc(
      name: _str(json['name'], 'scene'),
      size: _vec(json['size'], Vector2(400, 700)),
      world: json['world'] == null ? null : _vec(json['world'], Vector2(400, 700)),
      variables: json['variables'] is Map<String, Object?> ? {...json['variables'] as Map<String, Object?>} : null,
      entities: _list(json['entities']).map(EntityNode.fromJson).toList(),
    );
  }

  Map<String, Object?> toJson() => {
    'kiln': version,
    'name': name,
    'size': [size.x, size.y],
    if (world case final w?) 'world': [w.x, w.y],
    'variables': variables,
    'entities': [for (final e in entities) e.toJson()],
  };
}

class EntityNode {
  EntityNode({
    required this.id,
    this.name = 'Entity',
    Vector2? position,
    Vector2? size,
    this.angle = 0,
    List<String>? tags,
    List<BehaviorData>? behaviors,
    List<EntityNode>? children,
    Map<String, Object?>? variables,
  }) : position = position ?? Vector2.zero(),
       size = size ?? Vector2.all(64),
       tags = tags ?? [],
       behaviors = behaviors ?? [],
       children = children ?? [],
       variables = variables ?? {};

  String id;
  String name;

  /// Center of the entity (anchor is always center, like Unity's default pivot).
  Vector2 position;
  Vector2 size;

  /// Radians.
  double angle;

  /// Group names; actions address them as `#tag`.
  List<String> tags;
  List<BehaviorData> behaviors;
  List<EntityNode> children;

  /// This entity's own variables (start values); formulas read them as `self.name`.
  Map<String, Object?> variables;

  factory EntityNode.fromJson(Object? json) {
    final m = json is Map<String, Object?> ? json : const <String, Object?>{};
    return EntityNode(
      id: _str(m['id'], ''),
      name: _str(m['name'], 'Entity'),
      position: _vec(m['position'], Vector2.zero()),
      size: _vec(m['size'], Vector2.all(64)),
      angle: _num(m['angle']),
      tags: [
        for (final t in _list(m['tags']))
          if (t is String && t.isNotEmpty) t,
      ],
      behaviors: _list(m['behaviors']).map(BehaviorData.fromJson).toList(),
      children: _list(m['children']).map(EntityNode.fromJson).toList(),
      variables: m['variables'] is Map<String, Object?> ? {...m['variables'] as Map<String, Object?>} : null,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'position': [position.x, position.y],
    'size': [size.x, size.y],
    'angle': angle,
    if (tags.isNotEmpty) 'tags': tags,
    if (variables.isNotEmpty) 'variables': variables,
    'behaviors': [for (final b in behaviors) b.toJson()],
    'children': [for (final c in children) c.toJson()],
  };
}

class BehaviorData {
  BehaviorData(this.type, [Map<String, Object?>? props]) : props = props ?? {};

  String type;

  /// Unknown keys are kept as-is so newer files survive a round trip.
  Map<String, Object?> props;

  factory BehaviorData.fromJson(Object? json) {
    final m = json is Map<String, Object?> ? json : const <String, Object?>{};
    return BehaviorData(
      _str(m['type'], ''),
      m['props'] is Map<String, Object?> ? {...m['props'] as Map<String, Object?>} : null,
    );
  }

  Map<String, Object?> toJson() => {'type': type, 'props': props};
}

String _str(Object? v, String fallback) => v is String ? v : fallback;
double _num(Object? v) => v is num ? v.toDouble() : 0;
List<Object?> _list(Object? v) => v is List ? v : const [];
Vector2 _vec(Object? v, Vector2 fallback) => v is List && v.length == 2 && v[0] is num && v[1] is num
    ? Vector2((v[0] as num).toDouble(), (v[1] as num).toDouble())
    : fallback;
