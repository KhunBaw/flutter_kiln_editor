/// File helpers for apps with custom behaviors; kept out of `kiln.dart` because it needs `dart:io`.
library;

import 'dart:convert';
import 'dart:io';

import 'kiln.dart';

/// Writes [registry]'s schema to [path] (the editor reads `kiln.schema.json`) when it differs.
/// Returns true when the file changed. Use it in a test so code and schema never drift:
/// `test('kiln schema up to date', () => expect(syncSchema(registry, 'kiln.schema.json'), isFalse));`
bool syncSchema(KilnRegistry registry, String path) {
  final next = '${const JsonEncoder.withIndent('  ').convert(registry.schemaJson())}\n';
  final file = File(path);
  if (file.existsSync() && file.readAsStringSync() == next) return false;
  file.writeAsStringSync(next);
  return true;
}
