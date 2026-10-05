import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:remote_pi_identity/remote_pi_identity.dart';

/// Explicit, sticky local identity mode for the Android fork. No silent
/// fallback, import from cloud, export, or replacement of a damaged identity.
/// One secure-storage write commits both mode and identity atomically.
class PimicIdentityStore implements OwnerIdentityStore {
  PimicIdentityStore(this.cloud, {FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final OwnerIdentityStore cloud;
  final FlutterSecureStorage _storage;
  static const _key = 'pimic.owner.local.v1';
  Future<void>? _activation;

  Future<OwnerIdentity?> _local() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return null;
      if (raw.length != 90 || !raw.startsWith('1:')) {
        throw const FormatException();
      }
      final id = OwnerIdentity.fromBlob(base64Decode(raw.substring(2)));
      final pair = await Ed25519().newKeyPairFromSeed(id.ownerSk);
      final public = await pair.extractPublicKey();
      if (!ListEquality.equals(public.bytes, id.ownerPk)) {
        throw const FormatException();
      }
      return id;
    } on Object {
      // The upstream bridge regenerates on PlatformFailure. Fail closed here
      // instead: a corrupt/unreadable local identity must never rotate silently.
      throw const SyncUnavailable(
        'Local identity could not be read. Existing data was left unchanged.',
      );
    }
  }

  Future<bool> isLocal() async => await _local() != null;

  /// Only exposed at the sync gate, before any fork identity/pairing is loaded.
  /// Existing local mode is idempotent. The host guard prevents switching an
  /// already paired cloud profile. Concurrent taps share the same activation.
  Future<void> activateLocal({required Future<bool> Function() mayCreate}) {
    return _activation ??= _activateLocal(mayCreate).whenComplete(() {
      _activation = null;
    });
  }

  Future<void> _activateLocal(Future<bool> Function() mayCreate) async {
    if (await _local() != null) return;
    if (!await mayCreate()) {
      throw const SyncUnavailable(
        'Local mode cannot replace an existing identity or pairings.',
      );
    }
    final pair = await Ed25519().newKeyPair();
    final public = await pair.extractPublicKey();
    final seed = await pair.extractPrivateKeyBytes();
    final id = OwnerIdentity(
      ownerPk: Uint8List.fromList(public.bytes),
      ownerSk: Uint8List.fromList(seed),
    );
    await _storage.write(key: _key, value: '1:${base64Encode(id.toBlob())}');
    // Read and validate before letting the host proceed to the original boot.
    if (await _local() != id) {
      throw const SyncUnavailable('Local identity could not be saved.');
    }
  }

  @override
  Future<OwnerIdentity?> load() async => await _local() ?? await cloud.load();

  @override
  Future<void> save(OwnerIdentity identity) async {
    final local = await _local();
    if (local == null) {
      await cloud.save(identity);
    } else if (local != identity) {
      throw const SyncUnavailable('Replacing a local identity is not allowed.');
    }
  }

  @override
  Stream<OwnerIdentity> watch() async* {
    if (await _local() == null) yield* cloud.watch();
  }

  @override
  Future<bool> isSyncAvailable() async =>
      await _local() != null || await cloud.isSyncAvailable();

  @override
  Future<void> delete() async {
    if (await _local() != null) {
      // Changing modes in a running paired app is intentionally unsupported.
      throw const SyncUnavailable(
        'Reset local mode through app data settings.',
      );
    }
    await cloud.delete();
  }
}

abstract final class ListEquality {
  static bool equals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }
}
