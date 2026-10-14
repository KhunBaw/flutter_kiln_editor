import 'package:flutter/material.dart';
import 'package:kiln/kiln.dart';

void main() => runApp(
  const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: Color(0xFF1B1F2A),
      body: KilnGameWidget(asset: 'assets/scenes/level1.kiln.json'),
    ),
  ),
);
