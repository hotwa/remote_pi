# PiMic addons

Independent Android capture and OpenAI-compatible draft tools. Imports no
Remote Pi app model, protocol, storage or send code. Exported contracts are
`AddonConfigStore`, `AddonApiClient`, `AudioCapture`, `DraftSession`,
`AddonSettingsPage` and `showDraftSheet`.

STT and draft cleanup each default off. Native channels stay inert until an
explicit operation. The draft sheet never sends to Pi; it returns reviewed
text only after **Use draft**. The host decides where that draft belongs.

HTTP transports work with custom LAN/provider base URLs; include `/v1` when
required. WAV uploads support mono16kPCM16 <=60s and <=2MB including metadata.
API keys are securely stored and errors are sanitized. No provider SDK or
Pipecat dependency is required. A future gateway can expose these same routes.

Native capture uses a foreground Activity, actual AudioRecord routing and RMS.
Cancellation includes permissions, document picker, bounded capture/import and
event subscription lifecycle. Bluetooth is outside this initial implementation.

From the repository root:

```bash
pixi run --manifest-path pimic/pixi.toml run-package-tests
```

This runs fake-service tests only. See `docs/PIMIC_VOICE_IMPLEMENTATION.md` for
explicit LAN smoke tests, user configuration and upstream patch maintenance.
