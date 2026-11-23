import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';

import '../engine/device_sink.dart';

/// Name of the root-isolate relay's port.
const String kPcmRelayPortName = 'fiatsonus.probe.pcm';

/// Starts the root-isolate side of the `pcm` probe sink.
///
/// `flutter_pcm_sound` signals demand through a `MethodChannel`, which only
/// the root isolate can receive, so the root isolate owns the plugin and
/// relays: chunks from the engine isolate are fed, each feed callback's
/// `remainingFrames` is sent back.
void startPcmRelay() {
  final port = ReceivePort();
  IsolateNameServer.removePortNameMapping(kPcmRelayPortName);
  IsolateNameServer.registerPortWithName(port.sendPort, kPcmRelayPortName);
  SendPort? reply;
  var chain = Future<void>.value();
  void then(Future<void> Function() step) => chain = chain.then((_) => step());

  port.listen((message) {
    switch (message) {
      case ['hello', final SendPort engine]:
        reply = engine;
      case ['start', final int sampleRate]:
        then(() async {
          await FlutterPcmSound.setLogLevel(LogLevel.none);
          await FlutterPcmSound.setup(sampleRate: sampleRate, channelCount: 2);
          await FlutterPcmSound.setFeedThreshold(4096);
          FlutterPcmSound.setFeedCallback(
            (int remaining) => reply?.send(['demand', remaining]),
          );
        });
      case ['chunk', final Int16List chunk]:
        then(
          () => FlutterPcmSound.feed(
            PcmArrayInt16(bytes: ByteData.sublistView(chunk)),
          ),
        );
      case ['stop']:
        then(() async {
          FlutterPcmSound.setFeedCallback(null);
          await FlutterPcmSound.release();
        });
    }
  });
}

/// The engine-isolate side of the `pcm` probe sink: `write` waits for a
/// demand relayed by [startPcmRelay] (the first one is implicit), then sends
/// the chunk to the root isolate. Non-compliant by design (PLAN 2).
final class PcmRelaySink implements DeviceSink {
  SendPort? _relay;
  Completer<void> _demand = Completer<void>();
  bool _open = false;
  bool _sentChunk = false;
  int _underruns = 0;

  @override
  String get id => 'pcm';

  @override
  int get underruns => _underruns;

  @override
  int get starvedMicros => 0;

  @override
  Future<void> start({required int sampleRate, required int channels}) async {
    if (channels != 2) {
      throw ArgumentError.value(channels, 'channels', 'must be 2');
    }
    var relay = _relay;
    if (relay == null) {
      relay = IsolateNameServer.lookupPortByName(kPcmRelayPortName);
      if (relay == null) throw StateError('no $kPcmRelayPortName port');
      final replies = ReceivePort();
      replies.listen(_onReply);
      relay.send(['hello', replies.sendPort]);
      _relay = relay;
    }
    _underruns = 0;
    _sentChunk = false;
    _demand = Completer<void>()..complete();
    _open = true;
    relay.send(['start', sampleRate]);
  }

  void _onReply(Object? message) {
    if (message case ['demand', final int remaining] when _open) {
      if (remaining == 0 && _sentChunk) _underruns++;
      if (!_demand.isCompleted) _demand.complete();
    }
  }

  @override
  Future<void> write(Int16List interleaved) async {
    await _demand.future;
    _demand = Completer<void>();
    _sentChunk = true;
    _relay!.send(['chunk', interleaved]);
  }

  @override
  Future<void> stop() async {
    _open = false;
    _relay?.send(['stop']);
  }
}
