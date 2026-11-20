import 'dart:io';

import 'package:fiatsonus_engine/src/soundscapes/waterfall/waterfall_recipe.dart';
import 'package:test/test.dart';

/// The design doc's text from `## Soundscape: waterfall` up to the next
/// `## ` heading.
String _section() {
  final doc = File('../../docs/procedural-ambient-sound-engine-design.md')
      .readAsStringSync();
  final start = doc.indexOf('## Soundscape: waterfall');
  if (start < 0) fail('no waterfall section in the design doc');
  final next = doc.indexOf('\n## ', start + 1);
  return doc.substring(start, next < 0 ? doc.length : next);
}

List<String> _cells(String row) => [
  for (final c in row.trim().split('|').skip(1).toList()..removeLast())
    c.trim(),
];

/// Table rows after [header], until the first line that is not a row.
List<List<String>> _rows(String section, String header) {
  final lines = section.split('\n');
  final at = lines.indexWhere((l) => l.trim().startsWith(header));
  if (at < 0) fail('no table with header "$header"');
  return [
    for (final l in lines.skip(at + 2).takeWhile((l) => l.startsWith('|')))
      _cells(l),
  ];
}

void main() {
  final section = _section();

  test('params table names and defaults equal WaterfallRecipe.params', () {
    final rows = _rows(section, '| Param | Default | Maps to |');
    expect(rows, hasLength(4));
    for (var i = 0; i < rows.length; i++) {
      final spec = WaterfallRecipe.params[i];
      expect(rows[i][0], spec.label);
      expect(double.parse(rows[i][1]), spec.defaultValue);
    }
  });

  test('layer table states the tunable constants', () {
    final rows = _rows(section, '| Layer | Recipe | Notes |');
    String row(String name) =>
        rows.singleWhere((r) => r[0] == name).join(' | ');
    expect(row('Roar'), contains('Gain ${WaterfallRecipe.roarGain}.'));
    expect(row('Body'), contains('Gain ${WaterfallRecipe.bodyGain} ×'));
    expect(row('Spray'), contains('Gain ${WaterfallRecipe.sprayGain} ×'));
    expect(
      row('Texture'),
      contains('Texture gain ${WaterfallRecipe.textureGain}'),
    );
    expect(row('Distance stage'), contains('wet ${WaterfallRecipe.wetGain}'));
    expect(
      row('Output'),
      contains('Output trim ${WaterfallRecipe.outputTrim}'),
    );
  });

  test('distance row states the texture distance fade', () {
    final rows = _rows(section, '| Param | Default | Maps to |');
    final distance = rows.singleWhere((r) => r[0] == 'Distance').join(' | ');
    final db = (-WaterfallRecipe.textureDistanceDb).toStringAsFixed(0);
    expect(distance, contains('Texture a further \u2212$db·d dB'));
  });

  test('acceptance list is unchanged from the source design doc', () {
    final acceptance = section.substring(section.indexOf('**Acceptance**'));
    expect(
      [
        for (final l in acceptance.split('\n'))
          if (l.startsWith('- [ ] ')) l,
      ],
      [
        '- [ ] At Distance 0, it does not sound like TV static or a fan.',
        '- [ ] At Distance 1, it sounds like a waterfall heard across a valley.',
        '- [ ] Changing Height sounds like a bigger fall, not just louder bass.',
      ],
    );
  });
}
