import 'package:flutter/material.dart';
import 'package:kiln/kiln.dart';

import 'kiln.g.dart';

const icons = ['', 'star.png', 'heart.png', 'gem.png', 'coin.png', 'gift.png', 'clover.png'];
const backgrounds = ['', 'bg_night.png', 'bg_sunset.png'];

/// One editable prize; the scene's `slices` variable is built from these (see [WheelData.spec]).
class Prize {
  Prize(this.label, this.image, this.weight);

  String label, image;
  double weight;
}

/// What the app owns: prizes (image, label, drop rate) and the background. The scene's own variables are the
/// same data as a starting/mock value, so it also plays inside the editor.
class WheelData extends ChangeNotifier {
  WheelData()
    : background = 'bg_night.png',
      prizes = [
        Prize('Coins', 'coin.png', 40),
        Prize('Clover', 'clover.png', 30),
        Prize('Heart', 'heart.png', 15),
        Prize('Gift', 'gift.png', 10),
        Prize('Gem', 'gem.png', 4),
        Prize('Star', 'star.png', 1),
      ];

  String background;

  /// Spins allowed before the wheel refuses; 0 = unlimited.
  int limit = 5;
  final List<Prize> prizes;

  /// The `slices` variable: one map per prize.
  List<Map<String, Object?>> get spec => [
    for (final p in prizes) {'label': p.label, 'image': p.image, 'weight': p.weight},
  ];

  List<double> get rates {
    final total = prizes.fold<double>(0, (a, p) => a + p.weight);
    return [for (final p in prizes) total > 0 ? p.weight / total : 1 / prizes.length];
  }

  void update(void Function() change) {
    change();
    notifyListeners();
  }
}

void main() => runApp(const WheelApp());

class WheelApp extends StatelessWidget {
  const WheelApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true),
    home: const WheelPage(),
  );
}

class WheelPage extends StatefulWidget {
  const WheelPage({super.key});

  @override
  State<WheelPage> createState() => _WheelPageState();
}

class _WheelPageState extends State<WheelPage> {
  final data = WheelData();
  late final controller = KilnController(
    variables: KilnVars.initial(slices: data.spec, background: data.background, limit: data.limit.toDouble()),
  );
  final won = <String>[];

  @override
  void initState() {
    super.initState();
    data.addListener(_push);
  }

  // Pushes the app's data into the running scene; the Wheel and VarSprite read these variables every frame.
  void _push() {
    controller.vars
      ..slices = data.spec
      ..background = data.background
      ..limit = data.limit.toDouble();
  }

  void _reset() {
    controller.vars
      ..spins = 0
      ..result = '-';
    setState(won.clear);
  }

  @override
  void dispose() {
    data.dispose();
    controller.dispose();
    super.dispose();
  }

  void _onEvent(String name, Object? value) {
    if (name != 'won' || value is! int || value >= data.prizes.length) return;
    setState(() => won.insert(0, data.prizes[value].label));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF161814),
    body: Row(
      children: [
        SizedBox(
          width: 360,
          child: ListenableBuilder(
            listenable: data,
            builder: (_, _) => _Panel(data: data, won: won, onReset: _reset),
          ),
        ),
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 400 / 700,
              child: KilnGameWidget(asset: KilnScenes.wheel, controller: controller, onEvent: _onEvent),
            ),
          ),
        ),
      ],
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.data, required this.won, required this.onReset});

  final WheelData data;
  final List<String> won;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final rates = data.rates;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Text('Background'),
            const SizedBox(width: 12),
            DropdownButton<String>(
              value: data.background,
              items: [for (final b in backgrounds) DropdownMenuItem(value: b, child: Text(b.isEmpty ? 'none' : b))],
              onChanged: (v) => data.update(() => data.background = v ?? ''),
            ),
          ],
        ),
        Row(
          children: [
            const Text('Spin limit'),
            Expanded(
              child: Slider(
                value: data.limit.toDouble(),
                max: 20,
                divisions: 20,
                label: data.limit == 0 ? 'unlimited' : '${data.limit}',
                onChanged: (v) => data.update(() => data.limit = v.round()),
              ),
            ),
            SizedBox(width: 56, child: Text(data.limit == 0 ? '∞' : '${data.limit}')),
          ],
        ),
        TextButton.icon(icon: const Icon(Icons.restart_alt), label: const Text('Reset spins'), onPressed: onReset),
        const Divider(),
        for (var i = 0; i < data.prizes.length; i++)
          _PrizeRow(
            key: ObjectKey(data.prizes[i]),
            prize: data.prizes[i],
            rate: rates[i],
            onChanged: (f) => data.update(() => f(data.prizes[i])),
            onRemove: data.prizes.length > 2 ? () => data.update(() => data.prizes.removeAt(i)) : null,
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add slice'),
            onPressed: data.prizes.length >= 12
                ? null
                : () => data.update(() => data.prizes.add(Prize('Prize ${data.prizes.length + 1}', '', 1))),
          ),
        ),
        const Divider(),
        Text('History', style: Theme.of(context).textTheme.titleSmall),
        Text(won.isEmpty ? '-' : won.take(10).join('  ›  ')),
      ],
    );
  }
}

class _PrizeRow extends StatelessWidget {
  const _PrizeRow({super.key, required this.prize, required this.rate, required this.onChanged, this.onRemove});

  final Prize prize;
  final double rate;
  final void Function(void Function(Prize)) onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: prize.label,
                decoration: const InputDecoration(isDense: true),
                onChanged: (v) => onChanged((p) => p.label = v),
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: prize.image,
              items: [for (final i in icons) DropdownMenuItem(value: i, child: Text(i.isEmpty ? 'no image' : i))],
              onChanged: (v) => onChanged((p) => p.image = v ?? ''),
            ),
            IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onRemove),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: prize.weight.clamp(0, 100),
                max: 100,
                onChanged: (v) => onChanged((p) => p.weight = v.roundToDouble()),
              ),
            ),
            SizedBox(width: 90, child: Text('${prize.weight.round()}  (${(rate * 100).toStringAsFixed(1)}%)')),
          ],
        ),
      ],
    ),
  );
}
