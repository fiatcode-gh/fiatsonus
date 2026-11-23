import 'package:fiatsonus_engine/profiling.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/device/src/bench_report.dart';

/// Phone `us_per_s` per stage and run: medians full 172000, scape 136000,
/// bus 60000, the four layers 20000, 15000, 30000 and 10000 above it.
/// Unexplained is 136000 − 60000 − 75000 = 1000, under 5 % of full.
const _phone = {
  BenchStage.full: [170000, 190000, 172000],
  BenchStage.scape: [136000, 136000, 136000],
  BenchStage.bus: [60000, 60000, 60000],
  BenchStage.roar: [80000, 80000, 80000],
  BenchStage.body: [75000, 75000, 75000],
  BenchStage.spray: [90000, 90000, 90000],
  BenchStage.texture: [70000, 70000, 70000],
  BenchStage.reverb: [40000, 40000, 40000],
  BenchStage.limiter: [3000, 3000, 3000],
};

/// Unexplained is 3000 − 1500 − 1900 = −400, 10 % of full. The texture share
/// (100) makes the phone/desktop ratio 100, at least 1.5 × the 43.0 of full.
const _desktop = {
  BenchStage.full: [4000],
  BenchStage.scape: [3000],
  BenchStage.bus: [1500],
  BenchStage.roar: [2000],
  BenchStage.body: [1800],
  BenchStage.spray: [2500],
  BenchStage.texture: [1600],
  BenchStage.reverb: [1000],
  BenchStage.limiter: [100],
};

const _shareKeys = [
  'roar',
  'body',
  'spray',
  'texture',
  'reverb',
  'bus_other',
  'master',
  'unexplained',
  'full',
];

/// Bench lines as the bench target logs them. Each stage run takes 0.5 s of
/// wall time and 10 ticks on cpu0 at 691200 kHz; with [fullOnBig], `full`
/// also takes 30 ticks on cpu4 at 2208000 kHz. Without [tis] the data is
/// unavailable; [desktop] leaves the tis lines out, like `stage_bench`.
String _text(
  Map<BenchStage, List<int>> usPerS, {
  bool tis = true,
  bool fullOnBig = true,
  bool desktop = false,
  BenchStage? skip,
}) {
  var little = 0;
  var big = 0;
  var tUs = 1000;
  String tisLine() =>
      'FBENCH tis t_us=$tUs '
      'data=${tis ? 'cpu0,691200 $little,cpu4,2208000 $big' : 'unavailable'}';
  final lines = [
    'FBENCH begin v=1 mode=${desktop ? 'aot' : 'measure'} '
        'build=${desktop ? 'desktop' : 'release'}',
    if (!desktop) tisLine(),
  ];
  final runs = usPerS[BenchStage.full]!.length;
  for (var run = 1; run <= runs; run++) {
    for (final stage in BenchStage.values) {
      if (stage == skip) continue;
      final us = usPerS[stage]![run - 1];
      lines.add(
        'FBENCH v=1 stage=${stage.name} rate=48000 secs=60 run=$run '
        'us_per_s=$us factor=${(1e6 / us).toStringAsFixed(1)}',
      );
      little += 10;
      if (stage == BenchStage.full && fullOnBig) big += 30;
      tUs += 500000;
      if (!desktop) lines.add(tisLine());
    }
  }
  return [...lines, 'FBENCH done'].join('\n');
}

Map<BenchStage, List<int>> _scaled(
  Map<BenchStage, List<int>> usPerS,
  BenchStage stage,
  double by,
) => {
  for (final MapEntry(:key, :value) in usPerS.entries)
    key: key == stage ? [for (final v in value) (v * by).round()] : value,
};

/// The trimmed cells of the Markdown row whose first cell is [name], in the
/// table that follows [heading].
List<String> _row(String report, String heading, String name) {
  final lines = report.split('\n');
  final from = lines.indexOf(heading);
  expect(from, isNot(-1), reason: 'no "$heading" in\n$report');
  final row = lines
      .skip(from)
      .firstWhere((l) => l.startsWith('| $name |'), orElse: () => '');
  expect(row, isNotEmpty, reason: 'no row $name under $heading in\n$report');
  final cells = row.split('|').map((c) => c.trim()).toList();
  return cells.sublist(1, cells.length - 1);
}

String _report({
  String? phone,
  String? desktop,
  String? basePhone,
  String? baseDesktop,
}) => benchReport(
  phone: BenchFile.parse(phone ?? _text(_phone)),
  desktop: desktop == null ? null : BenchFile.parse(desktop),
  basePhone: basePhone == null ? null : BenchFile.parse(basePhone),
  baseDesktop: baseDesktop == null ? null : BenchFile.parse(baseDesktop),
);

void main() {
  test('the stage table holds the median, min, max, factor and residency', () {
    // Over 3 runs, full: 30 ticks on cpu0, 90 on cpu4, 1.5 s of wall time.
    expect(_row(_report(), '## Stages', 'full').sublist(0, 8), [
      'full',
      '172000',
      '170000',
      '190000',
      '5.8',
      'cpu0 25.0, cpu4 75.0',
      'cpu0 691, cpu4 2208',
      '0.80',
    ]);
    expect(_row(_report(), '## Stages', 'limiter').sublist(5, 8), [
      'cpu0 100.0, cpu4 0.0',
      'cpu0 691, cpu4 0',
      '0.20',
    ]);
  });

  test('the desktop column, the ratio and the speed-ups against the bases', () {
    final report = _report(
      desktop: _text(_desktop, desktop: true),
      basePhone: _text(_scaled(_phone, BenchStage.full, 1.1)),
      baseDesktop: _text(
        _scaled(_desktop, BenchStage.full, 1.1),
        desktop: true,
      ),
    );

    expect(_row(report, '## Stages', 'full').sublist(8), [
      '4000',
      '43.0',
      '1.10',
      '1.10',
    ]);
    expect(_row(report, '## Stages', 'reverb').sublist(8), [
      '1000',
      '40.0',
      '1.00',
      '1.00',
    ]);
  });

  test('without tis data the residency columns stay empty', () {
    final full = _row(
      _report(phone: _text(_phone, tis: false)),
      '## Stages',
      'full',
    );

    expect(full.sublist(1, 8), [
      '172000',
      '170000',
      '190000',
      '5.8',
      '',
      '',
      '',
    ]);
  });

  test('a desktop file without tis lines parses', () {
    final desktop = BenchFile.parse(_text(_desktop, desktop: true));

    expect(desktop.median(BenchStage.full), 4000);
    expect(desktop.residency, isEmpty);
  });

  test('the share table: values, % of full, ratios and the OUTLIER mark', () {
    final report = _report(desktop: _text(_desktop, desktop: true));

    expect(_row(report, '## Shares', 'full'), [
      'full',
      '172000',
      '100.0',
      '4000',
      '100.0',
      '43.0',
      '',
    ]);
    expect(_row(report, '## Shares', 'master'), [
      'master',
      '36000',
      '20.9',
      '1000',
      '25.0',
      '36.0',
      '',
    ]);
    expect(_row(report, '## Shares', 'texture'), [
      'texture',
      '10000',
      '5.8',
      '100',
      '2.5',
      '100.0',
      'OUTLIER',
    ]);
    expect(
      [
        for (final key in _shareKeys)
          if (_row(report, '## Shares', key).last == 'OUTLIER') key,
      ],
      ['texture'],
    );
  });

  test('UNRELIABLE split is printed per file when |unexplained| > 5 %', () {
    final report = _report(desktop: _text(_desktop, desktop: true));

    expect(
      report,
      contains('UNRELIABLE split desktop: unexplained -10.0 % of full'),
    );
    expect(report, isNot(contains('UNRELIABLE split phone')));
  });

  test('INCOMPARABLE placement when full moved clusters against the base', () {
    final moved = _report(basePhone: _text(_phone, fullOnBig: false));
    final same = _report(basePhone: _text(_phone));

    expect(
      moved,
      contains(
        'INCOMPARABLE placement: full on cpu4 75.0 % against 0.0 % in the base',
      ),
    );
    expect(same, isNot(contains('INCOMPARABLE')));
  });

  test('a file with a missing stage throws FormatException', () {
    expect(
      () => BenchFile.parse(_text(_phone, skip: BenchStage.limiter)),
      throwsFormatException,
    );
    expect(() => BenchFile.parse('FBENCH done'), throwsFormatException);
  });
}
