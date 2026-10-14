import 'package:flutter/material.dart';
import 'package:kiln/kiln.dart';
import 'package:kiln_forge2d/kiln_forge2d.dart';

/// The editor learns RigidBody/Joint/DragLaunch from `kiln.schema.json`, written by the test in `test/`.
KilnRegistry buildRegistry() {
  final registry = KilnRegistry();
  registerForge2d(registry);
  return registry;
}

void main() => runApp(
  MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: const Color(0xFF161814),
      body: KilnGameWidget(asset: 'assets/scenes/level1.kiln.json', registry: buildRegistry()),
    ),
  ),
);
