/// The table of `cpu_top.txt` from a `getCpuSamples` response in its JSON
/// form: the sample count, the period, then the [limit] functions with the
/// most exclusive ticks (ties: more inclusive ticks first), each with its
/// exclusive and inclusive ticks as % of the sample count, its kind and its
/// name (`<class>.<name>` when a class owns it).
String cpuTop(Map<String, Object?> cpuSamples, {int limit = 40}) {
  final count = cpuSamples['sampleCount']! as int;
  final functions = [
    for (final f in cpuSamples['functions']! as List<Object?>)
      f! as Map<String, Object?>,
  ];
  int ticks(Map<String, Object?> f, String key) => f[key]! as int;
  functions.sort((a, b) {
    final byExclusive = ticks(b, 'exclusiveTicks') - ticks(a, 'exclusiveTicks');
    return byExclusive != 0
        ? byExclusive
        : ticks(b, 'inclusiveTicks') - ticks(a, 'inclusiveTicks');
  });
  String pct(int n) => (n * 100 / count).toStringAsFixed(1).padLeft(6);
  return [
    'sample_count=$count',
    'sample_period_us=${cpuSamples['samplePeriod']}',
    ' excl%   incl%  kind    function',
    for (final f in functions.take(limit))
      '${pct(ticks(f, 'exclusiveTicks'))}  ${pct(ticks(f, 'inclusiveTicks'))}  '
          '${(f['kind']! as String).padRight(6)}  '
          '${_name(f['function']! as Map<String, Object?>)}',
  ].join('\n');
}

String _name(Map<String, Object?> function) {
  final name = function['name']! as String;
  final owner = function['owner'];
  if (owner is Map<String, Object?> && owner['type'] == '@Class') {
    return '${owner['name']}.$name';
  }
  return name;
}
