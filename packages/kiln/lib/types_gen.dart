/// Typed names for a project's scenes (pure Dart + `dart:io`, no Flutter): used by the editor on save
/// and by `dart run kiln:types`.
library;

import 'dart:convert';
import 'dart:io';

import 'src/types_gen.dart';

export 'src/types_gen.dart' show generateTypes;

/// Result of [writeProjectTypes].
typedef TypesResult = ({bool written, String path, List<String> skipped});

/// Regenerates `<projectDir>/lib/kiln.g.dart` from `<projectDir>/assets/scenes/*.kiln.json`.
/// Writes only when the content changed; unreadable scenes are skipped and listed.
/// Throws [StateError] when [projectDir] has no `pubspec.yaml` (not a Dart project).
Future<TypesResult> writeProjectTypes(String projectDir) async {
  if (!await File('$projectDir/pubspec.yaml').exists()) {
    throw StateError('$projectDir has no pubspec.yaml');
  }
  final scenes = <String, Object?>{}, skipped = <String>[];
  final dir = Directory('$projectDir/assets/scenes');
  if (await dir.exists()) {
    await for (final f in dir.list()) {
      final name = f.uri.pathSegments.last;
      if (f is! File || !name.endsWith('.kiln.json')) continue;
      try {
        scenes['assets/scenes/$name'] = jsonDecode(await f.readAsString());
      } catch (_) {
        skipped.add(name);
      }
    }
  }
  final out = File('$projectDir/lib/kiln.g.dart');
  final src = generateTypes(scenes);
  if (await out.exists() && await out.readAsString() == src) return (written: false, path: out.path, skipped: skipped);
  await out.parent.create(recursive: true);
  await out.writeAsString(src);
  return (written: true, path: out.path, skipped: skipped);
}
