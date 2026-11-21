import 'package:flutter/services.dart';

const _channel = MethodChannel('fiatsonus/notification_permission');

/// Asks Android for the notification permission through `MainActivity`
/// (PLAN 4.6). Never throws: playback does not depend on the answer.
Future<void> requestNotificationPermission() async {
  try {
    await _channel.invokeMethod<bool>('request');
  } on MissingPluginException {
    // No handler (host tests, a detached activity).
  } on PlatformException {
    // A request is already pending, or the platform refused.
  }
}
