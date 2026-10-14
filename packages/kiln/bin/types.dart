import 'dart:io';

import 'package:kiln/types_gen.dart';

/// `dart run kiln:types [projectDir]` — writes lib/kiln.g.dart from assets/scenes (default: current dir).
Future<void> main(List<String> args) async {
  final dir = args.isEmpty ? Directory.current.path : args.first;
  try {
    final r = await writeProjectTypes(dir);
    stdout.writeln(r.written ? 'wrote ${r.path}' : 'up to date: ${r.path}');
    for (final s in r.skipped) {
      stderr.writeln('skipped unreadable scene: $s');
    }
  } catch (e) {
    stderr.writeln('kiln types: $e');
    exitCode = 1;
  }
}
