// Explicit LAN smoke test. Not part of the default offline app test suite.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pimic_addons/pimic_addons.dart';

void main() {
  test(
    'configured LAN STT transcribes an existing bounded WAV',
    () async {
      final path = Platform.environment['PIMIC_STT_SMOKE_WAV'];
      expect(path, isNotNull, reason: 'Set PIMIC_STT_SMOKE_WAV explicitly.');
      final wav = await File(path!).readAsBytes();
      final watch = Stopwatch()..start();
      final text = await AddonApiClient().transcribe(
        profile: SttProfile(
          enabled: true,
          baseUrl:
              Platform.environment['PIMIC_STT_BASE_URL'] ??
              'http://192.168.11.130:50060/v1',
          model: Platform.environment['PIMIC_STT_MODEL'] ?? 'large-v3-turbo',
        ),
        wav: wav,
      );
      watch.stop();
      expect(text.trim(), isNotEmpty);
      // Never log headers, API keys, audio bytes or provider error bodies.
      // Transcript is intentionally visible for the user's recognition check.
      // ignore: avoid_print
      print('LAN STT ${watch.elapsedMilliseconds} ms: $text');
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
