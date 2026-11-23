import 'package:flutter/services.dart';

const _channel = MethodChannel('fiatsonus/playback_notification');

/// Asks `MainActivity` to cancel audio_service's notification once Android
/// has taken it out of the foreground (PLAN 4.6). Returns at once; never
/// throws.
Future<void> clearPlaybackNotification() async {
  try {
    await _channel.invokeMethod<void>('clear');
  } on MissingPluginException {
    // No handler (host tests).
  } on PlatformException {
    // Nothing to do: the notification stays until the next stop.
  }
}
