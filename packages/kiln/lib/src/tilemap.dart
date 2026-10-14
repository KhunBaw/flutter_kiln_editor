import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flutter/painting.dart' show HSLColor, TextStyle;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'builtins.dart';
import 'game.dart';

/// A grid of tiles drawn from the entity's top-left. `tiles` is row-major: 0 = empty, n = tileset tile n-1.
/// It is a [Solid], so [Body] collides with its solid tiles; GridMove and pathfinding read it too.
class Tilemap extends Solid {
  Tilemap({required this.tile, required this.cols, required List<int> tiles, required this.solid, this.image})
    : tiles = tiles.length % cols == 0 ? tiles : [...tiles, ...List.filled(cols - tiles.length % cols, 0)],
      super(oneWay: false);

  final double tile;
  final int cols;
  final List<int> tiles;
  final Set<int> solid;
  final Image? image;

  int get rows => tiles.length ~/ cols;

  Vector2 get _origin {
    final r = parent.toAbsoluteRect();
    return Vector2(r.left, r.top);
  }

  @override
  void onMount() {
    super.onMount();
    parent.game.tilemaps.add(this);
  }

  @override
  void onRemove() {
    parent.game.tilemaps.remove(this);
    super.onRemove();
  }

  /// Cell under a world point (may be outside the grid).
  (int, int) cellAt(Vector2 world) {
    final p = world - _origin;
    return ((p.x / tile).floor(), (p.y / tile).floor());
  }

  Vector2 centerOf(int c, int r) => _origin + Vector2((c + 0.5) * tile, (r + 0.5) * tile);

  /// Outside the grid counts as blocked, so walkers can't leave the map.
  bool blocked(int c, int r) => c < 0 || r < 0 || c >= cols || r >= rows || solid.contains(tiles[r * cols + c]);

  @override
  Iterable<Rect> hits(Rect area) sync* {
    final o = _origin;
    final c0 = ((area.left - o.x) / tile).floor().clamp(0, cols - 1), c1 = ((area.right - o.x) / tile).floor();
    final r0 = ((area.top - o.y) / tile).floor().clamp(0, rows - 1), r1 = ((area.bottom - o.y) / tile).floor();
    for (var r = r0; r <= r1 && r < rows; r++) {
      for (var c = c0; c <= c1 && c < cols; c++) {
        if (solid.contains(tiles[r * cols + c])) yield Rect.fromLTWH(o.x + c * tile, o.y + r * tile, tile, tile);
      }
    }
  }

  // shortcut: draws every cell each frame; add culling to the camera view if maps get large.
  @override
  void render(Canvas canvas) {
    final img = image, per = img == null ? 0 : (img.width ~/ tile).clamp(1, 1 << 20);
    final paint = Paint();
    for (var i = 0; i < tiles.length; i++) {
      final n = tiles[i];
      if (n <= 0) continue;
      final dst = Rect.fromLTWH((i % cols) * tile, (i ~/ cols) * tile, tile, tile);
      if (img == null) {
        canvas.drawRect(dst, paint..color = tileColor(n, solid: solid.contains(n)));
      } else {
        final k = n - 1;
        canvas.drawImageRect(img, Rect.fromLTWH((k % per) * tile, (k ~/ per) * tile, tile, tile), dst, paint);
      }
    }
  }
}

/// Placeholder colour for tile [n] when there is no tileset image (solid tiles read darker).
Color tileColor(int n, {required bool solid}) =>
    HSLColor.fromAHSL(1, (n * 47) % 360, 0.45, solid ? 0.32 : 0.55).toColor();

/// Parses "1, 2, 5" into tile ids; junk is skipped.
Set<int> parseIds(String s) => {for (final x in s.split(',')) ?int.tryParse(x.trim())};

/// Shortest 4-way path of cells from [from] to [to] (both included), or null when walled off.
/// Breadth-first: all steps cost the same, so it matches A* without the heuristic.
List<(int, int)>? findPath(Tilemap m, (int, int) from, (int, int) to) {
  if (m.blocked(to.$1, to.$2)) return null;
  final prev = <int, int>{};
  int key((int, int) c) => c.$2 * m.cols + c.$1;
  final queue = [from];
  final seen = {key(from)};
  for (var head = 0; head < queue.length; head++) {
    final cur = queue[head];
    if (cur == to) {
      final path = [cur];
      for (var k = key(cur); prev.containsKey(k); k = prev[k]!) {
        path.add((prev[k]! % m.cols, prev[k]! ~/ m.cols));
      }
      return path.reversed.toList();
    }
    for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      final n = (cur.$1 + dx, cur.$2 + dy);
      if (m.blocked(n.$1, n.$2) || !seen.add(key(n))) continue;
      prev[key(n)] = key(cur);
      queue.add(n);
    }
  }
  return null;
}

/// Walks along [findPath] toward a moving target; recomputed when the target changes cell.
class PathWalker {
  PathWalker(this.entity);

  final KilnEntity entity;
  (int, int)? _goal;
  List<Vector2> _way = [];

  /// Velocity direction (unit) toward [target], or zero when already there or unreachable.
  Vector2 steer(Tilemap m, Vector2 target, double reach, double dt, double speed) {
    final me = entity.absoluteCenter, goal = m.cellAt(target);
    if (goal != _goal) {
      _goal = goal;
      final path = findPath(m, m.cellAt(me), goal);
      _way = path == null ? [] : [for (final c in path.skip(1)) m.centerOf(c.$1, c.$2)];
      if (path == null) return Vector2.zero();
    }
    while (_way.isNotEmpty && me.distanceTo(_way.first) <= (speed * dt).clamp(1.5, double.infinity)) {
      _way.removeAt(0);
    }
    final to = (_way.isEmpty ? target : _way.first) - me;
    return to.length > reach ? (to..normalize()) : Vector2.zero();
  }
}

/// Moves its entity one cell per step (keys), pushing `push` entities ahead of it; tiles and `block` entities stop it.
/// Cells are [cell] pixels with the grid origin at the world's (0, 0).
class GridMove extends Component with ParentIsA<KilnEntity> {
  GridMove({
    required this.cell,
    required this.time,
    required String keys,
    required this.push,
    required this.block,
    required this.actions,
  }) : _dirs = [
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

  final double cell, time;
  final String push, block;
  final List<Object?> actions;
  final List<(LogicalKeyboardKey, int, int)> _dirs;
  Vector2? _from, _to;
  double _t = 0;

  @override
  void onMount() {
    super.onMount();
    if (!parent.game.editing) parent.game.keyPollers++;
  }

  @override
  void onRemove() {
    if (!parent.game.editing) parent.game.keyPollers--;
  }

  bool _at(KilnEntity e, Vector2 p) =>
      (e.absoluteCenter.x - p.x).abs() < cell / 2 && (e.absoluteCenter.y - p.y).abs() < cell / 2;

  Iterable<KilnEntity> _in(String selector, Vector2 p, {KilnEntity? except}) => selector.isEmpty
      ? const []
      : parent.game.targets(parent, selector).where((e) => e != parent && e != except && _at(e, p));

  bool _wall(Vector2 p) => parent.game.tilemaps.any((m) {
    final (c, r) = m.cellAt(p);
    return m.blocked(c, r);
  });

  void _step(int dx, int dy) {
    final to = parent.absoluteCenter + Vector2(dx * cell, dy * cell);
    if (_wall(to) || _in(block, to).isNotEmpty) return;
    for (final box in _in(push, to).toList()) {
      final beyond = to + Vector2(dx * cell, dy * cell);
      // A box can't be pushed into a wall, another box or a blocker; a blocked push stops the walker too.
      if (_wall(beyond) || _in(push, beyond).isNotEmpty || _in(block, beyond).isNotEmpty) return;
      time <= 0 ? box.position = beyond : box.add(MoveToEffect(beyond, EffectController(duration: time)));
    }
    if (time <= 0) {
      parent.position = to;
      return parent.runActions(actions);
    }
    _from = parent.position.clone();
    _to = to;
    _t = 0;
  }

  @override
  void update(double dt) {
    final g = parent.game;
    if (g.editing) return;
    if (_to case final to?) {
      _t += dt;
      if (_t < time) return parent.position.setFrom(_from! + (to - _from!) * (_t / time));
      parent.position.setFrom(to);
      _to = null;
      parent.runActions(actions);
    }
    for (final (k, x, y) in _dirs) {
      if (g.keysDown.contains(k)) return _step(x, y);
    }
  }
}

/// Text box with optional numbered choices. Tap, Space or Enter advances; a pick stores its 1-based number in `variable`.
class Dialogue extends Component with ParentIsA<KilnEntity> {
  Dialogue({
    required this.lines,
    required this.choices,
    required this.variable,
    required this.open,
    required this.style,
    required this.actions,
  });

  final List<String> lines, choices;
  final String variable, open;
  final TextStyle style;
  final List<Object?> actions;
  int _i = -1;
  final _shown = <Component>[];
  VoidCallback? _off;

  bool get isOpen => _i >= 0;

  @override
  void onMount() {
    super.onMount();
    final g = parent.game;
    if (g.editing) return _render(0);
    parent.tapHandlers.add(advance);
    g.keyListeners.add(_onKey);
    if (open.isEmpty) return start();
    parent.isVisible = false;
    _off = g.on(open, (_) => start());
  }

  @override
  void onRemove() {
    parent.tapHandlers.remove(advance);
    parent.game.keyListeners.remove(_onKey);
    _off?.call();
  }

  void start() {
    if (lines.isEmpty) return;
    parent.isVisible = true;
    _render(_i = 0);
  }

  void advance() {
    if (!isOpen || (_i == lines.length - 1 && choices.isNotEmpty)) return;
    if (_i < lines.length - 1) return _render(++_i);
    _finish();
  }

  void _pick(int n) {
    if (isOpen && _i == lines.length - 1 && n >= 1 && n <= choices.length) _finish(n);
  }

  void _finish([int? choice]) {
    _i = -1;
    _clear();
    parent.isVisible = false;
    if (choice != null && variable.isNotEmpty) parent.game.vars[variable] = choice;
    parent.runActions(actions);
  }

  void _onKey(KeyEvent ev) {
    if (ev is! KeyDownEvent) return;
    if (ev.logicalKey == LogicalKeyboardKey.space || ev.logicalKey == LogicalKeyboardKey.enter) advance();
    if (int.tryParse(ev.logicalKey.keyLabel) case final n?) _pick(n);
  }

  void _clear() {
    for (final c in _shown) {
      c.removeFromParent();
    }
    _shown.clear();
  }

  void _render(int i) {
    _clear();
    if (i >= lines.length) return;
    final last = i == lines.length - 1;
    final w = parent.size.x - 16;
    _shown.add(
      TextBoxComponent(
        text: fillTemplate(lines[i], parent.game.vars),
        textRenderer: TextPaint(style: style),
        boxConfig: TextBoxConfig(maxWidth: w, timePerChar: 0),
        position: Vector2(8, 8),
      ),
    );
    if (last) {
      for (final (n, c) in choices.indexed) {
        _shown.add(
          _Choice('${n + 1}. ${fillTemplate(c, parent.game.vars)}', TextPaint(style: style), () => _pick(n + 1))
            ..position = Vector2(8, parent.size.y - 8 - (choices.length - n) * (style.fontSize ?? 16) * 1.4),
        );
      }
    }
    parent.addAll(_shown);
  }
}

class _Choice extends TextComponent with TapCallbacks {
  _Choice(String text, TextPaint paint, this.onPick) : super(text: text, textRenderer: paint);

  final VoidCallback onPick;

  @override
  void onTapDown(TapDownEvent event) => onPick();
}

/// Where SaveGame/LoadGame keep data. The default writes JSON files in the app support directory.
abstract interface class KilnStorage {
  Future<Map<String, Object?>?> read(String slot);
  Future<void> write(String slot, Map<String, Object?> data);
}

class FileKilnStorage implements KilnStorage {
  Future<File> _file(String slot) async =>
      File('${(await getApplicationSupportDirectory()).path}/kiln_${slot.replaceAll(RegExp(r'[^\w-]'), '_')}.json');

  @override
  Future<Map<String, Object?>?> read(String slot) async {
    final f = await _file(slot);
    if (!await f.exists()) return null;
    return switch (jsonDecode(await f.readAsString())) {
      final Map<String, Object?> m => m,
      _ => null,
    };
  }

  @override
  Future<void> write(String slot, Map<String, Object?> data) async =>
      (await _file(slot)).writeAsString(jsonEncode(data), flush: true);
}
