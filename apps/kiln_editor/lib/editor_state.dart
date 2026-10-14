import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Offset;
import 'package:flame/components.dart' show Vector2;
import 'package:kiln/kiln.dart';
import 'package:kiln/types_gen.dart';

/// Holds the scene being edited. Every mutation goes through [edit] so undo/redo covers it.
class EditorState extends ChangeNotifier {
  EditorState([SceneDoc? doc]) : doc = doc ?? SceneDoc();

  SceneDoc doc;
  String? path;

  /// Flutter app folder holding `assets/` (and optionally `kiln.schema.json`); needed for images, audio, LoadScene.
  String? projectDir;
  final registry = KilnRegistry();
  String? selectedId;
  bool dirty = false;

  /// Bumped on every doc change; the scene view rebuilds its preview game on change.
  int revision = 0;

  /// Bumped when project files may have changed (open, import); the asset list re-reads on change.
  int assetsRevision = 0;

  // Scene view framing and snapping: editor-only, never saved or undone.
  double zoom = 1;
  Offset pan = Offset.zero;

  /// Snap step in scene pixels; 0 = whole pixels only.
  double grid = 0;

  void setView({double? zoom, Offset? pan, double? grid}) {
    this.zoom = (zoom ?? this.zoom).clamp(0.1, 16);
    this.pan = pan ?? this.pan;
    this.grid = grid ?? this.grid;
    notifyListeners();
  }

  /// Rounds [v] to the grid (or to whole pixels with no grid).
  double snap(double v) => grid > 0 ? (v / grid).roundToDouble() * grid : v.roundToDouble();

  // shortcut: undo stores whole-scene JSON snapshots; switch to diff commands if scenes get big.
  final _undo = <String>[];
  final _redo = <String>[];
  String? _mergeKey;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  EntityNode? get selected => selectedId == null ? null : _find(doc.entities, selectedId!);

  String snapshot() => jsonEncode(doc.toJson());
  SceneDoc copyDoc() => SceneDoc.fromJson(jsonDecode(snapshot()));

  /// Consecutive edits with the same [mergeKey] (e.g. typing in one field) collapse into one undo step.
  void edit(void Function(SceneDoc doc) change, {String? mergeKey}) {
    if (mergeKey == null || mergeKey != _mergeKey) {
      _undo.add(snapshot());
      _redo.clear();
    }
    _mergeKey = mergeKey;
    change(doc);
    _changed();
  }

  void undo() => _swap(_undo, _redo);
  void redo() => _swap(_redo, _undo);

  void _swap(List<String> from, List<String> to) {
    if (from.isEmpty) return;
    to.add(snapshot());
    doc = SceneDoc.fromJson(jsonDecode(from.removeLast()));
    _mergeKey = null;
    _changed();
  }

  void _changed() {
    dirty = true;
    revision++;
    if (selected == null) selectedId = null;
    notifyListeners();
  }

  // Tile painting: editor-only state, never saved or undone.
  /// The Tilemap entity being painted, if any.
  String? paintId;

  /// Tile number the brush lays (0 erases) and the tool: `brush` or `fill`.
  int brush = 1;
  String tool = 'brush';

  void setPaint({String? id, bool stop = false, int? brush, String? tool}) {
    paintId = stop ? null : (id ?? paintId);
    this.brush = brush ?? this.brush;
    this.tool = tool ?? this.tool;
    notifyListeners();
  }

  static BehaviorData? tilemapOf(EntityNode e) => e.behaviors.where((b) => b.type == 'Tilemap').firstOrNull;

  /// (tile px, columns, cells) of a Tilemap behavior; an empty one starts as the entity's size in cells.
  static (double, int, List<int>) gridOf(EntityNode e, BehaviorData b) {
    final p = Props(b.props), tile = p.number('tile') < 1 ? 1.0 : p.number('tile');
    final tiles = [for (final t in p.list('tiles')) t is num ? t.toInt() : 0];
    var cols = p.number('cols').round();
    if (tiles.isEmpty || cols < 1) {
      cols = (e.size.x / tile).round().clamp(1, 1 << 12);
      final rows = (e.size.y / tile).round().clamp(1, 1 << 12);
      return (tile, cols, List.filled(cols * rows, 0));
    }
    return (tile, cols, [...tiles, ...List.filled((cols - tiles.length % cols) % cols, 0)]);
  }

  /// Stores [tiles] and resizes the entity to the grid, keeping its top-left corner.
  void _setGrid(EntityNode e, BehaviorData b, double tile, int cols, List<int> tiles) {
    b.props['cols'] = cols;
    b.props['tiles'] = tiles;
    final topLeft = e.position - e.size / 2;
    e.size = Vector2(cols * tile, tiles.length ~/ cols * tile);
    e.position = topLeft + e.size / 2;
  }

  /// Paints the brush (or flood-fills) at scene point [p]; false when it hits no cell or changes nothing.
  /// A [stroke] key merges a drag into one undo step.
  bool paintAt(Vector2 p, {String? stroke}) {
    final e = paintId == null ? null : _find(doc.entities, paintId!);
    final b = e == null ? null : tilemapOf(e);
    if (e == null || b == null) return false;
    final (tile, cols, tiles) = gridOf(e, b);
    final rows = tiles.length ~/ cols, tl = e.position - e.size / 2;
    final c = ((p.x - tl.x) / tile).floor(), r = ((p.y - tl.y) / tile).floor();
    if (c < 0 || r < 0 || c >= cols || r >= rows) return false;
    final from = tiles[r * cols + c];
    if (from == brush && Props(b.props).list('tiles').length == tiles.length) return false;
    if (tool == 'fill') {
      final todo = [r * cols + c];
      while (todo.isNotEmpty) {
        final i = todo.removeLast();
        if (tiles[i] != from || tiles[i] == brush) continue;
        tiles[i] = brush;
        final x = i % cols;
        if (x > 0) todo.add(i - 1);
        if (x < cols - 1) todo.add(i + 1);
        if (i >= cols) todo.add(i - cols);
        if (i + cols < tiles.length) todo.add(i + cols);
      }
    } else {
      tiles[r * cols + c] = brush;
    }
    edit((_) => _setGrid(e, b, tile, cols, tiles), mergeKey: stroke);
    return true;
  }

  /// Resizes the selected entity's Tilemap grid to [cols] × [rows], keeping the cells that still fit.
  void resizeTiles(int cols, int rows) {
    final e = selected, b = e == null ? null : tilemapOf(e);
    if (e == null || b == null) return;
    cols = cols.clamp(1, 1 << 12);
    rows = rows.clamp(1, 1 << 12);
    final (tile, oldCols, old) = gridOf(e, b);
    final oldRows = old.length ~/ oldCols;
    final tiles = [
      for (var r = 0; r < rows; r++)
        for (var c = 0; c < cols; c++) c < oldCols && r < oldRows ? old[r * oldCols + c] : 0,
    ];
    edit((_) => _setGrid(e, b, tile, cols, tiles), mergeKey: '${e.id}.grid');
  }

  void select(String? id) {
    if (id != paintId) paintId = null;
    selectedId = id;
    _mergeKey = null;
    notifyListeners();
  }

  /// Adds a top-level entity (default: a blue rect at the view centre) and selects it.
  void addEntity({String? name, Vector2? at, Vector2? size, List<BehaviorData>? behaviors}) {
    final id = 'e${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    edit(
      (d) => d.entities.add(
        EntityNode(
          id: id,
          name: name ?? 'Entity ${d.entities.length + 1}',
          position: at ?? d.size / 2,
          size: size,
          behaviors:
              behaviors ??
              [
                BehaviorData('Shape', {'shape': 'rect', 'color': '#4488FF'}),
              ],
        ),
      ),
    );
    select(id);
  }

  /// Project files under `assets/<sub>/` (images, audio), sorted; empty without a project.
  Future<List<String>> assetFiles(String sub) async {
    final dir = Directory('$projectDir/assets/$sub');
    if (projectDir == null || !await dir.exists()) return const [];
    final names = [
      await for (final f in dir.list())
        if (f is File && !f.uri.pathSegments.last.startsWith('.')) f.uri.pathSegments.last,
    ];
    return names..sort();
  }

  void removeEntity(String id) => edit((d) => _remove(d.entities, id));

  void newScene() => _reset(SceneDoc(), null);

  /// Opens a project folder; returns the custom behavior/action types added from its `kiln.schema.json`.
  Future<List<String>> openProject(String dir) async {
    final schema = File('$dir/kiln.schema.json');
    final added = await schema.exists() ? registry.loadSchema(jsonDecode(await schema.readAsString())) : <String>[];
    projectDir = dir;
    revision++;
    assetsRevision++;
    notifyListeners();
    return added;
  }

  /// Copies [src] into `<project>/assets/<sub>/` without overwriting a different file; returns the stored name.
  Future<String> importAsset(String src, String sub) async {
    final dir = projectDir;
    if (dir == null) throw StateError('Open a project folder first');
    final out = await Directory('$dir/assets/$sub').create(recursive: true);
    final base = src.split('/').last;
    final dot = base.lastIndexOf('.');
    final (stem, ext) = dot > 0 ? (base.substring(0, dot), base.substring(dot)) : (base, '');
    var name = base;
    for (var i = 2; await File('${out.path}/$name').exists(); i++) {
      if (await _sameBytes(src, '${out.path}/$name')) return name;
      name = '$stem-$i$ext';
    }
    await File(src).copy('${out.path}/$name');
    revision++;
    assetsRevision++;
    notifyListeners();
    return name;
  }

  static Future<bool> _sameBytes(String a, String b) async =>
      listEquals(await File(a).readAsBytes(), await File(b).readAsBytes());

  /// Throws on unreadable/invalid files; the current scene is untouched in that case.
  Future<void> load(String file) async {
    final scene = SceneDoc.fromJson(jsonDecode(await File(file).readAsString()));
    _reset(scene, file);
  }

  /// Saves the scene. Inside `<project>/assets/scenes/` it also refreshes `lib/kiln.g.dart`
  /// (typed scene/event/variable names) and returns a note about it; a failed refresh never fails the save.
  Future<String?> save([String? to]) async {
    final target = to ?? path;
    if (target == null) throw StateError('No file path');
    // shortcut: direct overwrite (macOS sandbox only grants the chosen file, so no temp+rename); a crash mid-write can truncate.
    await File(target).writeAsString(const JsonEncoder.withIndent('  ').convert(doc.toJson()), flush: true);
    path = target;
    dirty = false;
    notifyListeners();
    final dir = projectDir;
    if (dir == null || !target.startsWith('$dir/assets/scenes/')) return null;
    try {
      final r = await writeProjectTypes(dir);
      return [
        if (r.written) 'types updated',
        if (r.skipped.isNotEmpty) 'skipped unreadable: ${r.skipped.join(', ')}',
      ].join(' · ');
    } on StateError {
      return null; // not a Dart project: nothing to generate
    } catch (e) {
      return 'types not updated: $e';
    }
  }

  void _reset(SceneDoc scene, String? file) {
    doc = scene;
    path = file;
    selectedId = null;
    dirty = false;
    _undo.clear();
    _redo.clear();
    _mergeKey = null;
    revision++;
    notifyListeners();
  }

  static EntityNode? _find(List<EntityNode> list, String id) {
    for (final e in list) {
      if (e.id == id) return e;
      final c = _find(e.children, id);
      if (c != null) return c;
    }
    return null;
  }

  static bool _remove(List<EntityNode> list, String id) {
    final before = list.length;
    list.removeWhere((e) => e.id == id);
    return list.length != before || list.any((e) => _remove(e.children, id));
  }
}
