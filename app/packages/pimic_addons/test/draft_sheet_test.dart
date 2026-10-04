import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pimic_addons/audio.dart';
import 'package:pimic_addons/config.dart';
import 'package:pimic_addons/draft_sheet.dart';

import 'draft_session_test.dart'
    show FakeCapture, FakeClient, enabledConfig, wiredInput;

Future<void> openSheet(
  WidgetTester tester, {
  AddonConfig config = enabledConfig,
  FakeCapture? capture,
  FakeClient? client,
  String initialText = '',
  void Function(String?)? onResult,
  bool Function()? targetIsCurrent,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final result = await showDraftSheet(
                context,
                config: config,
                initialText: initialText,
                capture: capture,
                client: client,
                targetIsCurrent: targetIsCurrent,
              );
              onResult?.call(result);
            },
            child: const Text('Open draft'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open draft'));
  await tester.pumpAndSettle();
}

// Broadcast StreamSubscription.cancel uses a shared completed Future whose
// event-loop completion can live outside WidgetTester's FakeAsync zone.
Future<void> flushCleanup(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pump();
}

Future<void> requestCleanup(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('optimize-this-draft')));
  await tester.tap(find.byKey(const Key('optimize-this-draft')));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('optimize-draft')));
  await tester.tap(find.byKey(const Key('optimize-draft')));
}

class _NativeOwner {
  String? active;
}

class _OwnerCapture extends FakeCapture {
  _OwnerCapture(this.owner, this.name);
  final _NativeOwner owner;
  final String name;

  @override
  Future<void> start({int? preferredInputId}) async {
    await super.start(preferredInputId: preferredInputId);
    owner.active = name;
  }

  @override
  Future<void> cancel() async {
    await super.cancel();
    owner.active = null;
  }

  @override
  Future<void> dispose() async {
    await super.dispose();
    owner.active = null;
  }
}

void main() {
  testWidgets(
    'opening is local; text-only draft returns only after explicit use',
    (tester) async {
      final client = FakeClient();
      String? result;
      await openSheet(
        tester,
        config: const AddonConfig(
          optimizer: OptimizerProfile(
            enabled: true,
            baseUrl: 'http://localhost/v1',
            model: 'draft',
          ),
        ),
        client: client,
        initialText: 'initial',
        onResult: (value) => result = value,
      );
      expect(client.sttCalls, 0);
      expect(client.optimizeCalls, 0);
      expect(find.byKey(const Key('record-toggle')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('editable-draft')),
        'edited text',
      );
      expect(result, isNull);
      await tester.tap(find.byKey(const Key('use-draft')));
      await tester.pumpAndSettle();
      expect(result, 'edited text');
    },
  );

  testWidgets(
    'unchecked transcription makes no cleanup request and resets on reopen',
    (tester) async {
      final client = FakeClient();
      final capture = FakeCapture();
      String? result;
      await openSheet(
        tester,
        capture: capture,
        client: client,
        onResult: (value) => result = value,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const Key('optimize-this-draft')),
            )
            .value,
        isFalse,
      );
      await tester.tap(find.byKey(const Key('import-wav')));
      await tester.pumpAndSettle();
      expect(client.sttCalls, 1);
      expect(client.optimizeCalls, 0);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('optimize-draft')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('use-draft')));
      await tester.pumpAndSettle();
      await flushCleanup(tester);
      expect(result, 'raw transcript');
      expect(client.optimizeCalls, 0);

      await tester.tap(find.text('Open draft'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('optimize-this-draft')));
      await tester.tap(find.byKey(const Key('optimize-this-draft')));
      await tester.pumpAndSettle();
      expect(client.optimizeCalls, 0);
      await tester.tap(find.byTooltip('Close draft'));
      await tester.pumpAndSettle();
      await flushCleanup(tester);
      await tester.tap(find.text('Open draft'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const Key('optimize-this-draft')),
            )
            .value,
        isFalse,
      );
      await tester.tap(find.byTooltip('Close draft'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'unchecking cancels cleanup and rejects a late result after reselecting',
    (tester) async {
      final client = FakeClient()..optimizeCompletion = Completer<String>();
      await openSheet(tester, client: client, initialText: 'keep my original');
      await requestCleanup(tester);
      await tester.pump();
      expect(client.optimizeCalls, 1);
      final cancellation = client.lastCancellation!;
      await tester.ensureVisible(find.byKey(const Key('optimize-this-draft')));
      await tester.tap(find.byKey(const Key('optimize-this-draft')));
      await tester.pumpAndSettle();
      expect(cancellation.isCancelled, isTrue);
      await tester.tap(find.byKey(const Key('optimize-this-draft')));
      await tester.pumpAndSettle();
      client.optimizeCompletion!.complete('late rewritten text');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('use-suggestion')), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('editable-draft')))
            .controller!
            .text,
        'keep my original',
      );
      expect(client.optimizeCalls, 1);
      await tester.tap(find.byTooltip('Close draft'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'unchecking discards a finished suggestion without replacing text',
    (tester) async {
      final client = FakeClient();
      await openSheet(tester, client: client, initialText: 'original text');
      await requestCleanup(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('use-suggestion')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('optimize-this-draft')));
      await tester.tap(find.byKey(const Key('optimize-this-draft')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('optimize-this-draft')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('use-suggestion')), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('editable-draft')))
            .controller!
            .text,
        'original text',
      );
      expect(client.optimizeCalls, 1);
      await tester.tap(find.byTooltip('Close draft'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'unconfigured cleanup cannot be selected and text remains usable',
    (tester) async {
      final client = FakeClient();
      String? result;
      await openSheet(
        tester,
        config: const AddonConfig(),
        client: client,
        initialText: 'use without extra APIs',
        onResult: (value) => result = value,
      );
      final checkbox = tester.widget<CheckboxListTile>(
        find.byKey(const Key('optimize-this-draft')),
      );
      expect(checkbox.value, isFalse);
      expect(checkbox.onChanged, isNull);
      expect(find.byKey(const Key('optimize-draft')), findsNothing);
      await tester.tap(find.byKey(const Key('use-draft')));
      await tester.pumpAndSettle();
      expect(result, 'use without extra APIs');
      expect(client.optimizeCalls, 0);
    },
  );

  testWidgets(
    'microphone choice and RMS show actual route instead of requested route',
    (tester) async {
      final capture = FakeCapture();
      final client = FakeClient();
      await openSheet(tester, capture: capture, client: client);
      expect(capture.starts, 0);
      expect(client.sttCalls, 0);
      expect(
        tester
            .widget<LinearProgressIndicator>(find.byKey(const Key('rms-meter')))
            .value,
        0,
      );
      expect(find.text('Actual recorded input: Unknown'), findsOneWidget);
      await tester.tap(find.byKey(const Key('audio-input')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Built-in microphone (builtin)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('record-toggle')));
      await tester.pump();
      capture.events.add(
        const AudioLevel(
          rms: .01,
          frames: 16000,
          duration: Duration(seconds: 1),
          input: wiredInput,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(capture.requestedInput, 1);
      expect(
        find.text('Actual recorded input: Headset microphone (wired)'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<LinearProgressIndicator>(find.byKey(const Key('rms-meter')))
            .value,
        closeTo(1 / 3, .001),
      );
      expect(find.textContaining('PCM RMS: 0.010'), findsOneWidget);
      expect(find.textContaining('-40.0 dBFS'), findsOneWidget);
      capture.events.add(
        const AudioLevel(
          rms: 0,
          frames: 32000,
          duration: Duration(seconds: 2),
          input: wiredInput,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(
        tester
            .widget<LinearProgressIndicator>(find.byKey(const Key('rms-meter')))
            .value,
        0,
      );
      expect(find.textContaining('−∞ dBFS'), findsOneWidget);
      await tester.tap(find.byTooltip('Close draft'));
      await tester.pumpAndSettle();
      expect(capture.cancels, greaterThan(0));
      expect(capture.disposals, 1);
    },
  );

  testWidgets(
    'cleanup displays both versions and requires explicit suggestion and draft use',
    (tester) async {
      final client = FakeClient();
      final capture = FakeCapture();
      String? result;
      await openSheet(
        tester,
        capture: capture,
        client: client,
        initialText: 'original intent',
        onResult: (value) => result = value,
      );
      await requestCleanup(tester);
      await tester.pumpAndSettle();
      expect(find.text('Original text'), findsOneWidget);
      expect(find.text('original intent'), findsWidgets);
      expect(find.text('cleaned suggestion'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('editable-draft')))
            .controller!
            .text,
        'original intent',
      );
      expect(result, isNull);
      await tester.ensureVisible(find.byKey(const Key('use-suggestion')));
      await tester.tap(find.byKey(const Key('use-suggestion')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('editable-draft')))
            .controller!
            .text,
        'cleaned suggestion',
      );
      expect(result, isNull);
      await tester.tap(find.byKey(const Key('use-draft')));
      await tester.pumpAndSettle();
      await flushCleanup(tester);
      expect(result, 'cleaned suggestion');
    },
  );

  testWidgets('dismissal cancels inflight cleanup and drops late result', (
    tester,
  ) async {
    final client = FakeClient()..optimizeCompletion = Completer<String>();
    final capture = FakeCapture();
    String? result;
    await openSheet(
      tester,
      capture: capture,
      client: client,
      initialText: 'original',
      onResult: (value) => result = value,
    );
    await requestCleanup(tester);
    await tester.pump();
    final cancellation = client.lastCancellation!;
    await tester.tap(find.byTooltip('Close draft'));
    await tester.pumpAndSettle();
    expect(cancellation.isCancelled, isTrue);
    expect(result, isNull);
    client.optimizeCompletion!.complete('late');
    await tester.pumpAndSettle();
    expect(find.text('late'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'backgrounding cancels recording; resume never reopens microphone',
    (tester) async {
      final capture = FakeCapture();
      final client = FakeClient();
      await openSheet(
        tester,
        capture: capture,
        client: client,
        initialText: 'keep text',
      );
      await tester.tap(find.byKey(const Key('record-toggle')));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(capture.starts, 1);
      expect(capture.cancels, greaterThan(0));
      expect(client.sttCalls, 0);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('editable-draft')))
            .controller!
            .text,
        'keep text',
      );
      await tester.tap(find.byTooltip('Close draft'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('permission failure keeps import and editing available', (
    tester,
  ) async {
    final capture = FakeCapture()
      ..startError = StateError('private platform details');
    final client = FakeClient();
    await openSheet(
      tester,
      capture: capture,
      client: client,
      initialText: 'original',
    );
    await tester.tap(find.byKey(const Key('record-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('draft-error')), findsOneWidget);
    expect(find.textContaining('private platform details'), findsNothing);
    await tester.tap(find.byKey(const Key('import-wav')));
    await tester.pumpAndSettle();
    expect(client.sttCalls, 1);
    expect(capture.starts, 1);
    await tester.enterText(
      find.byKey(const Key('editable-draft')),
      'manual edit',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('editable-draft')))
          .controller!
          .text,
      'manual edit',
    );
    await tester.tap(find.byTooltip('Close draft'));
    await tester.pumpAndSettle();
  });

  testWidgets('changed target cancels and closes the old draft within 250ms', (
    tester,
  ) async {
    var current = true;
    String? result;
    final client = FakeClient()..optimizeCompletion = Completer<String>();
    await openSheet(
      tester,
      config: const AddonConfig(
        optimizer: OptimizerProfile(
          enabled: true,
          baseUrl: 'http://localhost/v1',
          model: 'draft',
        ),
      ),
      client: client,
      initialText: 'old target',
      targetIsCurrent: () => current,
      onResult: (value) => result = value,
    );
    await requestCleanup(tester);
    await tester.pump();
    final cancellation = client.lastCancellation!;
    current = false;
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Voice / text draft'), findsNothing);
    expect(result, isNull);
    expect(cancellation.isCancelled, isTrue);
    client.optimizeCompletion!.complete('late');
    await tester.pumpAndSettle();
  });

  testWidgets('system back cancels recording and returns no draft', (
    tester,
  ) async {
    final capture = FakeCapture();
    final client = FakeClient();
    String? result;
    await openSheet(
      tester,
      capture: capture,
      client: client,
      initialText: 'unsent',
      onResult: (value) => result = value,
    );
    await tester.tap(find.byKey(const Key('record-toggle')));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(capture.cancels, greaterThan(0));
    expect(capture.disposals, 1);
    expect(client.sttCalls, 0);
    expect(result, isNull);
  });

  testWidgets('barrier dismissal cancels recording without transcription', (
    tester,
  ) async {
    final capture = FakeCapture();
    final client = FakeClient();
    await openSheet(tester, capture: capture, client: client);
    await tester.tap(find.byKey(const Key('record-toggle')));
    await tester.pump();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Voice / text draft'), findsNothing);
    expect(capture.cancels, greaterThan(0));
    expect(client.sttCalls, 0);
  });

  testWidgets('document picker background transition preserves the import', (
    tester,
  ) async {
    final pendingImport = Completer<CapturedAudio?>();
    final capture = FakeCapture()..importCompletion = pendingImport;
    final client = FakeClient();
    await openSheet(
      tester,
      capture: capture,
      client: client,
      initialText: 'original',
    );
    await tester.tap(find.byKey(const Key('import-wav')));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(capture.cancels, 0);
    expect(client.sttCalls, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    pendingImport.complete(capture.audio);
    await tester.pumpAndSettle();
    expect(client.sttCalls, 1);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('editable-draft')))
          .controller!
          .text,
      'raw transcript',
    );
    await tester.tap(find.byTooltip('Close draft'));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'editing during cleanup keeps new text and discards stale suggestion',
    (tester) async {
      final client = FakeClient()..optimizeCompletion = Completer<String>();
      await openSheet(
        tester,
        config: const AddonConfig(
          optimizer: OptimizerProfile(
            enabled: true,
            baseUrl: 'http://localhost/v1',
            model: 'draft',
          ),
        ),
        client: client,
        initialText: 'original',
      );
      await requestCleanup(tester);
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('editable-draft')),
        'new text',
      );
      client.optimizeCompletion!.complete('stale suggestion');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('editable-draft')))
            .controller!
            .text,
        'new text',
      );
      expect(find.text('Cleanup suggestion'), findsNothing);
      await tester.tap(find.byTooltip('Close draft'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'host cannot reopen until old native cancellation and dispose finish',
    (tester) async {
      final owner = _NativeOwner();
      final first = _OwnerCapture(owner, 'A')
        ..cancelCompletion = Completer<void>()
        ..disposeCompletion = Completer<void>();
      final second = _OwnerCapture(owner, 'B');
      var opening = false;
      var launches = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  if (opening) return;
                  opening = true;
                  final capture = launches++ == 0 ? first : second;
                  await showDraftSheet(
                    context,
                    config: enabledConfig,
                    capture: capture,
                    client: FakeClient(),
                  );
                  opening = false;
                },
                child: const Text('Open draft'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open draft'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('record-toggle')));
      await tester.pump();
      expect(owner.active, 'A');
      await tester.tap(find.byTooltip('Close draft'));
      await tester.pumpAndSettle();
      expect(find.text('Voice / text draft'), findsNothing);
      expect(opening, isTrue);
      await tester.tap(find.text('Open draft'));
      await tester.pump();
      expect(launches, 1);
      first.cancelCompletion!.complete();
      await tester.pumpAndSettle();
      expect(first.disposals, 1);
      expect(opening, isTrue);
      first.disposeCompletion!.complete();
      await tester.pumpAndSettle();
      await flushCleanup(tester);
      expect(opening, isFalse);
      await tester.tap(find.text('Open draft'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('record-toggle')));
      await tester.pump();
      expect(launches, 2);
      expect(owner.active, 'B');
      await tester.pump(const Duration(milliseconds: 500));
      expect(owner.active, 'B');
      await tester.tap(find.byTooltip('Close draft'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'target change during delayed cleanup discards an approved draft',
    (tester) async {
      var current = true;
      var returned = false;
      String? result;
      final capture = FakeCapture()..disposeCompletion = Completer<void>();
      await openSheet(
        tester,
        capture: capture,
        client: FakeClient(),
        initialText: 'old target',
        targetIsCurrent: () => current,
        onResult: (value) {
          returned = true;
          result = value;
        },
      );
      await tester.tap(find.byKey(const Key('use-draft')));
      await tester.pumpAndSettle();
      expect(returned, isFalse);
      current = false;
      capture.disposeCompletion!.complete();
      await tester.pumpAndSettle();
      await flushCleanup(tester);
      expect(returned, isTrue);
      expect(result, isNull);
    },
  );

  testWidgets('native cleanup failure still completes the draft-sheet future', (
    tester,
  ) async {
    var returned = false;
    String? result;
    final capture = FakeCapture()
      ..cancelFailure = StateError('private cancel failure')
      ..disposeFailure = StateError('private dispose failure');
    await openSheet(
      tester,
      capture: capture,
      client: FakeClient(),
      initialText: 'approved',
      onResult: (value) {
        returned = true;
        result = value;
      },
    );
    await tester.tap(find.byKey(const Key('use-draft')));
    await tester.pumpAndSettle();
    await flushCleanup(tester);
    expect(returned, isTrue);
    expect(result, 'approved');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '60 second timer stops and transcribes into draft without applying cleanup',
    (tester) async {
      final capture = FakeCapture();
      final client = FakeClient();
      await openSheet(tester, capture: capture, client: client);
      await tester.tap(find.byKey(const Key('record-toggle')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 60));
      await tester.pumpAndSettle();
      expect(capture.stops, 1);
      expect(client.sttCalls, 1);
      expect(client.optimizeCalls, 0);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('editable-draft')))
            .controller!
            .text,
        'raw transcript',
      );
      await tester.tap(find.byTooltip('Close draft'));
      await tester.pumpAndSettle();
    },
  );
}
