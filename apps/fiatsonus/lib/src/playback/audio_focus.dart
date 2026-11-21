import 'package:audio_session/audio_session.dart';

/// A change of the app's audio focus (PLAN 4.7).
enum FocusChange { lossTransient, lossPermanent, gain }

/// The app's audio focus.
abstract interface class AudioFocus {
  /// Requests focus; true when it was granted.
  Future<bool> request();

  /// Gives focus up.
  Future<void> abandon();

  /// Focus changes after a granted [request]; a broadcast stream.
  Stream<FocusChange> get changes;
}

/// [AudioFocus] through `audio_session`: media/music attributes, gain type
/// `gain`, pause when another app asks to duck.
final class AudioSessionFocus implements AudioFocus {
  final AudioSession _session;

  AudioSessionFocus._(this._session);

  static Future<AudioSessionFocus> create() async {
    final session = await AudioSession.instance;
    await session.configure(
      const AudioSessionConfiguration(
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: true,
      ),
    );
    return AudioSessionFocus._(session);
  }

  @override
  Future<bool> request() => _session.setActive(true);

  @override
  Future<void> abandon() => _session.setActive(false);

  @override
  Stream<FocusChange> get changes => _session.interruptionEventStream.map(
    (event) => switch (event) {
      AudioInterruptionEvent(begin: false) => FocusChange.gain,
      AudioInterruptionEvent(type: AudioInterruptionType.unknown) =>
        FocusChange.lossPermanent,
      _ => FocusChange.lossTransient,
    },
  );
}
