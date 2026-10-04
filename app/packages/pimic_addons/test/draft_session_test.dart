import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pimic_addons/api_client.dart';
import 'package:pimic_addons/audio.dart';
import 'package:pimic_addons/config.dart';
import 'package:pimic_addons/draft_session.dart';

const enabledConfig = AddonConfig(
  stt: SttProfile(enabled: true),
  optimizer: OptimizerProfile(
    enabled: true,
    baseUrl: 'http://localhost/v1',
    model: 'draft',
  ),
);
const builtinInput = AudioInput(
  id: 1,
  type: 'builtin',
  label: 'Built-in microphone',
);
const wiredInput = AudioInput(
  id: 2,
  type: 'wired',
  label: 'Headset microphone',
);

class FakeCapture implements AudioCapture {
  final events = StreamController<AudioLevel>.broadcast(sync: true);
  final audio = CapturedAudio(
    wav: Uint8List(44),
    frames: 16000,
    duration: const Duration(seconds: 1),
    input: wiredInput,
  );
  int starts = 0, stops = 0, cancels = 0, disposals = 0, imports = 0;
  int? requestedInput;
  Object? startError;
  Completer<void>? startCompletion;
  Completer<CapturedAudio>? stopCompletion;
  Completer<CapturedAudio?>? importCompletion;
  Completer<void>? cancelCompletion, disposeCompletion;
  Object? cancelFailure, disposeFailure;
  @override
  Stream<AudioLevel> get levels => events.stream;
  @override
  Future<List<AudioInput>> inputs() async => [builtinInput, wiredInput];
  @override
  Future<void> start({int? preferredInputId}) async {
    starts++;
    requestedInput = preferredInputId;
    if (startError != null) throw startError!;
    await startCompletion?.future;
  }

  @override
  Future<CapturedAudio> stop() async {
    stops++;
    return stopCompletion == null ? audio : stopCompletion!.future;
  }

  @override
  Future<CapturedAudio?> importWav() async {
    imports++;
    return importCompletion == null ? audio : importCompletion!.future;
  }

  @override
  Future<void> cancel() async {
    cancels++;
    await cancelCompletion?.future;
    if (cancelFailure != null) throw cancelFailure!;
  }

  @override
  Future<void> dispose() async {
    disposals++;
    await disposeCompletion?.future;
    await events.close();
    if (disposeFailure != null) throw disposeFailure!;
  }
}

class FakeClient extends AddonApiClient {
  int sttCalls = 0, optimizeCalls = 0;
  AddonCancellation? lastCancellation;
  Completer<String>? sttCompletion, optimizeCompletion;
  Object? failure;
  @override
  Future<String> transcribe({
    required SttProfile profile,
    required Uint8List wav,
    AddonCancellation? cancellation,
  }) async {
    sttCalls++;
    lastCancellation = cancellation;
    if (failure != null) throw failure!;
    return sttCompletion == null ? 'raw transcript' : sttCompletion!.future;
  }

  @override
  Future<String> optimize({
    required OptimizerProfile profile,
    required String text,
    AddonCancellation? cancellation,
  }) async {
    optimizeCalls++;
    lastCancellation = cancellation;
    if (failure != null) throw failure!;
    return optimizeCompletion == null
        ? 'cleaned suggestion'
        : optimizeCompletion!.future;
  }
}

void main() {
  test('constructing and discovery never record or contact APIs', () async {
    final capture = FakeCapture();
    final client = FakeClient();
    final session = DraftSession(
      config: enabledConfig,
      capture: capture,
      client: client,
      initialText: 'initial',
    );
    await session.loadInputs();
    expect(capture.starts, 0);
    expect(client.sttCalls, 0);
    expect(client.optimizeCalls, 0);
    expect(session.availableInputs, hasLength(2));
    expect(session.useDraft(), 'initial');
    session.dispose();
  });

  test(
    'manual stop transcribes only, with real route and explicit cleanup apply',
    () async {
      final capture = FakeCapture();
      final client = FakeClient();
      final session = DraftSession(
        config: enabledConfig,
        capture: capture,
        client: client,
      );
      session.selectInput(1);
      await session.startRecording();
      expect(capture.requestedInput, 1);
      expect(client.sttCalls, 0);
      capture.events.add(
        const AudioLevel(
          rms: .42,
          frames: 100,
          duration: Duration(milliseconds: 6),
          input: wiredInput,
        ),
      );
      expect(session.level!.input, wiredInput);
      await session.stopRecording();
      expect(session.editableDraft, 'raw transcript');
      expect(session.rawTranscript, 'raw transcript');
      expect(client.optimizeCalls, 0);
      await session.optimize();
      expect(session.editableDraft, 'raw transcript');
      expect(session.suggestionSource, 'raw transcript');
      session.useSuggestion();
      expect(session.editableDraft, 'cleaned suggestion');
      expect(session.useDraft(), 'cleaned suggestion');
      session.dispose();
    },
  );

  test(
    'import explicitly transcribes and does not request microphone',
    () async {
      final capture = FakeCapture();
      final client = FakeClient();
      final session = DraftSession(
        config: enabledConfig,
        capture: capture,
        client: client,
      );
      await session.importWav();
      expect(capture.imports, 1);
      expect(capture.starts, 0);
      expect(session.editableDraft, 'raw transcript');
      session.dispose();
    },
  );

  test('limit event stops once and only creates a transcript draft', () async {
    final capture = FakeCapture();
    final client = FakeClient();
    final session = DraftSession(
      config: enabledConfig,
      capture: capture,
      client: client,
    );
    await session.startRecording();
    capture.events.add(
      const AudioLevel(
        rms: .1,
        frames: 960000,
        duration: Duration(seconds: 60),
        limitReached: true,
      ),
    );
    await pumpEventQueue();
    expect(capture.stops, 1);
    expect(session.editableDraft, 'raw transcript');
    expect(client.optimizeCalls, 0);
    session.dispose();
  });

  test(
    'edits during transcription preserve newer draft and retain raw result',
    () async {
      final capture = FakeCapture();
      final client = FakeClient()..sttCompletion = Completer<String>();
      final session = DraftSession(
        config: enabledConfig,
        capture: capture,
        client: client,
        initialText: 'old',
      );
      final operation = session.importWav();
      await pumpEventQueue();
      session.editDraft('new user edit');
      client.sttCompletion!.complete('late transcript');
      await operation;
      expect(session.editableDraft, 'new user edit');
      expect(session.rawTranscript, 'late transcript');
      session.useTranscript();
      expect(session.editableDraft, 'late transcript');
      session.dispose();
    },
  );

  test(
    'edits during cleanup discard suggestion and preserve original text',
    () async {
      final client = FakeClient()..optimizeCompletion = Completer<String>();
      final session = DraftSession(
        config: enabledConfig,
        client: client,
        initialText: 'original',
      );
      final operation = session.optimize();
      session.editDraft('new edit');
      client.optimizeCompletion!.complete('late suggestion');
      await operation;
      expect(session.editableDraft, 'new edit');
      expect(session.suggestedDraft, isNull);
      expect(session.canUseSuggestion, isFalse);
      session.dispose();
    },
  );

  test(
    'cancel invalidates pending result even if client ignores cancellation',
    () async {
      final client = FakeClient()..optimizeCompletion = Completer<String>();
      final session = DraftSession(
        config: enabledConfig,
        client: client,
        initialText: 'original',
      );
      final operation = session.optimize();
      final cancellation = client.lastCancellation!;
      await session.cancelCurrent();
      expect(cancellation.isCancelled, isTrue);
      client.optimizeCompletion!.complete('late');
      await operation;
      expect(session.suggestedDraft, isNull);
      expect(session.editableDraft, 'original');
      expect(session.phase, DraftPhase.ready);
      session.dispose();
    },
  );

  test('late capture start after cancellation is cleaned up', () async {
    final capture = FakeCapture()..startCompletion = Completer<void>();
    final session = DraftSession(config: enabledConfig, capture: capture);
    final operation = session.startRecording();
    await session.cancelCurrent();
    expect(session.canRecord, isFalse);
    capture.startCompletion!.complete();
    await operation;
    expect(capture.cancels, greaterThanOrEqualTo(2));
    expect(session.isRecording, isFalse);
    session.dispose();
  });

  test('target or configuration change discards pending result', () async {
    var current = true;
    final client = FakeClient()..optimizeCompletion = Completer<String>();
    final session = DraftSession(
      config: enabledConfig,
      client: client,
      initialText: 'original',
      targetIsCurrent: () => current,
    );
    final operation = session.optimize();
    current = false;
    client.optimizeCompletion!.complete('wrong target');
    await operation;
    expect(session.suggestedDraft, isNull);
    expect(session.useDraft(), isNull);
    current = true;
    client.optimizeCompletion = Completer<String>();
    final second = session.optimize();
    await session.updateConfig(const AddonConfig());
    client.optimizeCompletion!.complete('old profile');
    await second;
    expect(session.suggestedDraft, isNull);
    expect(session.canOptimize, isFalse);
    session.dispose();
  });

  test(
    'failures preserve text and never expose platform exception details',
    () async {
      final capture = FakeCapture()
        ..startError = PlatformException(
          code: 'permission',
          message: 'secret device detail',
        );
      final client = FakeClient()
        ..failure = const AddonException('Service request failed (HTTP 503).');
      final session = DraftSession(
        config: enabledConfig,
        capture: capture,
        client: client,
        initialText: 'keep',
      );
      await session.startRecording();
      expect(session.error, isNot(contains('secret')));
      expect(session.canImport, isTrue);
      await session.optimize();
      expect(session.editableDraft, 'keep');
      expect(session.error, 'Service request failed (HTTP 503).');
      session.dispose();
    },
  );

  test(
    'text works without capture and controls bypass cleanup model',
    () async {
      final client = FakeClient();
      final session = DraftSession(
        config: enabledConfig,
        client: client,
        initialText: '/abort',
      );
      expect(session.canRecord, isFalse);
      await session.optimize();
      expect(client.optimizeCalls, 0);
      expect(session.useDraft(), '/abort');
      session.editDraft('停止');
      await session.optimize();
      expect(client.optimizeCalls, 0);
      session.editDraft('停一下，不要执行命令，也不要删除文件。');
      await session.optimize();
      expect(client.optimizeCalls, 0);
      expect(session.suggestedDraft, isNull);
      session.editDraft('Describe how the stop button works');
      await session.optimize();
      expect(client.optimizeCalls, 1);
      session.dispose();
    },
  );

  test('cancelled transcription cannot overwrite a newer operation', () async {
    final capture = FakeCapture();
    final firstResult = Completer<String>();
    final secondResult = Completer<String>();
    final client = FakeClient()..sttCompletion = firstResult;
    final session = DraftSession(
      config: enabledConfig,
      capture: capture,
      client: client,
    );
    final first = session.importWav();
    await pumpEventQueue();
    await session.cancelCurrent();
    client.sttCompletion = secondResult;
    final second = session.importWav();
    await pumpEventQueue();
    secondResult.complete('current transcript');
    await second;
    firstResult.complete('obsolete transcript');
    await first;
    expect(session.editableDraft, 'current transcript');
    expect(session.rawTranscript, 'current transcript');
    expect(session.phase, DraftPhase.ready);
    session.dispose();
  });

  test('microphone stream error cancels capture and preserves text', () async {
    final capture = FakeCapture();
    final client = FakeClient();
    final session = DraftSession(
      config: enabledConfig,
      capture: capture,
      client: client,
      initialText: 'keep',
    );
    await session.startRecording();
    capture.events.addError(StateError('private input error'));
    await pumpEventQueue();
    expect(session.isRecording, isFalse);
    expect(session.editableDraft, 'keep');
    expect(capture.cancels, greaterThan(0));
    expect(client.sttCalls, 0);
    expect(session.error, isNot(contains('private')));
    session.dispose();
  });

  test('cleanupDone waits for queued cancel and native dispose', () async {
    final capture = FakeCapture()
      ..cancelCompletion = Completer<void>()
      ..disposeCompletion = Completer<void>();
    final session = DraftSession(config: enabledConfig, capture: capture);
    var done = false;
    session.cleanupDone.then((_) => done = true);
    final cancellation = session.cancelCurrent();
    session.dispose();
    await pumpEventQueue();
    expect(capture.cancels, 1);
    expect(capture.disposals, 0);
    expect(done, isFalse);
    capture.cancelCompletion!.complete();
    await cancellation;
    await pumpEventQueue();
    expect(capture.disposals, 1);
    expect(done, isFalse);
    capture.disposeCompletion!.complete();
    await session.cleanupDone;
    expect(done, isTrue);
  });

  test(
    'cleanupDone waits for a late start and its final cancellation',
    () async {
      final capture = FakeCapture()..startCompletion = Completer<void>();
      final session = DraftSession(config: enabledConfig, capture: capture);
      final start = session.startRecording();
      var done = false;
      session.cleanupDone.then((_) => done = true);
      session.dispose();
      await pumpEventQueue();
      expect(capture.cancels, 1);
      expect(capture.disposals, 0);
      expect(done, isFalse);
      capture.startCompletion!.complete();
      await start;
      await session.cleanupDone;
      expect(capture.cancels, 2);
      expect(capture.disposals, 1);
      expect(done, isTrue);
    },
  );

  test(
    'cleanup completion survives native cancel and dispose failures',
    () async {
      final capture = FakeCapture()
        ..cancelFailure = StateError('private cancel detail')
        ..disposeFailure = StateError('private dispose detail');
      final session = DraftSession(config: enabledConfig, capture: capture);
      session.dispose();
      await session.cleanupDone;
      expect(capture.cancels, 1);
      expect(capture.disposals, 1);
      expect(session.useDraft(), isNull);
    },
  );

  test('dispose invalidates network work and releases local capture', () async {
    final capture = FakeCapture();
    final client = FakeClient()..optimizeCompletion = Completer<String>();
    final session = DraftSession(
      config: enabledConfig,
      capture: capture,
      client: client,
      initialText: 'draft',
    );
    final operation = session.optimize();
    final cancellation = client.lastCancellation!;
    session.dispose();
    client.optimizeCompletion!.complete('late');
    await operation;
    await pumpEventQueue();
    expect(cancellation.isCancelled, isTrue);
    expect(capture.disposals, 1);
    expect(session.suggestedDraft, isNull);
  });
}
