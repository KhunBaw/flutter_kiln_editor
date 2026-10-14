import 'package:flutter/material.dart';
import 'package:kiln/kiln.dart';

import 'kiln.g.dart';

void main() => runApp(
  MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: const Color(0xFF161814),
      body: KilnGameWidget(
        asset: KilnScenes.level1,
        // Coins collected carry from level1 into the win scene.
        controller: KilnController(keepVariables: true),
      ),
    ),
  ),
);
