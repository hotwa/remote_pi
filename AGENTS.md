# PiMic personal Remote Pi fork

Upstream baseline: `577e70b79528cc6c7da463ecd14c42ff8b9d9ed9`.
Keep `main` tracking upstream; work on feature branches. The user explicitly
authorized implementing this fork. Upstream CLAUDE.md describes its original
cmux workflow; this checkout uses the available Codex agents instead.

- New voice and prompt features belong to `app/packages/pimic_addons/`, with a
  thin host adapter in `app/lib/pimic_bridge/`. Preserve small upstream patches.
- STT and optimizer are independently optional and **off by default**. Missing,
  invalid or unavailable addon configuration fails closed. No new startup model
  requests, microphone capture or permission prompts. Reading local settings
  when entering chat is allowed. URLs saved alone do not enable features.
- Keep upstream pairing, Relay/protocol, Pi extension, ChatViewModel, existing
  SpeechService and sending behavior intact. Optimization returns a reviewed
  draft; it must never become mandatory on Send or automatically send commands.
- Cancel/close/background/target/config changes invalidate work. Late results
  must not overwrite another session or newer edits. Resource cleanup and native
  owner isolation must cover rapid close/reopen and cancelled imports.
- Device labels reflect actual AudioRecord routing. Never infer a wired mic
  from the requested device. All audio/queues/requests are bounded.
- Android first: builtin/wired/USB/manual recording and bounded PCM16 WAV import.
  Bluetooth, always-on VAD, TTS and realtime Pipecat are not implemented.
- Use `pimic/pixi.toml` and lockfile for toolchain/setup/tasks. Dart dependencies
  remain in pubspec/locks. Keep build work on WSL ext4. No global pip installs.
- Fork APK package/signature is independent of the Play Store app. Preserve
  official app data. Never copy existing pairing keys, passwords or API tokens.
  New profile secrets are entered explicitly and kept in secure device storage.
- Default tests are offline with fake API/capture; actual LAN STT/phone/pairing
  checks are explicit and reported separately. Run upstream regression tests,
  addon package tests, analysis and APK build before claiming readiness.
- Any workstation Pi launch must be via `wsl.exe -d Ubuntu-22.04`; never Windows
  Pi. No tests send prompts into an existing user Pi session without instruction.
- Optional Android local identity belongs in `app/lib/pimic_bridge/identity/`.
  Preserve native cloud storage by default; require explicit local activation.
  No automatic cloud fallback, identity import/export, silent key rotation, or
  swapping storage for a paired profile. Local corruption must fail closed.
  User-authorized original APK uninstall may keep its app data with `-k`.
