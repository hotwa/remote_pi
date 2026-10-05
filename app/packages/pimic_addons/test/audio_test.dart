import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pimic_addons/audio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/pimic_audio');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'discoverInputs' => [
              {'id': 14, 'type': 'wiredHeadset', 'label': 'Actual headset'},
            ],
            'stopRecording' => {
              'wav': Uint8List.fromList([1, 2, 3]),
              'frames': 16000,
              'durationMs': 1000,
              'input': {'id': 2, 'type': 'builtIn', 'label': 'Actual route'},
            },
            _ => null,
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('construction is idle and discovery does not start recording', () async {
    final capture = MethodChannelAudioCapture(channel: channel);
    expect(calls, isEmpty);
    final inputs = await capture.inputs();
    expect(inputs.single.id, 14);
    expect(inputs.single.type, 'wiredHeadset');
    expect(calls.map((call) => call.method), ['discoverInputs']);
  });

  test(
    'system automatic input omits preference; selected id is explicit',
    () async {
      final capture = MethodChannelAudioCapture(channel: channel);
      await capture.start();
      final owner = (calls.last.arguments as Map)['owner'];
      expect(owner, isA<String>());
      expect(
        (calls.last.arguments as Map).containsKey('preferredInputId'),
        isFalse,
      );
      await capture.start(preferredInputId: 14);
      expect(calls.last.arguments, {'owner': owner, 'preferredInputId': 14});
    },
  );

  test('stop returns actual route, sample frames and duration', () async {
    final capture = MethodChannelAudioCapture(channel: channel);
    await capture.start(preferredInputId: 14);
    final audio = await capture.stop();
    expect(audio.wav, [1, 2, 3]);
    expect(audio.frames, 16000);
    expect(audio.duration, const Duration(seconds: 1));
    expect(audio.input!.id, 2);
    expect(audio.input!.type, 'builtIn');
  });

  test('picker cancellation returns null; dispose is idempotent', () async {
    final capture = MethodChannelAudioCapture(channel: channel);
    expect(await capture.importWav(), isNull);
    await capture.dispose();
    await capture.dispose();
    await capture.cancel();
    expect(calls.map((call) => call.method), ['importWav', 'dispose']);
    await expectLater(capture.start(), throwsStateError);
  });

  test('unknown actual route remains null and RMS is passed from samples', () {
    final level = AudioLevel.fromMap({
      'rms': 0.25,
      'frames': 800,
      'durationMs': 50,
      'limitReached': false,
      'input': null,
    });
    expect(level.rms, 0.25);
    expect(level.input, isNull);
  });

  test(
    'late old cancel and dispose retain their original distinct owner',
    () async {
      final old = MethodChannelAudioCapture(channel: channel);
      final current = MethodChannelAudioCapture(channel: channel);
      await old.start();
      final oldOwner = (calls.last.arguments as Map)['owner'];
      await current.start();
      final newOwner = (calls.last.arguments as Map)['owner'];
      expect(newOwner, isNot(oldOwner));
      await old.cancel();
      expect(calls.last.arguments, {'owner': oldOwner});
      await old.dispose();
      expect(calls.last.arguments, {'owner': oldOwner});
      await current.stop();
      expect(calls.last.arguments, {'owner': newOwner});
    },
  );

  test('old unsubscribe cannot remove newer owner event handler', () async {
    const levels = EventChannel('test/pimic_levels');
    const codec = StandardMethodCodec();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final subscriptions = <MethodCall>[];
    messenger.setMockMethodCallHandler(
      const MethodChannel('test/pimic_levels'),
      (call) async {
        subscriptions.add(call);
        return null;
      },
    );
    final old = MethodChannelAudioCapture(
      channel: channel,
      levelChannel: levels,
    );
    final current = MethodChannelAudioCapture(
      channel: channel,
      levelChannel: levels,
    );
    final oldSubscription = old.levels.listen((_) {});
    await Future<void>.delayed(Duration.zero);
    final oldOwner = (subscriptions.last.arguments as Map)['owner'];
    final received = <AudioLevel>[];
    final currentSubscription = current.levels.listen(received.add);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final newOwner = (subscriptions.last.arguments as Map)['owner'];
    expect(newOwner, isNot(oldOwner));
    await oldSubscription.cancel();
    await old.dispose();
    await messenger.handlePlatformMessage(
      levels.name,
      codec.encodeSuccessEnvelope({
        'owner': newOwner,
        'rms': .5,
        'frames': 800,
        'durationMs': 50,
        'input': null,
      }),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);
    expect(received.single.rms, .5);
    expect(
      subscriptions
          .where((call) => call.method == 'cancel')
          .every((call) => (call.arguments as Map)['owner'] == oldOwner),
      isTrue,
    );
    await currentSubscription.cancel();
    await current.dispose();
    messenger.setMockMethodCallHandler(
      const MethodChannel('test/pimic_levels'),
      null,
    );
  });
}
