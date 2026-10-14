import 'package:flutter/material.dart';
import 'package:kiln/kiln.dart';

void main() => runApp(
  const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: Color(0xFF161814),
      body: KilnGameWidget(asset: 'assets/scenes/table.kiln.json', fade: Duration(milliseconds: 250)),
    ),
  ),
);
