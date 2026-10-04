import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'audio.dart';
import 'config.dart';

enum DraftPhase {
  ready,
  starting,
  recording,
  stopping,
  importing,
  transcribing,
  optimizing,
}

/// A local draft workflow. It has no Pi connection and never sends a message.
class DraftSession extends ChangeNotifier {
  DraftSession({
    required AddonConfig config,
    String initialText = '',
    AudioCapture? capture,
    AddonApiClient? client,
    bool Function()? targetIsCurrent,
  }) : _config = config,
       _capture = capture,
       _client = client ?? AddonApiClient(),
       _targetIsCurrent = targetIsCurrent,
       _editableDraft = initialText {
    if (targetIsCurrent != null) {
      _targetTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!_disposed && !_targetInvalid && !_currentTarget()) {
          _targetInvalid = true;
          unawaited(cancelCurrent());
        }
      });
    }
    _levels = capture?.levels.listen(
      _onLevel,
      onError: (Object _) {
        if (!_disposed && phase == DraftPhase.recording) {
          error =
              'Recording stopped because the microphone became unavailable. Your draft is preserved.';
          unawaited(cancelCurrent());
        }
      },
    );
  }

  AddonConfig _config;
  final AudioCapture? _capture;
  final AddonApiClient _client;
  final bool Function()? _targetIsCurrent;
  StreamSubscription<AudioLevel>? _levels;
  AddonCancellation? _request;
  Timer? _limitTimer;
  Timer? _targetTimer;
  bool _targetInvalid = false;
  bool _disposed = false;
  bool _startingCapture = false;
  int _generation = 0;
  int _editRevision = 0;
  int _captureCleanups = 0;
  Future<void> _captureCleanupTail = Future<void>.value();
  Completer<void>? _startDone;
  final Completer<void> _cleanupDone = Completer<void>();

  /// Completes after event unsubscription and all native cleanup finish.
  Future<void> get cleanupDone => _cleanupDone.future;
  int? _suggestionRevision;

  DraftPhase phase = DraftPhase.ready;
  String _editableDraft;
  String get editableDraft => _editableDraft;
  String rawTranscript = '';
  String? suggestionSource;
  String? suggestedDraft;
  String? error;
  String? notice;
  AudioLevel? level;
  CapturedAudio? recordedAudio;
  List<AudioInput> availableInputs = [];
  int? preferredInputId;

  AddonConfig get config => _config;
  bool get isBusy => phase != DraftPhase.ready;
  bool get isRecording => phase == DraftPhase.recording;
  bool get canRecord =>
      !_disposed &&
      _capture != null &&
      _config.stt.enabled &&
      !isBusy &&
      !_startingCapture &&
      _captureCleanups == 0;
  bool get canImport =>
      !_disposed &&
      _capture != null &&
      _config.stt.enabled &&
      !isBusy &&
      !_startingCapture &&
      _captureCleanups == 0;
  bool get canOptimize =>
      !_disposed &&
      _config.optimizer.enabled &&
      !isBusy &&
      editableDraft.trim().isNotEmpty;
  bool get canUseDraft =>
      !_disposed &&
      !isBusy &&
      editableDraft.trim().isNotEmpty &&
      _currentTarget();
  bool get canUseSuggestion =>
      !_disposed &&
      suggestedDraft != null &&
      _suggestionRevision == _editRevision &&
      !isBusy;

  bool get targetIsCurrent => _currentTarget();

  bool _currentTarget() {
    if (_targetInvalid) return false;
    try {
      return _targetIsCurrent?.call() ?? true;
    } on Object {
      return false;
    }
  }

  bool _active(int generation) =>
      !_disposed && generation == _generation && _currentTarget();
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void editDraft(String value) {
    if (_disposed || value == editableDraft) return;
    _editableDraft = value;
    _editRevision++;
    suggestedDraft = null;
    suggestionSource = null;
    _suggestionRevision = null;
    _notify();
  }

  /// Changing settings invalidates all work started under the old profile.
  Future<void> updateConfig(AddonConfig value) async {
    await cancelCurrent();
    if (_disposed) return;
    _config = value;
    _notify();
  }

  Future<void> loadInputs() async {
    if (_capture == null || _disposed) return;
    final generation = _generation;
    try {
      final inputs = await _capture.inputs();
      if (!_active(generation)) return;
      availableInputs = inputs;
      if (!inputs.any((input) => input.id == preferredInputId)) {
        preferredInputId = null;
      }
      _notify();
    } on Object {
      if (_active(generation)) {
        error =
            'Microphone inputs are unavailable. You can still import WAV or edit text.';
        _notify();
      }
    }
  }

  void selectInput(int? id) {
    if (isBusy || _startingCapture || _disposed) return;
    preferredInputId = id;
    _notify();
  }

  Future<void> startRecording() async {
    if (!canRecord || !_currentTarget()) return;
    final generation = ++_generation;
    error = null;
    notice = null;
    level = null;
    recordedAudio = null;
    phase = DraftPhase.starting;
    _startingCapture = true;
    final startDone = Completer<void>();
    _startDone = startDone;
    _notify();
    try {
      await _capture!.start(preferredInputId: preferredInputId);
      if (!_active(generation)) {
        await _quietCancelCapture();
        if (!_disposed && generation == _generation) phase = DraftPhase.ready;
        return;
      }
      phase = DraftPhase.recording;
      _limitTimer = Timer(const Duration(seconds: 60), () {
        unawaited(stopRecording());
      });
    } on Object catch (failure) {
      if (_active(generation)) {
        phase = DraftPhase.ready;
        error = _safeError(
          failure,
          'Unable to record. Check microphone permission or import a WAV file.',
        );
      }
      await _quietCancelCapture();
    } finally {
      _startingCapture = false;
      startDone.complete();
      if (identical(_startDone, startDone)) _startDone = null;
      _notify();
    }
  }

  void _onLevel(AudioLevel value) {
    if (_disposed || !isRecording) return;
    if (!_currentTarget()) {
      unawaited(cancelCurrent());
      return;
    }
    level = value;
    _notify();
    if (value.limitReached) unawaited(stopRecording());
  }

  Future<void> stopRecording() async {
    if (!isRecording || _capture == null) return;
    final generation = _generation;
    final revision = _editRevision;
    _limitTimer?.cancel();
    phase = DraftPhase.stopping;
    _notify();
    try {
      final audio = await _capture.stop();
      if (!_active(generation)) return;
      recordedAudio = audio;
      await _transcribe(audio, generation, revision);
    } on Object catch (failure) {
      if (_active(generation)) {
        phase = DraftPhase.ready;
        error = _safeError(
          failure,
          'Unable to finish recording. Your draft is preserved.',
        );
        _notify();
        await _quietCancelCapture();
      }
    }
  }

  Future<void> importWav() async {
    if (!canImport || !_currentTarget()) return;
    final generation = ++_generation;
    final revision = _editRevision;
    error = null;
    notice = null;
    phase = DraftPhase.importing;
    _notify();
    try {
      final audio = await _capture!.importWav();
      if (!_active(generation)) return;
      if (audio == null) {
        phase = DraftPhase.ready;
        _notify();
        return;
      }
      recordedAudio = audio;
      await _transcribe(audio, generation, revision);
    } on Object catch (failure) {
      if (_active(generation)) {
        phase = DraftPhase.ready;
        error = _safeError(
          failure,
          'Unable to import audio. Choose a mono 16 kHz PCM16 WAV up to 60 seconds.',
        );
        _notify();
      }
    }
  }

  Future<void> _transcribe(
    CapturedAudio audio,
    int generation,
    int revision,
  ) async {
    phase = DraftPhase.transcribing;
    final cancellation = AddonCancellation(generation: generation);
    _request = cancellation;
    _notify();
    try {
      final text = await _client.transcribe(
        profile: _config.stt,
        wav: audio.wav,
        cancellation: cancellation,
      );
      if (!_active(generation) || cancellation.isCancelled) return;
      rawTranscript = text;
      if (_editRevision == revision) {
        editDraft(text);
      } else {
        notice =
            'Transcription is ready below. Your newer draft edits were preserved.';
      }
    } on Object catch (failure) {
      if (_active(generation) && !cancellation.isCancelled) {
        error = _safeError(
          failure,
          'Transcription failed. Your draft is preserved.',
        );
      }
    } finally {
      if (identical(_request, cancellation)) _request = null;
      if (!_disposed && generation == _generation) {
        phase = DraftPhase.ready;
        _notify();
      }
    }
  }

  static bool isControlCommand(String text) {
    final trimmed = text.trim();
    return trimmed.startsWith('/') ||
        isControlDraft(trimmed) ||
        RegExp(
          r'^(stop|abort|cancel|pause|resume|停止|取消|中止|暂停|继续)[.!。！]?$',
          caseSensitive: false,
        ).hasMatch(trimmed);
  }

  Future<void> optimize() async {
    if (!canOptimize || !_currentTarget()) return;
    error = null;
    notice = null;
    if (isControlCommand(editableDraft)) {
      notice =
          'Control commands are kept unchanged. Review and use the draft directly.';
      _notify();
      return;
    }
    final source = editableDraft;
    final revision = _editRevision;
    final generation = ++_generation;
    final cancellation = AddonCancellation(generation: generation);
    _request = cancellation;
    phase = DraftPhase.optimizing;
    suggestedDraft = null;
    suggestionSource = null;
    _notify();
    try {
      final result = await _client.optimize(
        profile: _config.optimizer,
        text: source,
        cancellation: cancellation,
      );
      if (!_active(generation) || cancellation.isCancelled) return;
      if (_editRevision != revision) {
        notice =
            'Your draft changed during cleanup. Run cleanup again to review the current text.';
      } else {
        suggestionSource = source;
        suggestedDraft = result;
        _suggestionRevision = revision;
      }
    } on Object catch (failure) {
      if (_active(generation) && !cancellation.isCancelled) {
        error = _safeError(
          failure,
          'Draft cleanup failed. Your original text is preserved.',
        );
      }
    } finally {
      if (identical(_request, cancellation)) _request = null;
      if (!_disposed && generation == _generation) {
        phase = DraftPhase.ready;
        _notify();
      }
    }
  }

  void useSuggestion() {
    if (!canUseSuggestion || !_currentTarget()) return;
    final result = suggestedDraft!;
    editDraft(result);
    notice =
        'Suggestion applied to your editable draft. Review it before using it.';
    _notify();
  }

  void useTranscript() {
    if (rawTranscript.isEmpty || isBusy || !_currentTarget()) return;
    editDraft(rawTranscript);
  }

  String? useDraft() => canUseDraft ? editableDraft : null;

  /// Cancel on dismissal, backgrounding or target changes. Text stays local.
  Future<void> cancelCurrent() async {
    if (_disposed) return;
    _generation++;
    _request?.cancel();
    _request = null;
    _limitTimer?.cancel();
    suggestedDraft = null;
    suggestionSource = null;
    _suggestionRevision = null;
    phase = DraftPhase.ready;
    level = null;
    _notify();
    await _quietCancelCapture();
  }

  Future<void> _quietCancelCapture() {
    _captureCleanups++;
    _notify();
    final cleanup = _captureCleanupTail.then((_) async {
      try {
        await _capture?.cancel();
      } on Object {
        /* Cleanup must preserve the draft. */
      } finally {
        _captureCleanups--;
        _notify();
      }
    });
    _captureCleanupTail = cleanup;
    return cleanup;
  }

  String _safeError(Object failure, String fallback) =>
      failure is AddonException ? failure.message : fallback;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _targetTimer?.cancel();
    _generation++;
    _request?.cancel();
    _limitTimer?.cancel();
    unawaited(_disposeResources());
    super.dispose();
  }

  Future<void> _disposeResources() async {
    final startDone = _startDone?.future;
    // Event-channel shutdown must not delay releasing the microphone.
    final levelCancellation = _cancelLevels();
    try {
      await _quietCancelCapture();
      // A pending permission/start response can trigger one final cancellation.
      // Wait for that response before releasing the native capture owner.
      await startDone;
      await _captureCleanupTail;
      try {
        await _capture?.dispose();
      } on Object {
        /* No UI remains for an error. */
      }
      await levelCancellation;
    } finally {
      _cleanupDone.complete();
    }
  }

  Future<void> _cancelLevels() async {
    try {
      await _levels?.cancel();
    } on Object {
      /* Native cleanup must continue if the event channel failed. */
    }
  }
}
