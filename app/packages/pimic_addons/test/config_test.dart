import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:pimic_addons/config.dart';

class MemoryStorage implements AddonStorage {
  String? value;
  int reads = 0;
  @override
  Future<String?> read() async {
    reads++;
    return value;
  }

  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}

void main() {
  test('construction is lazy and defaults disabled', () async {
    final storage = MemoryStorage();
    final store = AddonConfigStore(storage: storage);
    expect(storage.reads, 0);
    final config = await store.load();
    expect(config.stt.enabled, false);
    expect(config.optimizer.enabled, false);
    expect(config.stt.model, 'large-v3-turbo');
  });
  test('flags are independent and saving URL does not enable', () async {
    final store = AddonConfigStore(storage: MemoryStorage());
    await store.save(
      const AddonConfig(
        stt: SttProfile(baseUrl: 'http://localhost/v1'),
        optimizer: OptimizerProfile(
          enabled: true,
          baseUrl: 'https://example.com/v1',
          model: 'test',
        ),
      ),
    );
    final loaded = await store.load();
    expect(loaded.stt.enabled, false);
    expect(loaded.optimizer.enabled, true);
  });
  test('corrupt config fails closed', () async {
    final storage = MemoryStorage();
    for (final raw in [
      '{',
      '{}',
      jsonEncode({
        'version': 1,
        'stt': {'enabled': true},
        'optimizer': {},
      }),
    ]) {
      storage.value = raw;
      final config = await AddonConfigStore(storage: storage).load();
      expect(config.stt.enabled, false);
      expect(config.optimizer.enabled, false);
    }
  });
  test(
    'enabled invalid profile is rejected; disabled empty profiles persist',
    () async {
      final store = AddonConfigStore(storage: MemoryStorage());
      await store.save(
        const AddonConfig(
          stt: SttProfile(baseUrl: '', model: ''),
        ),
      );
      await expectLater(
        store.save(
          const AddonConfig(optimizer: OptimizerProfile(enabled: true)),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'profile bounds reject injected controls and accept flexible model IDs',
    () {
      for (final model in ['model\r\nfield', 'model\u0000', 'model\u007f']) {
        expect(
          () => validateProfile('http://localhost/v1', model),
          throwsFormatException,
        );
      }
      expect(
        () => validateProfile('http://localhost/${'x' * 2048}', 'test'),
        throwsFormatException,
      );
      expect(
        () => validateProfile('http://localhost/v1\r\n', 'test'),
        throwsFormatException,
      );
      validateProfile('http://localhost/v1', 'org/model:latest 4-bit');
      for (final key in ['x' * 8193, 'key\tsecret', 'key\u0085']) {
        expect(() => validateApiKey(key), throwsFormatException);
      }
      validateApiKey('');
      validateApiKey('x' * 8192);
      for (final language in ['zh\r\nmodel', 'zh CN', 'x' * 33, 'zh/region']) {
        expect(() => validateLanguage(language), throwsFormatException);
      }
      for (final language in ['', 'zh', 'en-US', 'zh_Hans', 'es419']) {
        validateLanguage(language);
      }
    },
  );
}
