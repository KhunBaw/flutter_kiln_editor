import 'package:flutter/material.dart';
import 'package:kiln/kiln.dart';

import 'kiln.g.dart';

void main() => runApp(const TapGameApp());

class TapGameApp extends StatefulWidget {
  const TapGameApp({super.key});

  @override
  State<TapGameApp> createState() => _TapGameAppState();
}

class _TapGameAppState extends State<TapGameApp> {
  final _c = KilnController();
  String _result = '';

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: const Color(0xFF1B1F2A),
      body: Stack(
        children: [
          KilnGameWidget(
            asset: KilnScenes.level1,
            controller: _c,
            onEvent: (name, _) => setState(() => _result = name == KilnEvents.win ? 'win' : 'lose'),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: ListenableBuilder(
              // The controller notifies on scene change; vars on every change.
              listenable: Listenable.merge([_c, _c.vars]),
              builder: (_, _) => Row(
                children: [
                  if (_result.isNotEmpty) Text('last: $_result  ', style: const TextStyle(color: Colors.white70)),
                  Text('score ${_c.vars.score.toInt()}', style: const TextStyle(color: Colors.white)),
                  TextButton(onPressed: () => _c.loadScene(KilnScenes.level1), child: const Text('Restart')),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
