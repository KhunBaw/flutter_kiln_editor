import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kiln/kiln.dart';

import 'editor_state.dart';
import 'panels.dart';
import 'project.dart';
import 'theme.dart';

void main() => runApp(const KilnEditorApp());

class KilnEditorApp extends StatelessWidget {
  const KilnEditorApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Kiln Editor',
    debugShowCheckedModeBanner: false,
    theme: kilnTheme(),
    home: const EditorPage(),
  );
}

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final s = EditorState();
  late final registry = s.registry;

  /// Running copy of the scene; edits made while playing don't affect it (like Unity).
  KilnGame? _play;

  void _togglePlay() => setState(() => _play = _play == null ? _playGame(s.copyDoc()) : null);

  /// Play-mode game; with a project open, images/audio/LoadScene read from the project folder.
  KilnGame _playGame(SceneDoc doc) {
    final dir = s.projectDir;
    if (dir == null) return KilnGame(doc, registry: registry);
    return KilnGame(
      doc,
      registry: registry,
      bundle: DirBundle(dir),
      playSound: (file) {
        final p = AudioPlayer();
        p.onPlayerComplete.first.then((_) => p.dispose());
        p.play(DeviceFileSource('$dir/assets/audio/$file')).catchError((Object e) {
          p.dispose();
          _toast('Sound failed: $e');
        });
      },
      onLoadScene: (asset) async {
        try {
          final next = SceneDoc.fromJson(jsonDecode(await File('$dir/$asset').readAsString()));
          if (mounted && _play != null) setState(() => _play = _playGame(next));
        } catch (e) {
          _toast('LoadScene failed: $e');
        }
      },
    );
  }

  String? get _scenesDir => s.projectDir == null ? null : '${s.projectDir}/assets/scenes';

  Future<void> _openProject() async {
    try {
      final dir = await getDirectoryPath();
      if (dir == null) return;
      final added = await s.openProject(dir);
      _toast('Project ${dir.split('/').last}${added.isEmpty ? '' : ' • custom types: ${added.join(', ')}'}');
    } catch (e) {
      _toast('Open project failed: $e');
    }
  }

  static const _types = [
    XTypeGroup(label: 'Kiln scene', extensions: ['json']),
  ];

  @override
  void dispose() {
    s.dispose();
    super.dispose();
  }

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  /// True when it is safe to drop the current scene.
  Future<bool> _confirmDiscard() async {
    if (!s.dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('DISCARD UNSAVED CHANGES?'),
        content: Text('Changes to ${s.doc.name} since the last save will be lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('KEEP EDITING')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Z.danger),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('DISCARD'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _new() async {
    if (await _confirmDiscard()) s.newScene();
  }

  Future<void> _open() async {
    if (!await _confirmDiscard()) return;
    try {
      final f = await openFile(acceptedTypeGroups: _types, initialDirectory: _scenesDir);
      if (f != null) await s.load(f.path);
    } catch (e) {
      _toast('Open failed: $e');
    }
  }

  Future<void> _save({bool as = false}) async {
    try {
      var target = s.path;
      if (as || target == null) {
        target = (await getSaveLocation(
          acceptedTypeGroups: _types,
          initialDirectory: _scenesDir,
          suggestedName: '${s.doc.name}.kiln.json',
        ))?.path;
        if (target == null) return;
      }
      await s.save(target);
      _toast('Saved $target');
    } catch (e) {
      _toast('Save failed: $e');
    }
  }

  PlatformMenuItem _item(String label, VoidCallback onSelected, [SingleActivator? shortcut]) =>
      PlatformMenuItem(label: label, onSelected: onSelected, shortcut: shortcut);

  // Native macOS menu: its shortcuts fire even when no Flutter widget has focus (e.g. after a file dialog).
  @override
  Widget build(BuildContext context) => PlatformMenuBar(
    menus: [
      PlatformMenu(
        label: 'Kiln Editor',
        menus: [
          for (final t in [PlatformProvidedMenuItemType.about, PlatformProvidedMenuItemType.quit])
            if (PlatformProvidedMenuItem.hasMenu(t)) PlatformProvidedMenuItem(type: t),
        ],
      ),
      PlatformMenu(
        label: 'File',
        menus: [
          PlatformMenuItemGroup(
            members: [
              _item('New Scene', _new, const SingleActivator(LogicalKeyboardKey.keyN, meta: true)),
              _item('Open Project Folder…', _openProject),
              _item('Open Scene…', _open, const SingleActivator(LogicalKeyboardKey.keyO, meta: true)),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              _item('Save', _save, const SingleActivator(LogicalKeyboardKey.keyS, meta: true)),
              _item(
                'Save As…',
                () => _save(as: true),
                const SingleActivator(LogicalKeyboardKey.keyS, meta: true, shift: true),
              ),
            ],
          ),
        ],
      ),
      PlatformMenu(
        label: 'Edit',
        menus: [
          _item('Undo', s.undo, const SingleActivator(LogicalKeyboardKey.keyZ, meta: true)),
          _item('Redo', s.redo, const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true)),
        ],
      ),
      PlatformMenu(
        label: 'Game',
        menus: [_item('Play / Stop', _togglePlay, const SingleActivator(LogicalKeyboardKey.keyP, meta: true))],
      ),
    ],
    child: Focus(
      autofocus: true,
      child: Scaffold(
        body: ListenableBuilder(
          listenable: s,
          builder: (context, _) => Column(
            children: [
              _toolbar(context),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 248,
                      child: ColoredBox(color: Z.z2, child: HierarchyPanel(s)),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: _play == null
                          ? SceneView(s, registry)
                          : SceneFrame(
                              size: _play!.scene.size,
                              caption: 'Playing',
                              child: GameWidget(key: ObjectKey(_play), game: _play!),
                            ),
                    ),
                    const VerticalDivider(width: 1),
                    SizedBox(
                      width: 340,
                      child: ColoredBox(color: Z.z2, child: InspectorPanel(s, registry)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _toolbar(BuildContext context) {
    final project = s.projectDir?.split('/').last;
    final playing = _play != null;
    Widget btn(String label, String tip, VoidCallback? onPressed) => Tooltip(
      message: tip,
      child: TextButton(onPressed: onPressed, child: Text(label)),
    );
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: Z.z0,
        border: Border(bottom: BorderSide(color: Z.z3)),
      ),
      child: Row(
        children: [
          btn('NEW', 'New (⌘N)', _new),
          btn('PROJECT', 'Open project folder', _openProject),
          btn('OPEN', 'Open (⌘O)', _open),
          btn('SAVE', 'Save (⌘S)', _save),
          const _Sep(),
          btn('UNDO', 'Undo (⌘Z)', s.canUndo ? s.undo : null),
          btn('REDO', 'Redo (⇧⌘Z)', s.canRedo ? s.redo : null),
          const _Sep(),
          Tooltip(
            message: playing ? 'Stop (⌘P)' : 'Play (⌘P)',
            child: TextButton.icon(
              onPressed: _togglePlay,
              style: TextButton.styleFrom(
                backgroundColor: playing ? Colors.transparent : Z.mark,
                foregroundColor: playing ? Z.danger : Z.z1,
                side: BorderSide(color: playing ? Z.danger : Z.mark),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              icon: Icon(playing ? Icons.stop : Icons.play_arrow, size: 16),
              label: Text(playing ? 'STOP' : 'PLAY'),
            ),
          ),
          const SizedBox(width: 18),
          if (project != null) ...[
            Text(project, style: T.head.copyWith(color: Z.z8)),
            Text('  /  ', style: T.head.copyWith(color: Z.z6)),
          ],
          Text(s.path?.split('/').last ?? 'Untitled', style: T.head.copyWith(color: Z.z10)),
          if (s.dirty)
            Tooltip(
              message: 'Unsaved changes',
              child: Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(left: 8),
                decoration: const BoxDecoration(color: Z.mark, shape: BoxShape.circle),
              ),
            ),
        ],
      ),
    );
  }
}

class _Sep extends StatelessWidget {
  const _Sep();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 20, margin: const EdgeInsets.symmetric(horizontal: 8), color: Z.z4);
}
