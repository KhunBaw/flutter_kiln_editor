import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:kiln/kiln.dart';

import 'theme.dart';

/// Live values while Play runs: game variables, the selected entity's variables and Log output.
/// Entity variables don't notify, so the panel also refreshes on a short timer.
class WatchPanel extends StatefulWidget {
  const WatchPanel(this.game, this.entityName, {super.key});

  final KilnGame game;

  /// Name of the entity selected in the editor, or null.
  final String? entityName;

  @override
  State<WatchPanel> createState() => _WatchPanelState();
}

class _WatchPanelState extends State<WatchPanel> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  static String _fmt(Object? v) => switch (v) {
    double d when d.isFinite && d == d.roundToDouble() => d.toInt().toString(),
    double d when d.isFinite => d.toStringAsFixed(3),
    List() || Map() => jsonEncode(v),
    _ => '$v',
  };

  Widget _col(String title, List<MapEntry<String, Object?>> rows) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: T.head),
        const SizedBox(height: 4),
        Expanded(
          child: rows.isEmpty
              ? const Text('none', style: T.small)
              : ListView(
                  children: [
                    for (final e in rows)
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '${e.key}  ', style: T.label),
                            TextSpan(text: _fmt(e.value), style: T.value),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final g = widget.game;
    final self = g.world
        .descendants()
        .whereType<KilnEntity>()
        .where((e) => e.node.name == widget.entityName)
        .firstOrNull;
    final logs = g.logs.value;
    return Container(
      height: 150,
      padding: const EdgeInsets.all(10),
      decoration: const BoxDecoration(
        color: Z.z1,
        border: Border(top: BorderSide(color: Z.z3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _col('Variables', g.vars.all.entries.toList()),
          const SizedBox(width: 16),
          _col(self == null ? 'Selected entity' : self.node.name, [if (self != null) ...self.vars.entries]),
          const SizedBox(width: 16),
          _col('Log', [for (final (i, m) in logs.indexed.toList().reversed) MapEntry('${i + 1}', m)]),
        ],
      ),
    );
  }
}
