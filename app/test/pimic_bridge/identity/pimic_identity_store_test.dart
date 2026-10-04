import 'dart:async';
import 'dart:typed_data';

import 'package:app/pimic_bridge/identity/pimic_identity_store.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_pi_identity/remote_pi_identity.dart';

class CloudSpy implements OwnerIdentityStore {
  final inner = InMemoryOwnerIdentityStore();
  int loads = 0, saves = 0, watches = 0, deletes = 0, checks = 0;
  @override
  Future<OwnerIdentity?> load() {
    loads++;
    return inner.load();
  }

  @override
  Future<void> save(OwnerIdentity id) {
    saves++;
    return inner.save(id);
  }

  @override
  Stream<OwnerIdentity> watch() {
    watches++;
    return inner.watch();
  }

  @override
  Future<void> delete() {
    deletes++;
    return inner.delete();
  }

  @override
  Future<bool> isSyncAvailable() {
    checks++;
    return inner.isSyncAvailable();
  }
}

class WriteFailureStorage extends FlutterSecureStorage {
  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => throw StateError('storage unavailable');
}

Future<OwnerIdentity> fresh() async {
  final pair = await Ed25519().newKeyPair();
  return OwnerIdentity(
    ownerPk: Uint8List.fromList((await pair.extractPublicKey()).bytes),
    ownerSk: Uint8List.fromList(await pair.extractPrivateKeyBytes()),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CloudSpy cloud;
  late PimicIdentityStore store;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    cloud = CloudSpy();
    store = PimicIdentityStore(cloud);
  });

  test('default delegates original cloud load/save/check/delete', () async {
    expect(await store.isLocal(), false);
    expect(await store.load(), null);
    final id = await fresh();
    await store.save(id);
    expect(await store.load(), id);
    expect(await store.isSyncAvailable(), true);
    await store.delete();
    expect(cloud.loads, 2);
    expect(cloud.saves, 1);
    expect(cloud.checks, 1);
    expect(cloud.deletes, 1);
  });

  test('cloud unavailable never silently creates local identity', () async {
    final blocked = PimicIdentityStore(
      InMemoryOwnerIdentityStore(syncAvailable: false),
    );
    await expectLater(blocked.load(), throwsA(isA<SyncUnavailable>()));
    expect(await blocked.isLocal(), false);
  });

  test('cloud watcher is forwarded in default mode', () async {
    final event = store.watch().first;
    await Future<void>.delayed(Duration.zero);
    final id = await fresh();
    await cloud.save(id);
    expect(await event, id);
    expect(cloud.watches, 1);
  });

  test(
    'explicit local activation persists across new store instances',
    () async {
      await store.activateLocal(mayCreate: () async => true);
      final id = await store.load();
      expect(id, isNotNull);
      expect(await PimicIdentityStore(cloud).load(), id);
      expect(await store.isLocal(), true);
      expect(await store.isSyncAvailable(), true);
      expect(cloud.loads + cloud.saves + cloud.checks, 0);
    },
  );

  test(
    'activation idempotent and concurrent taps retain a single identity',
    () async {
      var guards = 0;
      await Future.wait(
        List.generate(
          8,
          (_) => store.activateLocal(
            mayCreate: () async {
              guards++;
              return true;
            },
          ),
        ),
      );
      final id = await store.load();
      await store.activateLocal(mayCreate: () async => false);
      expect(await store.load(), id);
      expect(guards, 1);
    },
  );

  test(
    'existing pairings/loaded cloud profile guard denies activation',
    () async {
      await expectLater(
        store.activateLocal(mayCreate: () async => false),
        throwsA(isA<SyncUnavailable>()),
      );
      expect(await store.isLocal(), false);
      expect(cloud.saves, 0);
    },
  );

  test('local watch cannot adopt a cloud identity', () async {
    await store.activateLocal(mayCreate: () async => true);
    expect(await store.watch().toList(), isEmpty);
    expect(cloud.watches, 0);
  });

  test(
    'local save accepts same identity and rejects rotation/deletion',
    () async {
      await store.activateLocal(mayCreate: () async => true);
      final id = (await store.load())!;
      await store.save(id);
      await expectLater(
        store.save(await fresh()),
        throwsA(isA<SyncUnavailable>()),
      );
      await expectLater(store.delete(), throwsA(isA<SyncUnavailable>()));
      expect(await store.load(), id);
      expect(cloud.saves + cloud.deletes, 0);
    },
  );

  test(
    'corrupt local identity fails closed without cloud fallback/overwrite',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'pimic.owner.local.v1': 'broken',
      });
      await expectLater(store.load(), throwsA(isA<SyncUnavailable>()));
      await expectLater(
        store.activateLocal(mayCreate: () async => true),
        throwsA(isA<SyncUnavailable>()),
      );
      expect(cloud.loads + cloud.saves, 0);
      expect(
        await const FlutterSecureStorage().read(key: 'pimic.owner.local.v1'),
        'broken',
      );
    },
  );

  test('same-size invalid public/private pair fails closed', () async {
    FlutterSecureStorage.setMockInitialValues({
      'pimic.owner.local.v1': '1:${'A' * 86}==',
    });
    await expectLater(store.load(), throwsA(isA<SyncUnavailable>()));
    expect(cloud.loads, 0);
  });

  test(
    'secure write failure prevents proceeding and does not create mode',
    () async {
      final failing = PimicIdentityStore(cloud, storage: WriteFailureStorage());
      await expectLater(
        failing.activateLocal(mayCreate: () async => true),
        throwsStateError,
      );
      expect(await store.isLocal(), false);
      expect(cloud.saves, 0);
    },
  );
}
