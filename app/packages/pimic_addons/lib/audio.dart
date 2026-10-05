import 'dart:async';

import 'package:flutter/services.dart';

/// An Android input reported by AudioManager, or the actual AudioRecord route.
final class AudioInput {
  const AudioInput({required this.id, required this.type, required this.label});

  final int id;
  final String type;
  final String label;

  factory AudioInput.fromMap(Map<Object?, Object?> map) => AudioInput(
    id: (map['id']! as num).toInt(),
    type: map['type']! as String,
    label: map['label']! as String,
  );
}

/// Levels are derived from captured PCM samples, at most 20 times per second.
final class AudioLevel {
  const AudioLevel({
    required this.rms,
    required this.frames,
    required this.duration,
    this.input,
    this.limitReached = false,
  });

  final double rms;
  final int frames;
  final Duration duration;

  /// Null until Android exposes the actual route. Never a requested route guess.
  final AudioInput? input;
  final bool limitReached;

  factory AudioLevel.fromMap(Map<Object?, Object?> map) => AudioLevel(
    rms: (map['rms']! as num).toDouble(),
    frames: (map['frames']! as num).toInt(),
    duration: Duration(milliseconds: (map['durationMs']! as num).toInt()),
    input: _input(map['input']),
    limitReached: map['limitReached'] == true,
  );
}

/// Bounded RIFF/WAVE PCM16 mono audio at 16000 Hz, ready for explicit upload.
final class CapturedAudio {
  CapturedAudio({
    required this.wav,
    required this.frames,
    required this.duration,
    this.input,
  });

  final Uint8List wav;
  final int frames;
  final Duration duration;
  final AudioInput? input;

  factory CapturedAudio.fromMap(Map<Object?, Object?> map) => CapturedAudio(
    wav: map['wav']! as Uint8List,
    frames: (map['frames']! as num).toInt(),
    duration: Duration(milliseconds: (map['durationMs']! as num).toInt()),
    input: _input(map['input']),
  );
}

AudioInput? _input(Object? value) =>
    value == null ? null : AudioInput.fromMap(value as Map<Object?, Object?>);

/// Construction and input discovery never request microphone permission.
/// Each operation is local; networking belongs to the optional addon client.
abstract interface class AudioCapture {
  Future<List<AudioInput>> inputs();
  Future<void> start({int? preferredInputId});
  Future<CapturedAudio> stop();
  Future<void> cancel();
  Future<CapturedAudio?> importWav();
  Stream<AudioLevel> get levels;
  Future<void> dispose();
}

final class MethodChannelAudioCapture implements AudioCapture {
  MethodChannelAudioCapture({
    MethodChannel? channel,
    EventChannel? levelChannel,
  }) : _channel = channel ?? const MethodChannel('pimic_addons/audio'),
       _levelChannel =
           levelChannel ?? const EventChannel('pimic_addons/levels'),
       _owner = '${DateTime.now().microsecondsSinceEpoch}-${_nextOwner++}';

  static int _nextOwner = 0;
  final MethodChannel _channel;
  final EventChannel _levelChannel;
  final String _owner;
  Map<String, Object?> get _arguments => {'owner': _owner};
  StreamController<AudioLevel>? _levelController;
  _LevelHub? _hub;
  Stream<AudioLevel>? _levels;
  bool _disposed = false;

  void _checkActive() {
    if (_disposed) throw StateError('Audio capture has been disposed.');
  }

  @override
  Future<List<AudioInput>> inputs() async {
    _checkActive();
    final values = await _channel.invokeListMethod<Object?>('discoverInputs');
    return [
      for (final value in values ?? const <Object?>[])
        AudioInput.fromMap(value! as Map<Object?, Object?>),
    ];
  }

  @override
  Future<void> start({int? preferredInputId}) async {
    _checkActive();
    await _channel.invokeMethod<void>('startRecording', <String, Object?>{
      ..._arguments,
      'preferredInputId': ?preferredInputId,
    });
  }

  @override
  Future<CapturedAudio> stop() async {
    _checkActive();
    final map = await _channel.invokeMapMethod<Object?, Object?>(
      'stopRecording',
      _arguments,
    );
    if (map == null) throw StateError('Recording returned no audio.');
    return CapturedAudio.fromMap(map);
  }

  @override
  Future<void> cancel() async {
    if (_disposed) return;
    await _channel.invokeMethod<void>('cancel', _arguments);
  }

  @override
  Future<CapturedAudio?> importWav() async {
    _checkActive();
    final map = await _channel.invokeMapMethod<Object?, Object?>(
      'importWav',
      _arguments,
    );
    return map == null ? null : CapturedAudio.fromMap(map);
  }

  @override
  Stream<AudioLevel> get levels {
    _checkActive();
    if (_levels != null) return _levels!;
    // A single hub owns the BinaryMessenger handler for this channel. Old
    // instances cannot remove the handler installed for a newer owner.
    final hub = _hub = _LevelHub.forChannel(_levelChannel);
    late final StreamController<AudioLevel> controller;
    controller = StreamController<AudioLevel>.broadcast(
      onListen: () => hub.attach(_owner, controller),
      onCancel: () => hub.detach(_owner),
    );
    _levelController = controller;
    return _levels = controller.stream;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _hub?.detach(_owner);
    final controller = _levelController;
    if (controller != null) unawaited(controller.close());
    await _channel.invokeMethod<void>('dispose', _arguments);
  }
}

final class _LevelHub {
  _LevelHub(this.channel);
  static final _hubs = <String, _LevelHub>{};
  static _LevelHub forChannel(EventChannel channel) => _hubs.putIfAbsent(
    '${channel.name}:${identityHashCode(channel.binaryMessenger)}',
    () => _LevelHub(channel),
  );

  final EventChannel channel;
  String? _owner;
  StreamSubscription<Object?>? _subscription;
  Future<void> _transition = Future<void>.value();

  void attach(String owner, StreamController<AudioLevel> controller) {
    _owner = owner;
    _transition = _transition.then((_) async {
      await _subscription?.cancel();
      _subscription = null;
      if (_owner != owner || controller.isClosed) return;
      _subscription = channel
          .receiveBroadcastStream({'owner': owner})
          .listen(
            (Object? event) {
              final map = event! as Map<Object?, Object?>;
              if (_owner == owner &&
                  map['owner'] == owner &&
                  !controller.isClosed) {
                controller.add(AudioLevel.fromMap(map));
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              if (_owner == owner && !controller.isClosed) {
                controller.addError(error, stackTrace);
              }
            },
          );
    });
  }

  Future<void> detach(String owner) {
    if (_owner != owner) return Future<void>.value();
    _owner = null;
    _transition = _transition.then((_) async {
      await _subscription?.cancel();
      _subscription = null;
    });
    return _transition;
  }
}
