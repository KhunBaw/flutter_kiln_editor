import 'package:flutter_test/flutter_test.dart';
import 'package:kiln/schema_io.dart';
import 'package:launcher/main.dart';

void main() {
  // Keeps kiln.schema.json (what the editor reads) in step with the registry; rewrites it when it drifts.
  test('kiln.schema.json is up to date', () {
    final changed = syncSchema(buildRegistry(), 'kiln.schema.json');
    if (changed) fail('kiln.schema.json was out of date and has been rewritten; commit it');
  });
}
