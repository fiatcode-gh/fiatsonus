import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/device/src/cpu_top.dart';

Map<String, Object?> _function(
  String kind,
  int exclusive,
  int inclusive,
  Map<String, Object?> function,
) => {
  'type': 'ProfileFunction',
  'kind': kind,
  'inclusiveTicks': inclusive,
  'exclusiveTicks': exclusive,
  'resolvedUrl': '',
  'function': function,
};

Map<String, Object?> _dart(String name, Map<String, Object?> owner) => {
  'type': '@Function',
  'id': 'functions/$name',
  'name': name,
  'owner': owner,
  'static': false,
  'const': false,
  'implicit': false,
  'abstract': false,
  'isGetter': false,
  'isSetter': false,
};

Map<String, Object?> _class(String name) => {
  'type': '@Class',
  'id': 'classes/$name',
  'name': name,
};

/// A `getCpuSamples` response as `CpuSamples.toJson()` writes it, after a
/// round trip through JSON text.
final Map<String, Object?> _samples = jsonDecode(
  jsonEncode({
    'type': 'CpuSamples',
    'samplePeriod': 1000,
    'maxStackDepth': 128,
    'sampleCount': 200,
    'timeOriginMicros': 0,
    'timeExtentMicros': 200000,
    'pid': 4242,
    'functions': [
      _function('Dart', 20, 150, _dart('render', _class('Waterfall'))),
      _function(
        'Dart',
        30,
        180,
        _dart('benchIsolateMain', {
          'type': '@Library',
          'id': 'libraries/1',
          'name': '',
          'uri': 'package:fiatsonus/src/bench/bench_isolate.dart',
        }),
      ),
      _function('Dart', 90, 90, _dart('processStereo', _class('Biquad'))),
      _function('Native', 40, 40, {'type': 'NativeFunction', 'name': 'round'}),
      _function(
        'Dart',
        5,
        5,
        _dart('<anonymous closure>', _dart('runBench', _class('BenchRunner'))),
      ),
    ],
    'samples': <Object?>[],
  }),
) as Map<String, Object?>;

void main() {
  test('functions are listed by exclusive ticks, as % of the samples', () {
    expect(cpuTop(_samples).split('\n'), [
      'sample_count=200',
      'sample_period_us=1000',
      ' excl%   incl%  kind    function',
      '  45.0    45.0  Dart    Biquad.processStereo',
      '  20.0    20.0  Native  round',
      '  15.0    90.0  Dart    benchIsolateMain',
      '  10.0    75.0  Dart    Waterfall.render',
      '   2.5     2.5  Dart    <anonymous closure>',
    ]);
  });

  test('limit keeps the functions with the most exclusive ticks', () {
    final lines = cpuTop(_samples, limit: 2).split('\n');

    expect(lines, hasLength(5));
    expect(lines.last, endsWith('  round'));
  });

  test('no samples gives the counts without rows', () {
    expect(
      cpuTop({'sampleCount': 0, 'samplePeriod': 250, 'functions': <Object?>[]}),
      'sample_count=0\nsample_period_us=250\n excl%   incl%  kind    function',
    );
  });
}
