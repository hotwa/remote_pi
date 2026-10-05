# Android fork: optional local pairing identity

The upstream Google Block Store store and native plugin are unchanged. Android
forks wrap that store with `app/lib/pimic_bridge/identity/PimicIdentityStore`.
With no local identity, load/save/watch/delete use the original cloud store.
There is no automatic fallback when Google sync is unavailable.

At **Sync required**, choose **仅存于此手机 · 无需 Google 同步**, read the
confirmation, and choose **使用本地身份**. This creates a new fork identity using
Ed25519 and persists it through the existing FlutterSecureStorage plugin
(Android Keystore-backed encrypted storage). A single versioned record commits
both the identity and the mode; no plaintext key, separate mode flag, cloud
identity import, key export, or cross-package identity sharing is introduced.
The local identity is validated against its private seed before use.

Local mode persists through app restarts and APK updates. The fork disables
Android application-data backup to prevent restoring encrypted app data without
its device key. Local mode requires no Google account, backup, secure screen
lock, or model API configuration. It preserves the original pairing handshake,
relay, mesh, transport, session selection, and Send behavior. It is independent
of the optional STT and prompt modules.

Local activation refuses to replace a loaded cloud identity or existing paired
profile. Corrupt/unreadable local identity data fails closed; the upstream
bridge is not allowed to generate a replacement key silently. Repeated taps
share activation; a cloud watch cannot replace a local identity. In-app key
rotation/deletion or switching an already paired local profile back to cloud
is intentionally unsupported. Clearing app data, uninstalling with data removal,
or changing phones requires fresh Pi pairing. Keeping app data during uninstall
allows reinstalling with the same signature; it is not an export/backup workflow.

Settings displays the active storage mode. First pairing still uses the original
`/remote-pi pair` QR or **Paste pairing code**. Configure the same relay URL in
Pi and the phone. STT's `/v1` URL is a separate setting, not a relay URL.

The host sync page now asks the router to reload its cached boot verdict after
successful recheck. This also fixes the original stale gate after enabling
Google sync. Only three host seams are needed: dependency wiring, sync entry /
boot reload callback, and a read-only Settings status. Native identity plugin,
OwnerIdentityBridge, pairing protocol, and ChatViewModel remain unchanged.

Validation: 16 focused identity/gate tests; 562 application tests (serial),
73 addon tests, 17 upstream identity tests; analysis and ARM64 debug APK build.
An initial parallel full-suite run hit an existing 5 ms room-stream timing test;
its standalone rerun and complete serial rerun passed. No unrelated production
transport changes were made to address that timing issue.
