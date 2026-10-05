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

Android also offers an explicit **local pairing identity** on the sync gate.
It keeps the original cloud store by default and uses secure local persistence
only after confirmation. See [local identity](PIMIC_LOCAL_IDENTITY.md).

## Configure and use

1. Open **Settings → PiMic · Voice & draft tools**.
2. For STT, set an OpenAI-compatible base URL, model, optional language and key.
   For this user's existing mac7 service: `http://192.168.11.130:50060/v1`,
   model `large-v3-turbo`. Enable **Speech to text** explicitly and save.
3. Optionally configure **Draft cleanup** separately with a chat-completions
   base URL/model/key. oMLX desktop app may serve this role. Existing service
   keys are never copied automatically; enter a dedicated credential if needed.
   **Load models** explicitly queries that profile's `/models` catalog, with
   its optional key. Choose an ID or keep a manual name. Lookup never enables
   a tool or saves settings, and a catalog is not an inference capability test.
   Services without `/models` remain usable through manual model entry.
4. Before Pi pairing, use **Test voice / draft tools** for a standalone preview.
   The same settings/test entries are available on upstream's **Sync required**
   screen. They use no Pi identity; the original Block Store/Keychain gate and
   pairing flow remain in place for Pi chat.
5. In a selected Pi chat, tap the additional microphone-tools icon. Select
   System default or a currently detected built-in, wired or USB input. Tap
   **Record**, speak, then **Stop & transcribe**. The level and input name show
   actual AudioRecord routing; a requested device is not presented as confirmed.
6. Review raw transcription and edit the draft. **Optimize this draft** starts
   unchecked on each opening, even when Draft cleanup is configured. Select it,
   then explicitly press **Suggest cleanup**, compare the original/suggestion,
   and **Use suggestion**. Selecting alone makes no API call. Unchecking cancels
   an in-flight cleanup and discards its suggestion without changing the draft.
   Choose **仅纠错** (default) or **整理提示词**. Mode changes invalidate earlier
   requests. Changed numbers, identifiers and restrictions are marked and require
   explicit acknowledgement before applying. Optional single-template JSON import
   is described in [optimization and template compatibility](PIMIC_OPTIMIZATION.md).
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
An empty STT result now reports no detected speech and preserves the draft.
Catalog lookup has a 15-second timeout, the same byte/redirect limits as other
requests, up to 256 IDs, and explicit cancellation. Editing its URL/key,
backgrounding, closing or saving invalidates pending catalog work. No lookup
starts when opening settings. Catalogs are transient and never persisted.

## Upstream maintenance

Feature code is in `app/packages/pimic_addons/`. It imports no upstream app model
or protocol. `app/lib/pimic_bridge/` contains the host adapter. Upstream edits are
limited to a path dependency, lazy DI binding, settings/composer entries,
and the sync gate/router boot reload seam. Local identity is isolated in
`app/lib/pimic_bridge/identity/`; the native upstream store stays unchanged.
Separate packaging changes cover package ID/name, LAN HTTP and update banner.
No Relay, Pi extension, wire format, ChatViewModel or existing SpeechService
implementation is changed.

To rebase: update upstream in `main`, rebase the feature branch, review the small
host/packaging diff, run the app regression tests plus addon package tests and
build. `pimic/export_patch.py` exports host, local-identity, packaging and test portability patches and
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

### Verified on 2026-10-04

- App analysis: no issues; final app regression suite: 546 passed.
- Addon Dart suite: 73 passed; existing identity package suite: 17 passed.
- Android Gradle unit tests: 16 passed. Addon lint: zero errors, one advisory
  about a newer AGP version; the upstream version remains pinned.
- ARM64 debug APK built and installed over Wi-Fi ADB on MI 5s Plus / Android 15,
  alongside the Play Store app. Microphone hardware is explicitly optional.
- Both switches start off. Saving the prefilled STT URL with switches off left
  capture/API tools disabled. Secure save and explicit STT enable worked.
- On the phone, Import WAV selected an existing 2.32-second wired recording,
  uploaded it to mac7 and displayed **手機語音測試** as raw and editable text.
  This verifies the phone → STT → phone path, not fresh-speech accuracy.
- Foreground recording reported actual **h2w (wiredHeadset)** input, PCM RMS,
  and automatic stop at exactly 60 seconds / 960,000 frames. The ambient clip
  had no supplied reference utterance and is not counted as an accuracy test.
- At this earlier stage the phone was behind the upstream sync gate;
  the local-identity continuation below resolves it without changing system settings.
- Real prompt cleanup against mac5 was not validated: its LAN port was
  unavailable. The optimizer is off on the test phone; fake-service tests pass.

### Continued development without a live speaker

- Added explicit catalog discovery for each profile. API and widget coverage
  includes no automatic requests/enabling/saving, manual fallback, bounded
  catalogs, redirection rejection, cancellation and ignoring stale results.
- Phone `/models` lookup against mac7 correctly reports HTTP 404 with manual
  entry guidance. The STT service itself remains ready; another known wired-WAV
  request returned **手機語音測試** in 777 ms.
- A temporary synthetic HTTP fixture reached over a scoped ADB reverse tunnel
  returned two model IDs. Selection filled the model field while cleanup stayed
  off, and did not reopen the keyboard. Enabling cleanup for this explicit test
  verified the nonstream chat-completions contract, original/suggestion view,
  explicit application to the draft and standalone return without a Pi send.
  This validates the phone/API/UI contract, not a real model's editing quality.
- Restored mac7 STT enabled with `large-v3-turbo`; cleanup is off and its temporary
  URL/model/key are blank. Removed the test tunnel and stopped the fixture.
- Final Dart total: **636** (546 app + 73 addon + 17 identity). Analysis and
  ARM64 debug build pass. Native code was unchanged in this continuation.
- Charging stay-awake is enabled for debugging. Without external power the
  existing 30-minute screen timeout remains. Original keyboard was restored.


### Optional local identity continuation

- Added 16 identity/gate tests. Final application suite: 562, addon: 73,
  original identity: 17 (652 Dart total); analysis and ARM64 APK build passed.
- Original Play APK uninstalled at user request while retaining its app data.
  Final fork APK metadata is 1.2.0+9. Direct Gradle builds now refresh their
  generated version properties from pubspec before building.
- Phone explicitly enabled local mode without Google sync or screen-lock changes.
  Successfully paired with installed remote-pi 0.7.0 in an isolated WSL Pi RPC
  test session. Cold start retained pairing and showed the online room/chat.
  Pi was launched through wsl.exe into Ubuntu-22.04; no LLM prompts were sent.
- Chat addon imported the existing 2.316-second WAV, mac7 returned
  **手機語音測試**, and explicit **Use draft** populated the composer.
  No Send was pressed. This is not fresh speech or real optimizer quality QA.
- The final version-stamped APK was reinstalled without clearing its local
  identity, paired peer, or STT configuration. Temporary test process/code and
  test WAV are cleaned up after acceptance; paired host registration remains.

### Draft modes and template compatibility — version 11

- Each draft still starts opted out. Default correction-only and optional prompt
  rewriting share conservative fact/restriction rules. Mode changes cancel old
  optimization; edits, config changes and opting out invalidate suggestions.
- Changed numbers, code identifiers and restriction clauses are highlighted.
  Applying a flagged suggestion requires acknowledgement; the original draft
  remains directly usable. Detection is heuristic, not semantic validation.
- Independent single-template JSON import/export supports a documented subset
  of Prompt Optimizer user templates. No upstream AGPL runtime or template text
  is bundled. Imported rules affect rewriting only; no extra service is required.
- Application suite 562, addon suite 99 and original identity suite 17 all passed
  (678 total). App analysis found no issues; ARM64 debug build passed through Pixi.
- Wi-Fi ADB upgrade succeeded and installed versionCode 11 was verified. The
  phone retained its local pairing identity and Relay settings. No real mac5
  optimizer quality or new spoken accuracy test is claimed for this update.
- Native capture, Pi extension, transport and upstream send code were unchanged.

### Optional workspace tools — version 12

- A third independent default-off setting enables grouped/searchable paired
  targets, run-local favorites, bounded per-target draft/scroll memory and a
  persistent entry to the existing typed Pi Quick Actions. No model API required.
- Selection uses the existing Home path and a stable peer/room route target.
  Recording/transcribing/media blocks switching. Target, settings or identity
  changes dismiss a pending picker. No switch sends a prompt or stops another Pi.
- App 572, addon 107, original identity 17: **696 Dart tests**. Analysis passed
  and ARM64 debug versionCode 12 built. New tests exercise route replacement,
  separate drafts, sent-draft clearing, memory limits, scroll restoration,
  selection races, identity reset and default-off compatibility.
- The native recorder, Pi extension, protocol and original send handler remain
  unchanged. Historical-session restore and arbitrary slash commands are pending.
- Details: [workspace guide](PIMIC_WORKSPACES.md).
- mac5 desktop oMLX 0.7.0 loopback tests used the existing Qwen3.8-27B model,
  three written inputs and both modes. Final warm medians: correction 1.313 s,
  rewriting 4.963 s; first cold request 64.506 s. Non-thinking was requested
  per call; no global service/configuration or credentials were changed.
  Rewriting rules were tightened after observed translation/added requirements.
  Small probes do not establish speech accuracy or semantic equivalence.
