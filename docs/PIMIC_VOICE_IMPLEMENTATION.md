# PiMic optional voice / draft tools — first implementation

Based on upstream `577e70b79528cc6c7da463ecd14c42ff8b9d9ed9`.
Upstream `main` remains unchanged; implementation branch: `pimic/voice-addon`.

## Behavior

Both optional tools start **off**. Installing this APK requires no model service.
The upstream local speech recognizer, pairing, session list, chat, attachments,
tool approvals and send handler remain in place. A settings entry configures
the addon; the extra composer action appears only when a tool is enabled.
Entering chat reads local addon settings; it starts no new API request or mic.
Malformed/unavailable settings fail closed. Saving a URL alone enables nothing.

The additional APK installs as `work.jacobmoura.remotepi.pimic` / **PiMic Remote**.
It coexists with the Play Store package. Its identity and pairings are separate:
pair once through the normal Remote Pi QR flow. Official app data is not copied.
The official APK update banner is disabled for this fork to avoid offering an
APK with another package/signature.

## Configure and use

1. Open **Settings → PiMic · Voice & draft tools**.
2. For STT, set an OpenAI-compatible base URL, model, optional language and key.
   For this user's existing mac7 service: `http://192.168.11.130:50060/v1`,
   model `large-v3-turbo`. Enable **Speech to text** explicitly and save.
3. Optionally configure **Draft cleanup** separately with a chat-completions
   base URL/model/key. oMLX desktop app may serve this role. Existing service
   keys are never copied automatically; enter a dedicated credential if needed.
4. Before Pi pairing, use **Test voice / draft tools** for a standalone preview.
5. In a selected Pi chat, tap the additional microphone-tools icon. Select
   System default or a currently detected built-in, wired or USB input. Tap
   **Record**, speak, then **Stop & transcribe**. The level and input name show
   actual AudioRecord routing; a requested device is not presented as confirmed.
6. Review raw transcription and edit the draft. Optionally press **Clean up**,
   compare the original/suggestion, then explicitly **Use suggestion**.
7. **Use draft** returns text to the composer. Press the original Send button
   when ready. Neither transcription nor cleanup sends a Pi command.

Without a microphone/permission, text editing remains available. **Import WAV**
accepts bounded mono 16 kHz PCM16 WAV up to 60 seconds. Other formats require
conversion first. Bluetooth capture, always-on VAD, TTS and realtime Pipecat
transport are follow-up work; this version records only after a manual tap.

Base URLs are literal: include `/v1` if the provider requires it. The client
appends `/audio/transcriptions` or `/chat/completions`, uses JSON/nonstreaming
responses, rejects redirects and bounds request/response duration and size.
Android cleartext HTTP is allowed for user-configured LAN endpoints; HTTPS
retains normal certificate validation. API keys are stored in device secure
storage and never printed. Keys and service settings belong to the addon only.

Cancel, dismissal, app backgrounding, target-session changes and profile changes
invalidate work; late results cannot overwrite another session's draft. Editing
while a request runs preserves the newer edits. Errors preserve the draft.
Control commands bypass cleanup; users still review every model suggestion.

## Upstream maintenance

Feature code is in `app/packages/pimic_addons/`. It imports no upstream app model
or protocol. `app/lib/pimic_bridge/` contains the host adapter. Upstream edits are
limited to a path dependency, lazy DI binding, settings entry and composer seam.
Separate packaging changes cover package ID/name, LAN HTTP and update banner.
No Relay, Pi extension, wire format, ChatViewModel or existing SpeechService
implementation is changed.

To rebase: update upstream in `main`, rebase the feature branch, review the small
host/packaging diff, run the app regression tests plus addon package tests and
build. `pimic/export_patch.py` exports host, packaging and test portability patches and
checksums for review. A future Pipecat gateway should preserve these HTTP draft
contracts; no Pipecat SDK/runtime is required in this APK.

## Build and verification

Tool setup and all Flutter commands run through **`pimic/pixi.toml`**; see
`pimic/README.md`. Dart dependencies remain in pubspec/lockfiles. No global Python
packages are required. Flutter/SDK/download caches and signing files are ignored.
Android 14/API 34 is the upstream minimum.

Default test suites use fake services and never download models or call Pi.
An explicit LAN smoke test is provided outside the default app test directory:

```bash
PIMIC_STT_SMOKE_WAV=/absolute/path/to/recording.wav \
  pixi run --manifest-path pimic/pixi.toml python pimic/scripts/flutter.py \
  test ../pimic/integration_test/stt_smoke_test.dart --reporter expanded
```

Real phone recording/route, fresh QR pairing and end-to-end user speech should
be reported separately from fake-client tests and existing-WAV API tests.
