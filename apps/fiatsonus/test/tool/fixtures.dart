import 'dart:io';

/// Text captured from the phone, read relative to the package root (the
/// working directory of `flutter test`).
String fixture(String name) =>
    File('test/tool/fixtures/$name').readAsStringSync();

/// The pid of the media player that owns the active track of
/// `audio_flinger_active.txt` and the ServiceRecord of
/// `services_other_app.txt`.
const kPlayerPid = 24608;

/// `audio_flinger_active.txt` with the Underruns cell of the player's track
/// (id 214) set to [underruns], right-aligned like AudioFlinger prints it.
String activeAudioFlinger({int underruns = 0}) {
  final lines = fixture('audio_flinger_active.txt').split('\n');
  final row = lines.indexWhere((l) => l.contains('   214    yes   24608/'));
  lines[row] = lines[row].replaceFirst(
    ' A         0 ',
    ' A ${underruns.toString().padLeft(9)} ',
  );
  return lines.join('\n');
}

/// `/proc/<pid>/stat` of the fixture with utime and stime replaced.
String procStat({required int utime, required int stime}) =>
    _withTimes(fixture('proc_stat.txt').trim(), utime, stime);

/// The captured task stats, with [extraTicks] added to the utime of the
/// threads whose tid is a key.
String taskStats({Map<int, int> extraTicks = const {}}) =>
    fixture('task_stat.txt')
        .trim()
        .split('\n')
        .map((line) {
          final tid = int.parse(line.substring(0, line.indexOf(' ')));
          final extra = extraTicks[tid];
          if (extra == null) return line;
          final fields = _fieldsAfterComm(line);
          return _withTimes(
            line,
            int.parse(fields[11]) + extra,
            int.parse(fields[12]),
          );
        })
        .join('\n');

List<String> _fieldsAfterComm(String line) =>
    line.substring(line.lastIndexOf(')') + 2).split(' ');

String _withTimes(String line, int utime, int stime) {
  final head = line.substring(0, line.lastIndexOf(')') + 2);
  final fields = _fieldsAfterComm(line);
  fields[11] = '$utime';
  fields[12] = '$stime';
  return head + fields.join(' ');
}

/// `services_other_app.txt` rewritten into the shape of the app's
/// `audio_service` record.
String audioServiceServices({bool foreground = true, String uid = 'u0a105'}) =>
    fixture('services_other_app.txt')
        .replaceAll(
          'com.android.bbkmusic/.service.MusicService',
          'dev.fiatcode.fiatsonus/com.ryanheise.audioservice.AudioService',
        )
        .replaceFirst('isForeground=false', 'isForeground=$foreground')
        .replaceAll(
          'com.android.bbkmusic/u0a105}',
          'dev.fiatcode.fiatsonus/$uid}',
        );

/// A whole `logcat -v epoch` line carrying an `FSTAT v=1` message.
String fstatLine({
  required int epochMs,
  int version = 1,
  int rate = 48000,
  required int playUs,
  required int renderUs,
  int maxRenderUs = 900,
  required int frames,
  int underruns = 0,
  int starvedUs = 0,
  int overlaps = 0,
  int faults = 0,
  int sessions = 1,
}) {
  final seconds = epochMs ~/ 1000;
  final millis = (epochMs % 1000).toString().padLeft(3, '0');
  return '         $seconds.$millis $kPlayerPid 24650 I flutter : '
      'FSTAT v=$version sink=soloud rate=$rate play_us=$playUs '
      'render_us=$renderUs max_render_us=$maxRenderUs frames=$frames '
      'underruns=$underruns starved_us=$starvedUs overlaps=$overlaps '
      'faults=$faults sessions=$sessions';
}
