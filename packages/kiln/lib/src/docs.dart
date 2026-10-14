import 'registry.dart';

/// Markdown reference of every registered behavior and action, generated from the registry.
String referenceMarkdown(KilnRegistry registry) {
  final b = StringBuffer(
    '# Kiln behavior reference\n\nGenerated from `KilnRegistry.schemaJson()`; do not edit by hand.\n',
  );
  void section(String title, Iterable<(String, List<PropDef>)> items) {
    b.write('\n## $title\n');
    for (final (type, props) in items) {
      b.write('\n### $type\n');
      if (props.isEmpty) {
        b.write('\nNo properties.\n');
        continue;
      }
      b.write('\n| Property | Kind | Default |\n|---|---|---|\n');
      for (final p in props) {
        final kind = p.options.isEmpty ? p.kind.name : '${p.kind.name} (${p.options.join(', ')})';
        b.write('| `${p.key}` | $kind | ${p.defaultValue == null ? '' : '`${p.defaultValue}`'} |\n');
      }
    }
  }

  section('Behaviors', [for (final d in registry.behaviors.values) (d.type, d.props)]);
  section('Actions', [for (final d in registry.actions.values) (d.type, d.props)]);
  return b.toString();
}
