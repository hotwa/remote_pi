import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'api_client.dart';
import 'audio.dart';
import 'config.dart';
import 'draft_session.dart';

/// Returns text only after the user presses Use draft. It never sends to Pi.
Future<String?> showDraftSheet(
  BuildContext context, {
  required AddonConfig config,
  String initialText = '',
  AudioCapture? capture,
  AddonApiClient? client,
  bool Function()? targetIsCurrent,
}) async {
  final session = DraftSession(
    config: config,
    initialText: initialText,
    capture:
        capture ?? (config.stt.enabled ? MethodChannelAudioCapture() : null),
    client: client,
    targetIsCurrent: targetIsCurrent,
  );
  final disposed = Completer<void>();
  var built = false;
  String? result;
  try {
    result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) {
        built = true;
        return DraftSheet._withSession(
          config: config,
          session: session,
          onDispose: () {
            if (!disposed.isCompleted) disposed.complete();
          },
        );
      },
    );
    // Navigator.pop completes before the route's exit animation and dispose.
    // Keep the host entry closed until that old route has released its owner.
    if (built) await disposed.future;
  } finally {
    session.dispose();
    await session.cleanupDone;
  }
  return session.targetIsCurrent ? result : null;
}

class DraftSheet extends StatefulWidget {
  const DraftSheet({
    super.key,
    required this.config,
    this.initialText = '',
    this.capture,
    this.client,
    this.targetIsCurrent,
  }) : _providedSession = null,
       _onDispose = null;

  const DraftSheet._withSession({
    required this.config,
    required DraftSession session,
    required VoidCallback onDispose,
  }) : _providedSession = session,
       _onDispose = onDispose,
       initialText = '',
       capture = null,
       client = null,
       targetIsCurrent = null;

  final DraftSession? _providedSession;
  final VoidCallback? _onDispose;
  final AddonConfig config;
  final String initialText;
  final AudioCapture? capture;
  final AddonApiClient? client;
  final bool Function()? targetIsCurrent;

  @override
  State<DraftSheet> createState() => _DraftSheetState();
}

class _DraftSheetState extends State<DraftSheet> with WidgetsBindingObserver {
  late final DraftSession _session;
  late final TextEditingController _text;
  bool _closingForTarget = false;
  bool _optimizeThisDraft = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session =
        widget._providedSession ??
        DraftSession(
          config: widget.config,
          initialText: widget.initialText,
          capture: widget.capture,
          client: widget.client,
          targetIsCurrent: () => widget.targetIsCurrent?.call() ?? true,
        );
    _text = TextEditingController(text: _session.editableDraft);
    _session.addListener(_changed);
    // Device discovery does not request microphone permission or start recording.
    if (widget.config.stt.enabled) unawaited(_session.loadInputs());
  }

  @override
  void didUpdateWidget(covariant DraftSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.config, widget.config)) {
      _optimizeThisDraft = false;
      unawaited(_session.updateConfig(widget.config));
    }
    if (!(widget.targetIsCurrent?.call() ?? true)) {
      unawaited(_session.cancelCurrent());
    }
  }

  void _changed() {
    if (!mounted) return;
    if (!_session.targetIsCurrent && !_closingForTarget) {
      _closingForTarget = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
    if (_text.text != _session.editableDraft) {
      _text.value = TextEditingValue(
        text: _session.editableDraft,
        selection: TextSelection.collapsed(
          offset: _session.editableDraft.length,
        ),
      );
    }
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The system document picker temporarily backgrounds the host Activity.
    // Importing has no active microphone or network request to suspend.
    if (_session.phase == DraftPhase.importing &&
        state != AppLifecycleState.detached) {
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(_session.cancelCurrent());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_changed);
    _session.dispose();
    _text.dispose();
    super.dispose();
    widget._onDispose?.call();
  }

  String get _status => switch (_session.phase) {
    DraftPhase.ready => 'Ready — review text before using it',
    DraftPhase.starting => 'Opening microphone…',
    DraftPhase.recording => 'Recording — stops after 60 seconds',
    DraftPhase.stopping => 'Finishing recording…',
    DraftPhase.importing => 'Choose a WAV file…',
    DraftPhase.transcribing => 'Transcribing audio…',
    DraftPhase.optimizing => 'Preparing a cleanup suggestion…',
  };

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return PopScope<String>(
      onPopInvokedWithResult: (didPop, _) {
        // Begin final cleanup at pop, while the exit animation is running.
        // showDraftSheet still waits for both widget disposal and cleanupDone.
        if (didPop) _session.dispose();
      },
      child: SizedBox(
        height: media.size.height * .92,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            media.viewInsets.bottom + 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Voice / text draft',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close draft',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Text(
                'Record or import audio, edit text, then explicitly use the draft. It returns to your composer for review.',
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.config.stt.enabled) ...[
                        DropdownButtonFormField<int>(
                          key: const Key('audio-input'),
                          isExpanded: true,
                          initialValue: _session.preferredInputId ?? -1,
                          decoration: const InputDecoration(
                            labelText: 'Requested microphone',
                            helperText:
                                'System auto, built-in, wired or USB inputs when available',
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: -1,
                              child: Text('System auto'),
                            ),
                            for (final input in _session.availableInputs)
                              DropdownMenuItem(
                                value: input.id,
                                child: Text(
                                  '${input.label} (${input.type})',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: _session.isBusy
                              ? null
                              : (value) => _session.selectInput(
                                  value == -1 ? null : value,
                                ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              key: const Key('record-toggle'),
                              onPressed: _session.isRecording
                                  ? () => unawaited(_session.stopRecording())
                                  : (_session.canRecord
                                        ? () => unawaited(
                                            _session.startRecording(),
                                          )
                                        : null),
                              icon: Icon(
                                _session.isRecording ? Icons.stop : Icons.mic,
                              ),
                              label: Text(
                                _session.isRecording
                                    ? 'Stop & transcribe'
                                    : 'Start recording',
                              ),
                            ),
                            OutlinedButton.icon(
                              key: const Key('import-wav'),
                              onPressed: _session.canImport
                                  ? () => unawaited(_session.importWav())
                                  : null,
                              icon: const Icon(Icons.audio_file),
                              label: const Text('Import WAV'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _meter(context),
                      ],
                      Text(
                        _status,
                        key: const Key('draft-status'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (_session.isBusy)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () =>
                                unawaited(_session.cancelCurrent()),
                            child: const Text('Cancel operation'),
                          ),
                        ),
                      if (_session.error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            _session.error!,
                            key: const Key('draft-error'),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      if (_session.notice != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            _session.notice!,
                            key: const Key('draft-notice'),
                          ),
                        ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('editable-draft'),
                        controller: _text,
                        onChanged: _session.editDraft,
                        minLines: 5,
                        maxLines: 10,
                        maxLength: AddonApiClient.maxTextCharacters,
                        decoration: const InputDecoration(
                          labelText: 'Editable draft',
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(),
                          hintText: 'Type here, even without a microphone',
                        ),
                      ),
                      CheckboxListTile(
                        key: const Key('optimize-this-draft'),
                        value: _optimizeThisDraft,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('Optimize this draft'),
                        subtitle: Text(
                          widget.config.optimizer.enabled
                              ? 'Optional. Select, then request a suggestion; your original text stays available.'
                              : 'Configure and enable Draft cleanup in settings to use this option.',
                        ),
                        onChanged:
                            widget.config.optimizer.enabled &&
                                (!_session.isBusy ||
                                    _session.phase == DraftPhase.optimizing)
                            ? (value) {
                                setState(() {
                                  _optimizeThisDraft = value ?? false;
                                });
                                if (!_optimizeThisDraft) {
                                  _session.cancelOptimization();
                                }
                              }
                            : null,
                      ),
                      if (widget.config.optimizer.enabled)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            key: const Key('optimize-draft'),
                            onPressed:
                                _optimizeThisDraft && _session.canOptimize
                                ? () => unawaited(_session.optimize())
                                : null,
                            icon: const Icon(Icons.auto_fix_high),
                            label: const Text('Suggest cleanup'),
                          ),
                        ),
                      if (_session.rawTranscript.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _comparison(
                          context,
                          'Raw transcript',
                          _session.rawTranscript,
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            key: const Key('use-transcript'),
                            onPressed: _session.isBusy
                                ? null
                                : _session.useTranscript,
                            child: const Text('Use transcript in draft'),
                          ),
                        ),
                      ],
                      if (_optimizeThisDraft &&
                          _session.suggestedDraft != null) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Review both versions before applying the suggestion.',
                        ),
                        const SizedBox(height: 8),
                        _comparison(
                          context,
                          'Original text',
                          _session.suggestionSource!,
                        ),
                        const SizedBox(height: 8),
                        _comparison(
                          context,
                          'Cleanup suggestion',
                          _session.suggestedDraft!,
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton(
                            key: const Key('use-suggestion'),
                            onPressed: _session.canUseSuggestion
                                ? _session.useSuggestion
                                : null,
                            child: const Text('Use suggestion'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('use-draft'),
                onPressed: _session.canUseDraft
                    ? () {
                        final result = _session.useDraft();
                        if (result != null) Navigator.of(context).pop(result);
                      }
                    : null,
                child: const Text('Use draft'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _comparison(BuildContext context, String title, String text) =>
      DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              SelectableText(text),
            ],
          ),
        ),
      );

  Widget _meter(BuildContext context) {
    final level = _session.level;
    final audio = _session.recordedAudio;
    final input = level?.input ?? audio?.input;
    final duration = level?.duration ?? audio?.duration;
    final frames = level?.frames ?? audio?.frames;
    final rawRms = level?.rms ?? 0;
    final rms = rawRms.isFinite ? rawRms.clamp(0.0, 1.0).toDouble() : 0.0;
    final dbfs = rms > 0 ? 20 * math.log(rms) / math.ln10 : null;
    final meter = dbfs == null
        ? 0.0
        : ((dbfs + 60) / 60).clamp(0.0, 1.0).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: meter),
          duration: const Duration(milliseconds: 100),
          builder: (_, value, _) => LinearProgressIndicator(
            key: const Key('rms-meter'),
            value: value,
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Actual recorded input: ${input == null ? 'Unknown' : '${input.label} (${input.type})'}',
          key: const Key('actual-input'),
        ),
        Text(
          'PCM RMS: ${rms.toStringAsFixed(3)} • ${dbfs == null ? '−∞' : dbfs.toStringAsFixed(1)} dBFS (meter: −60 to 0 dBFS)${duration == null ? '' : ' • ${(duration.inMilliseconds / 1000).toStringAsFixed(1)} s'}${frames == null ? '' : ' • $frames frames'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
