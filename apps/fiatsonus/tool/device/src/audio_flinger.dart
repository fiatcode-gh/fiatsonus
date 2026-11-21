/// A live track row of an AudioFlinger thread's track table.
class AudioFlingerTrack {
  const AudioFlingerTrack({
    required this.id,
    required this.pid,
    required this.uid,
    required this.underruns,
  });

  final int id;
  final int pid;
  final int uid;
  final int underruns;
}

/// A playback or record thread of `dumpsys media.audio_flinger`.
class AudioFlingerThread {
  const AudioFlingerThread({
    required this.name,
    required this.sampleRate,
    required this.tracks,
  });

  final String name;
  final int? sampleRate;
  final List<AudioFlingerTrack> tracks;
}

final _threadHeader = RegExp(r'^\w+ thread 0x[0-9a-f]+, name (\S+?),');
final _sampleRate = RegExp(r'^  Sample rate: (\d+) Hz');
final _trackCount = RegExp(r'^\s+\d+ Tracks');
// Optional type letter, track id, active flag, client pid/uid. Rows of a
// thread's local log start with a timestamp and never match.
final _trackRow = RegExp(
  r'^\s+(?:\S\s+)?(\d+)\s+(?:yes|no)\s+(\d+)/\s*(\d+)\s',
);

/// Parses the threads of a `dumpsys media.audio_flinger` dump with the rows
/// of their live track tables.
List<AudioFlingerThread> parseAudioFlinger(String text) {
  final threads = <AudioFlingerThread>[];
  String? name;
  int? sampleRate;
  var tracks = <AudioFlingerTrack>[];

  void closeThread() {
    if (name != null) {
      threads.add(
        AudioFlingerThread(name: name, sampleRate: sampleRate, tracks: tracks),
      );
    }
  }

  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final header = _threadHeader.firstMatch(line);
    if (header != null) {
      closeThread();
      name = header.group(1);
      sampleRate = null;
      tracks = [];
      continue;
    }
    if (name == null) continue;
    final rate = _sampleRate.firstMatch(line);
    if (rate != null) {
      sampleRate = int.parse(rate.group(1)!);
      continue;
    }
    if (!_trackCount.hasMatch(line) || i + 1 >= lines.length) continue;
    final columns = lines[i + 1];
    if (!columns.contains('Client(pid/uid)')) continue;
    final underrunsAt = columns.indexOf(' Underruns');
    if (underrunsAt < 0) {
      throw FormatException('track table of $name has no Underruns column');
    }
    final underrunsEnd = underrunsAt + ' Underruns'.length;
    for (i += 2; i < lines.length; i++) {
      final row = _trackRow.firstMatch(lines[i]);
      if (row == null) break;
      tracks.add(
        AudioFlingerTrack(
          id: int.parse(row.group(1)!),
          pid: int.parse(row.group(2)!),
          uid: int.parse(row.group(3)!),
          underruns: _cellEndingAt(lines[i], underrunsEnd, name),
        ),
      );
    }
    i--;
  }
  closeThread();
  return threads;
}

/// AudioFlinger right-aligns each cell with the end of its column title.
int _cellEndingAt(String row, int end, String thread) {
  final value = row.length >= end
      ? int.tryParse(row.substring(0, end).split(' ').last)
      : null;
  if (value == null || (row.length > end && row[end] != ' ')) {
    throw FormatException('no Underruns cell in a track row of $thread', row);
  }
  return value;
}

List<AudioFlingerTrack> tracksOfPid(
  List<AudioFlingerThread> threads,
  int pid,
) => [
  for (final thread in threads)
    for (final track in thread.tracks)
      if (track.pid == pid) track,
];

int underrunsOfPid(List<AudioFlingerThread> threads, int pid) =>
    tracksOfPid(threads, pid).fold(0, (sum, t) => sum + t.underruns);

/// The sample rate of the first thread that holds a track of [pid].
int? sampleRateOfPid(List<AudioFlingerThread> threads, int pid) {
  for (final thread in threads) {
    if (thread.tracks.any((t) => t.pid == pid)) return thread.sampleRate;
  }
  return null;
}
