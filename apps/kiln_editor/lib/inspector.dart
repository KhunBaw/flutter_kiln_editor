import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui show Image;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flame/components.dart' show Vector2;
import 'package:kiln/kiln.dart';

import 'editor_state.dart';
import 'theme.dart';
import 'widgets.dart';

/// Panel title bar: 40px, title left, actions right.
class PanelHeader extends StatelessWidget {
  const PanelHeader(this.title, this.actions, {super.key, this.leading});

  final String title;
  final List<Widget> actions;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => Container(
    height: 40,
    padding: const EdgeInsets.only(left: 12, right: 6),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Z.z3)),
    ),
    child: Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 8)],
        Expanded(
          child: Text(title, style: T.head, overflow: TextOverflow.ellipsis),
        ),
        ...actions,
      ],
    ),
  );
}

/// `fontSize` → `Font size`.
String propTitle(String key) {
  final spaced = key.replaceAllMapped(RegExp(r'(?<=[a-z])([A-Z])'), (m) => ' ${m[1]!.toLowerCase()}');
  return spaced.isEmpty ? key : spaced[0].toUpperCase() + spaced.substring(1);
}

/// Label above a group of fields.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Row(
      children: [
        Expanded(child: Text(title, style: T.head)),
        ?trailing,
      ],
    ),
  );
}

class InspectorPanel extends StatelessWidget {
  const InspectorPanel(this.s, this.registry, {super.key});

  final EditorState s;
  final KilnRegistry registry;

  @override
  Widget build(BuildContext context) {
    final e = s.selected;
    return Column(
      children: [
        if (e == null)
          const PanelHeader('Scene', [], leading: Icon(Icons.crop_landscape, size: 16, color: Z.z8))
        else
          _EntityHeader(s, e),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            children: e == null ? _scene() : _entity(e),
          ),
        ),
      ],
    );
  }

  List<Widget> _scene() {
    final d = s.doc;
    return [
      const SectionTitle('Scene'),
      Field('Name', d.name, (v) => s.edit((d) => d.name = v as String, mergeKey: 'scene.name')),
      Pair(
        Field(
          'W',
          d.size.x,
          (v) => s.edit((d) => d.size.x = v as double, mergeKey: 'scene.w'),
          parse: parseNumber,
          scrub: 1,
          compact: true,
        ),
        Field(
          'H',
          d.size.y,
          (v) => s.edit((d) => d.size.y = v as double, mergeKey: 'scene.h'),
          parse: parseNumber,
          scrub: 1,
          compact: true,
        ),
      ),
      const SectionTitle('World'),
      // World defaults to the view; a larger world scrolls under a Camera behavior.
      Pair(
        Field(
          'World W',
          d.worldSize.x,
          (v) => s.edit((d) => d.world = Vector2(v as double, d.worldSize.y), mergeKey: 'scene.ww'),
          parse: parseNumber,
          scrub: 1,
          compact: true,
        ),
        Field(
          'World H',
          d.worldSize.y,
          (v) => s.edit((d) => d.world = Vector2(d.worldSize.x, v as double), mergeKey: 'scene.wh'),
          parse: parseNumber,
          scrub: 1,
          compact: true,
        ),
      ),
      ..._variables(d.variables, 'scene', 'No variables. Text can show one as {name}.'),
    ];
  }

  /// Name/value rows editing [vars] in place (scene variables, or an entity's own).
  List<Widget> _variables(Map<String, Object?> vars, String id, String empty) {
    final rows = vars.entries.toList();
    return [
      SectionTitle(
        'Variables',
        trailing: IconBtn(
          Icons.add,
          'Add variable',
          () => s.edit((_) {
            var n = vars.length + 1;
            while (vars.containsKey('var$n')) {
              n++;
            }
            vars['var$n'] = 0;
          }),
          size: 24,
        ),
      ),
      for (final (i, kv) in rows.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Expanded(
                child: Field('Name', kv.key, (v) {
                  final name = v as String;
                  if (name.isEmpty || vars.containsKey(name)) return;
                  s.edit((_) {
                    final next = {for (final x in vars.entries) x.key == kv.key ? name : x.key: x.value};
                    vars
                      ..clear()
                      ..addAll(next);
                  }, mergeKey: '$id.var$i.name');
                }, compact: true),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Field(
                  'Value',
                  kv.value,
                  (v) => s.edit((_) => vars[kv.key] = v, mergeKey: '$id.var$i.value'),
                  parse: parseVar,
                  compact: true,
                ),
              ),
              IconBtn(Icons.close, 'Remove variable', () => s.edit((_) => vars.remove(kv.key)), size: 24),
            ],
          ),
        ),
      if (rows.isEmpty) Text(empty, style: T.small),
    ];
  }

  List<Widget> _entity(EntityNode e) {
    final animated = EditorState.animatorOf(e) != null;
    return [
      ValueListenableBuilder(valueListenable: s.playhead, builder: (_, _, _) => _transform(e, animated)),
      for (final (i, b) in e.behaviors.indexed)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: _BehaviorCard(key: ValueKey('${e.id}.b$i.${b.type}'), s: s, registry: registry, entity: e, index: i),
        ),
      ..._variables(e.variables, e.id, 'No variables. Formulas read them as self.name.'),
      const SizedBox(height: 12),
      AddMenu('Add behavior', registry.behaviors.keys, (type) {
        final def = registry.behaviors[type]!;
        s.edit((_) => e.behaviors.add(BehaviorData(type, {for (final p in def.props) p.key: p.defaultValue})));
      }),
    ];
  }

  Widget _transform(EntityNode e, bool animated) {
    Widget key(String prop) => !animated
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(left: 2),
            child: IconBtn(
              s.keyedAtPlayhead(e, prop) ? Icons.diamond : (s.isAnimated(e, prop) ? Icons.diamond_outlined : Icons.add),
              s.keyedAtPlayhead(e, prop)
                  ? 'Remove key at playhead'
                  : 'Animate: key ${propTitle(prop).toLowerCase()} at playhead',
              () => s.toggleKey(e, prop),
              active: s.isAnimated(e, prop),
              size: 22,
              glyph: (c) =>
                  Diamond(color: s.isAnimated(e, prop) ? Z.accent : Z.z6, filled: s.keyedAtPlayhead(e, prop), size: 10),
            ),
          );
    Widget num_(
      String label,
      String prop, {
      double scrub = 1,
      String? suffix,
      double Function(double)? toUi,
      double Function(double)? fromUi,
    }) {
      final raw = s.valueOf(e, prop);
      final ui = toUi?.call(raw) ?? raw;
      return Row(
        children: [
          Expanded(
            child: Field(
              label,
              ui,
              (v) => s.setProp(e, prop, fromUi?.call(v as double) ?? v as double, mergeKey: '${e.id}.$prop'),
              parse: parseNumber,
              scrub: scrub,
              suffix: suffix,
              compact: true,
            ),
          ),
          key(prop),
        ],
      );
    }

    Field size(String label, double value, void Function(double) set) => Field(
      label,
      value,
      (v) => s.edit((_) => set(v as double), mergeKey: '${e.id}.$label'),
      parse: parseNumber,
      scrub: 1,
      compact: true,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Transform'),
        Pair(num_('X', 'x'), num_('Y', 'y')),
        Pair(size('W', e.size.x, (v) => e.size.x = v), size('H', e.size.y, (v) => e.size.y = v)),
        Pair(
          num_('Rot', 'angle', suffix: '°', toUi: (r) => r * 180 / math.pi, fromUi: (d) => d * math.pi / 180),
          animated ? num_('Opacity', 'opacity', scrub: 0.01) : const SizedBox.shrink(),
        ),
        if (animated) Pair(num_('Scale X', 'scaleX', scrub: 0.01), num_('Scale Y', 'scaleY', scrub: 0.01)),
        Field(
          'Tags',
          e.tags.join(', '),
          (v) => s.edit(
            (_) => e.tags = [
              for (final t in (v as String).split(','))
                if (t.trim().isNotEmpty) t.trim(),
            ],
            mergeKey: '${e.id}.tags',
          ),
          // Commit only when the parsed list differs, so typing ", " doesn't fight the field.
          parse: (t) => [
            for (final x in t.split(','))
              if (x.trim().isNotEmpty) x.trim(),
          ].join(', '),
          hint: 'comma separated',
        ),
      ],
    );
  }
}

/// Entity title: inline-editable name, plus the families it is made of.
class _EntityHeader extends StatefulWidget {
  const _EntityHeader(this.s, this.e);

  final EditorState s;
  final EntityNode e;

  @override
  State<_EntityHeader> createState() => _EntityHeaderState();
}

class _EntityHeaderState extends State<_EntityHeader> {
  late final _c = TextEditingController(text: widget.e.name);

  @override
  void didUpdateWidget(_EntityHeader old) {
    super.didUpdateWidget(old);
    if (_c.text != widget.e.name) _c.text = widget.e.name;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.e;
    return Container(
      height: 44,
      padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Z.z3)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: Z.accent, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              key: ValueKey(e.id),
              controller: _c,
              style: T.title,
              decoration: const InputDecoration(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (v) => widget.s.edit((_) => e.name = v, mergeKey: '${e.id}.name'),
            ),
          ),
        ],
      ),
    );
  }
}

/// One behavior on an entity: family chip, name, summary, overflow menu, collapsible property list.
class _BehaviorCard extends StatefulWidget {
  const _BehaviorCard({super.key, required this.s, required this.registry, required this.entity, required this.index});

  final EditorState s;
  final KilnRegistry registry;
  final EntityNode entity;
  final int index;

  @override
  State<_BehaviorCard> createState() => _BehaviorCardState();
}

class _BehaviorCardState extends State<_BehaviorCard> {
  bool _open = true;
  bool _hover = false;

  EditorState get s => widget.s;
  EntityNode get e => widget.entity;
  BehaviorData get b => e.behaviors[widget.index];

  void _menu(String v) {
    final i = widget.index;
    switch (v) {
      case 'remove':
        s.edit((_) => e.behaviors.removeAt(i));
      case 'dup':
        s.edit(
          (_) =>
              e.behaviors.insert(i + 1, BehaviorData(b.type, jsonDecode(jsonEncode(b.props)) as Map<String, Object?>)),
        );
      case 'up':
        s.edit((_) => e.behaviors.insert(i - 1, e.behaviors.removeAt(i)));
      case 'down':
        s.edit((_) => e.behaviors.insert(i + 1, e.behaviors.removeAt(i)));
      case 'reset':
        final def = widget.registry.behaviors[b.type];
        if (def != null) s.edit((_) => b.props = {for (final p in def.props) p.key: p.defaultValue});
    }
  }

  @override
  Widget build(BuildContext context) {
    final fam = Family.of(b.type);
    final def = widget.registry.behaviors[b.type];
    final factor = factorOf(b);
    final children = [
      if (def != null)
        for (final p in def.props) propEditor(s, widget.registry, p, b.props, '${e.id}.b${widget.index}')
      else
        const Text('No schema for this type. Kept as-is in the file.', style: T.small),
      if (b.type == 'Animator') _OpenTimeline(s, b),
    ];
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        decoration: BoxDecoration(
          color: Z.z3,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _hover ? Z.z5 : Z.z4),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _open = !_open),
              child: SizedBox(
                height: 38,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8, right: 4),
                  child: Row(
                    children: [
                      AnimatedRotation(
                        turns: _open ? 0.25 : 0,
                        duration: const Duration(milliseconds: 120),
                        child: const Icon(Icons.chevron_right, size: 16, color: Z.z7),
                      ),
                      const SizedBox(width: 4),
                      FamilyChip(fam),
                      const SizedBox(width: 8),
                      Text(b.type, style: T.head.copyWith(color: Z.z10)),
                      if (factor.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(factor, style: T.small, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                      const Spacer(),
                      PopupMenuButton<String>(
                        tooltip: 'Behavior options',
                        position: PopupMenuPosition.under,
                        onSelected: _menu,
                        icon: const Icon(Icons.more_horiz, size: 16, color: Z.z8),
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'dup', height: 30, child: Text('Duplicate')),
                          PopupMenuItem(
                            value: 'up',
                            height: 30,
                            enabled: widget.index > 0,
                            child: const Text('Move up'),
                          ),
                          PopupMenuItem(
                            value: 'down',
                            height: 30,
                            enabled: widget.index < e.behaviors.length - 1,
                            child: const Text('Move down'),
                          ),
                          const PopupMenuItem(value: 'reset', height: 30, child: Text('Reset to defaults')),
                          const PopupMenuDivider(height: 9),
                          PopupMenuItem(
                            value: 'remove',
                            height: 30,
                            child: Text('Remove', style: T.body.copyWith(color: Z.danger)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_open && children.isNotEmpty)
              Container(
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Z.z4)),
                ),
                padding: const EdgeInsets.fromLTRB(12, 12, 8, 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
              ),
          ],
        ),
      ),
    );
  }
}

class _OpenTimeline extends StatelessWidget {
  const _OpenTimeline(this.s, this.b);

  final EditorState s;
  final BehaviorData b;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Cmd('Edit in timeline', () => s.setTimeline(open: true), icon: Icons.animation),
  );
}

bool _same(Object? a, Object? b) => a is num && b is num ? a == b : a == b;

/// Builds an editor widget for one [PropDef]; [map] is mutated in place inside [EditorState.edit].
Widget propEditor(EditorState s, KilnRegistry reg, PropDef d, Map<String, Object?> map, String id) {
  final v = map[d.key] ?? d.defaultValue;
  void set(Object? x, {bool merge = true}) => s.edit((_) => map[d.key] = x, mergeKey: merge ? '$id.${d.key}' : null);
  final title = propTitle(d.key);
  final modified =
      !_same(v, d.defaultValue) &&
      d.kind != PropKind.actions &&
      d.kind != PropKind.tiles &&
      d.kind != PropKind.keyframes &&
      d.kind != PropKind.json;
  final VoidCallback? reset = modified ? () => set(d.defaultValue, merge: false) : null;
  return switch (d.kind) {
    PropKind.number => Field(
      title,
      v,
      set,
      parse: parseNumber,
      scrub: d.defaultValue is num && (d.defaultValue as num).abs() < 10 && d.defaultValue != 0 ? 0.05 : 1,
      onReset: reset,
    ),
    // If.expr / Condition.expr hold a bare formula; every other string prop only validates after a leading '='.
    PropKind.string => Field(title, v, set, onReset: reset, formula: d.key == 'expr'),
    PropKind.image || PropKind.audio => _AssetField(s, d, title, v, set, reset),
    PropKind.color => _ColorField(title, v, set, reset),
    PropKind.bool => Row2(
      title,
      Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Toggle(value: v == true, onChanged: (x) => set(x, merge: false)),
        ),
      ),
      onReset: reset,
    ),
    PropKind.choice => Row2(
      title,
      d.options.length <= 3 && d.options.every((o) => o.length <= 7)
          ? Seg(options: d.options, value: v as String?, onChanged: (x) => set(x, merge: false))
          : _Dropdown(options: d.options, value: v as String?, onChanged: (x) => set(x, merge: false)),
      onReset: reset,
    ),
    PropKind.actions => _actions(s, reg, d, v is List ? v : const [], (x) => set(x, merge: false), id),
    PropKind.tiles => _TilesEditor(s, map),
    PropKind.json => Field(
      title,
      v,
      set,
      // JSON when it starts like JSON (invalid JSON is rejected); anything else stays text (Wheel's old format).
      parse: (t) {
        final x = t.trimLeft();
        if (!x.startsWith('[') && !x.startsWith('{')) return t;
        try {
          return jsonDecode(x);
        } on FormatException {
          return null;
        }
      },
      onReset: reset,
    ),
    PropKind.keyframes => _KeyframeSummary(s, v is List ? v : const []),
  };
}

class _KeyframeSummary extends StatelessWidget {
  const _KeyframeSummary(this.s, this.tracks);

  final EditorState s;
  final List<Object?> tracks;

  @override
  Widget build(BuildContext context) {
    final names = [
      for (final t in tracks)
        if (t is Map && t['prop'] is String) '${t['prop']}',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Z.z1, borderRadius: BorderRadius.circular(6)),
        child: Row(
          children: [
            const Icon(Icons.timeline, size: 16, color: Z.z7),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                names.isEmpty ? 'No tracks' : names.map((n) => n).join(' · '),
                style: T.small,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({required this.options, required this.value, required this.onChanged});

  final List<String> options;
  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: '',
    position: PopupMenuPosition.under,
    onSelected: onChanged,
    itemBuilder: (_) => [
      for (final o in options)
        PopupMenuItem(
          value: o,
          height: 30,
          child: Text(o, style: T.body.copyWith(color: o == value ? Z.accent : Z.z10)),
        ),
    ],
    child: Container(
      height: 28,
      padding: const EdgeInsets.only(left: 8, right: 4),
      decoration: BoxDecoration(color: Z.z1, borderRadius: BorderRadius.circular(4)),
      child: Row(
        children: [
          Expanded(
            child: Text(value ?? '', style: T.value, overflow: TextOverflow.ellipsis),
          ),
          const Icon(Icons.unfold_more, size: 14, color: Z.z7),
        ],
      ),
    ),
  );
}

class _ColorField extends StatelessWidget {
  const _ColorField(this.title, this.value, this.set, this.reset);

  final String title;
  final Object? value;
  final void Function(Object? v, {bool merge}) set;
  final VoidCallback? reset;

  @override
  Widget build(BuildContext context) {
    final color = Props({'c': value}).color('c');
    return Field(
      title,
      value,
      (v) => set(v),
      onReset: reset,
      leading: Builder(
        builder: (context) => MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () {
              final box = context.findRenderObject() as RenderBox;
              final at = box.localToGlobal(Offset.zero) & box.size;
              showColorPicker(context, anchor: at, color: color, onChanged: (c) => set(colorHex(c)));
            },
            child: Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: Z.z5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AssetField extends StatelessWidget {
  const _AssetField(this.s, this.d, this.title, this.value, this.set, this.reset);

  final EditorState s;
  final PropDef d;
  final String title;
  final Object? value;
  final void Function(Object? v, {bool merge}) set;
  final VoidCallback? reset;

  bool get _image => d.kind == PropKind.image;

  @override
  Widget build(BuildContext context) {
    final dir = s.projectDir, name = '$value';
    return Field(
      title,
      value,
      (v) => set(v),
      onReset: reset,
      hint: _image ? 'image file' : 'audio file',
      leading: Container(
        width: 28,
        height: 28,
        margin: const EdgeInsets.only(right: 6),
        decoration: BoxDecoration(
          color: Z.z1,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: Z.z4),
        ),
        clipBehavior: Clip.antiAlias,
        child: _image && dir != null && name.isNotEmpty
            ? Image.file(
                File('$dir/assets/images/$name'),
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined, size: 14, color: Z.z7),
              )
            : Icon(_image ? Icons.image_outlined : Icons.graphic_eq, size: 14, color: Z.z7),
      ),
      trailing: Builder(
        builder: (context) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconBtn(
              Icons.folder_open_outlined,
              'Choose from project',
              dir == null ? null : () => _choose(context),
              size: 26,
            ),
            IconBtn(Icons.file_upload_outlined, 'Import ${d.kind.name}', () => _import(context), size: 26),
          ],
        ),
      ),
    );
  }

  Future<void> _choose(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox;
    final at = box.localToGlobal(Offset.zero);
    final files = await s.assetFiles(_image ? 'images' : 'audio');
    if (!context.mounted) return;
    final pick = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy + box.size.height, at.dx + box.size.width, 0),
      items: [
        for (final f in files) PopupMenuItem(value: f, height: 30, child: Text(f)),
        if (files.isEmpty) const PopupMenuItem(enabled: false, height: 30, child: Text('Nothing imported yet')),
      ],
    );
    if (pick != null) set(pick, merge: false);
  }

  Future<void> _import(BuildContext context) async {
    try {
      final f = await openFile(
        acceptedTypeGroups: [
          XTypeGroup(
            label: d.kind.name,
            extensions: _image ? ['png', 'jpg', 'jpeg', 'webp'] : ['wav', 'mp3', 'ogg', 'm4a'],
          ),
        ],
      );
      if (f != null) set(await s.importAsset(f.path, _image ? 'images' : 'audio'), merge: false);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }
}

/// Action chain: numbered cases, each a small card with its own properties.
Widget _actions(
  EditorState s,
  KilnRegistry reg,
  PropDef d,
  List<Object?> list,
  void Function(List<Object?>) set,
  String id,
) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6, top: 2),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(propTitle(d.key), style: T.head),
            const SizedBox(width: 6),
            Text('${list.length}', style: T.small),
          ],
        ),
        const SizedBox(height: 6),
        for (final (i, raw) in list.indexed)
          if (raw is Map<String, Object?>)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: Z.z2,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Z.z4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 30,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8, right: 2),
                      child: Row(
                        children: [
                          Container(
                            width: 16,
                            height: 16,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: Z.z4, borderRadius: BorderRadius.circular(4)),
                            child: Text('${i + 1}', style: T.code.copyWith(color: Z.z9)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('${raw['type']}', style: T.head.copyWith(color: Z.z10)),
                          ),
                          IconBtn(
                            Icons.arrow_upward,
                            'Move up',
                            i == 0
                                ? null
                                : () => set(
                                    [...list]
                                      ..insert(i - 1, list[i])
                                      ..removeAt(i + 1),
                                  ),
                            size: 22,
                          ),
                          IconBtn(Icons.close, 'Remove action', () => set([...list]..removeAt(i)), size: 22),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 4, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (reg.actions[raw['type']]?.targeted ?? true) _target(s, raw, '$id.${d.key}.$i'),
                        for (final p in reg.actions[raw['type']]?.props ?? const <PropDef>[])
                          propEditor(s, reg, p, raw, '$id.${d.key}.$i'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        AddMenu('Add action', reg.actions.keys, (type) {
          final def = reg.actions[type]!;
          set([
            ...list,
            {'type': type, for (final p in def.props) p.key: p.defaultValue},
          ]);
        }, compact: true),
      ],
    ),
  );
}

/// Who an action acts on: empty = self, an entity name, or `#tag`; the menu lists what the scene has.
Widget _target(EditorState s, Map<String, Object?> raw, String id) {
  final names = <String>{}, tags = <String>{};
  void walk(List<EntityNode> list) {
    for (final e in list) {
      names.add(e.name);
      tags.addAll(e.tags);
      walk(e.children);
    }
  }

  walk(s.doc.entities);
  void set(Object? v, {bool merge = true}) => s.edit(
    (_) => (v == '' ? raw.remove(KilnRegistry.targetKey) : raw[KilnRegistry.targetKey] = v),
    mergeKey: merge ? '$id.target' : null,
  );
  return Field(
    'Target',
    raw[KilnRegistry.targetKey] ?? '',
    set,
    hint: 'self',
    trailing: PopupMenuButton<String>(
      tooltip: 'Pick target',
      icon: const Icon(Icons.arrow_drop_down),
      position: PopupMenuPosition.under,
      onSelected: (v) => set(v, merge: false),
      itemBuilder: (_) => [
        const PopupMenuItem(value: '', height: 30, child: Text('self')),
        const PopupMenuItem(value: 'other', height: 30, child: Text('other (collision partner)')),
        for (final n in names) PopupMenuItem(value: n, height: 30, child: Text(n)),
        for (final t in tags) PopupMenuItem(value: '#$t', height: 30, child: Text('#$t')),
      ],
    ),
  );
}

/// Full-width "+ label" button that opens a menu of [types] grouped by family.
class AddMenu extends StatelessWidget {
  const AddMenu(this.label, this.types, this.onSelected, {super.key, this.compact = false});

  final String label;
  final Iterable<String> types;
  final ValueChanged<String> onSelected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final sorted = [...types]..sort((a, b) => Family.of(a).index.compareTo(Family.of(b).index));
    final items = <PopupMenuEntry<String>>[];
    Family? last;
    for (final t in sorted) {
      final f = Family.of(t);
      if (f != last) {
        if (last != null) items.add(const PopupMenuDivider(height: 9));
        items.add(PopupMenuItem(enabled: false, height: 24, child: Text(f.label, style: T.small)));
        last = f;
      }
      items.add(
        PopupMenuItem(
          value: t,
          height: 30,
          child: Row(children: [FamilyChip(f, size: 18), const SizedBox(width: 10), Text(t)]),
        ),
      );
    }
    return PopupMenuButton<String>(
      tooltip: label,
      onSelected: onSelected,
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 200),
      itemBuilder: (_) => items,
      child: Container(
        height: compact ? 28 : 34,
        decoration: BoxDecoration(
          color: compact ? Colors.transparent : Z.z3,
          borderRadius: BorderRadius.circular(compact ? 5 : 8),
          border: Border.all(color: Z.z4),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add, size: 16, color: Z.z8),
            const SizedBox(width: 6),
            Text(label, style: T.head),
          ],
        ),
      ),
    );
  }
}

/// Tile painter controls for a Tilemap: grid size, tool and the tileset palette.
class _TilesEditor extends StatelessWidget {
  const _TilesEditor(this.s, this.props);

  final EditorState s;
  final Map<String, Object?> props;

  @override
  Widget build(BuildContext context) {
    final e = s.selected, b = e == null ? null : EditorState.tilemapOf(e);
    if (e == null || b == null || b.props != props) return const SizedBox.shrink();
    final (tile, cols, tiles) = EditorState.gridOf(e, b);
    final rows = tiles.length ~/ cols, on = s.paintId == e.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Pair(
          Field(
            'Cols',
            cols,
            (v) => s.resizeTiles((v as double).round(), rows),
            parse: parseNumber,
            scrub: 1,
            compact: true,
          ),
          Field(
            'Rows',
            rows,
            (v) => s.resizeTiles(cols, (v as double).round()),
            parse: parseNumber,
            scrub: 1,
            compact: true,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              if (on) ...[
                Expanded(
                  child: Seg(
                    options: const ['brush', 'fill'],
                    value: s.tool,
                    labels: const {'brush': 'Brush', 'fill': 'Fill'},
                    onChanged: (t) => s.setPaint(tool: t),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Cmd(
                on ? 'Done' : 'Paint',
                () => on ? s.setPaint(stop: true) : s.setPaint(id: e.id),
                icon: on ? Icons.check : Icons.brush,
                primary: on,
              ),
            ],
          ),
        ),
        if (on)
          _Palette(
            image: Props(props).string('image'),
            dir: s.projectDir,
            tile: tile,
            solid: parseIds(Props(props).string('solid')),
            brush: s.brush,
            onPick: (n) => s.setPaint(brush: n),
          ),
        const SizedBox(height: 6),
      ],
    );
  }
}

/// Swatches for tile 0 (erase) and every tile of the tileset image (or 8 flat colours without one).
class _Palette extends StatefulWidget {
  const _Palette({
    required this.image,
    required this.dir,
    required this.tile,
    required this.solid,
    required this.brush,
    required this.onPick,
  });

  final String image;
  final String? dir;
  final double tile;
  final Set<int> solid;
  final int brush;
  final ValueChanged<int> onPick;

  @override
  State<_Palette> createState() => _PaletteState();
}

class _PaletteState extends State<_Palette> {
  ui.Image? _img;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_Palette old) {
    super.didUpdateWidget(old);
    if (old.image != widget.image || old.dir != widget.dir) _load();
  }

  Future<void> _load() async {
    final dir = widget.dir;
    ui.Image? img;
    if (dir != null && widget.image.isNotEmpty) {
      try {
        img = await decodeImageFromList(await File('$dir/assets/images/${widget.image}').readAsBytes());
      } catch (_) {
        // Missing or unreadable tileset: fall back to flat colours.
      }
    }
    if (mounted) setState(() => _img = img);
  }

  @override
  Widget build(BuildContext context) {
    final img = _img, t = widget.tile;
    final per = img == null ? 0 : math.max(1, img.width ~/ t);
    final count = img == null ? 8 : math.min(256, per * math.max(1, img.height ~/ t));
    Widget swatch(int n) => GestureDetector(
      onTap: () => widget.onPick(n),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: widget.brush == n ? Z.accent : Z.z5, width: widget.brush == n ? 2 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: CustomPaint(painter: _SwatchPainter(img, t, n, widget.solid.contains(n), per)),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(spacing: 4, runSpacing: 4, children: [for (var n = 0; n <= count; n++) swatch(n)]),
    );
  }
}

class _SwatchPainter extends CustomPainter {
  const _SwatchPainter(this.img, this.tile, this.n, this.solid, this.per);

  final ui.Image? img;
  final double tile;
  final int n, per;
  final bool solid;

  @override
  void paint(Canvas canvas, Size size) {
    final dst = Offset.zero & size;
    if (n == 0) {
      canvas.drawLine(dst.topLeft, dst.bottomRight, Paint()..color = Z.z7);
      canvas.drawLine(dst.topRight, dst.bottomLeft, Paint()..color = Z.z7);
    } else if (img == null) {
      canvas.drawRect(dst, Paint()..color = tileColor(n, solid: solid));
    } else {
      final k = n - 1;
      canvas.drawImageRect(img!, Rect.fromLTWH((k % per) * tile, (k ~/ per) * tile, tile, tile), dst, Paint());
    }
  }

  @override
  bool shouldRepaint(_SwatchPainter old) =>
      old.img != img || old.n != n || old.solid != solid || old.tile != tile || old.per != per;
}
