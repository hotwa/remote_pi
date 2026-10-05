import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pimic_addons/api_client.dart';
import 'package:pimic_addons/config.dart';

Uint8List wav() {
  final bytes = Uint8List(46);
  final data = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, ascii.encode('RIFF'));
  data.setUint32(4, 38, Endian.little);
  bytes.setRange(8, 16, ascii.encode('WAVEfmt '));
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 16000, Endian.little);
  data.setUint32(28, 32000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  bytes.setRange(36, 40, ascii.encode('data'));
  data.setUint32(40, 2, Endian.little);
  return bytes;
}

void main() {
  late HttpServer server;
  late String base;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}/v1';
  });
  tearDown(() async {
    await server.close(force: true);
  });
  OptimizerProfile profile() => OptimizerProfile(
    enabled: true,
    baseUrl: base,
    model: 'test',
    apiKey: 'private-key',
  );

  test(
    'model catalog GET uses explicit base and optional bearer without a model',
    () async {
      server.listen((request) async {
        expect(request.method, 'GET');
        expect(request.uri.path, '/v1/models');
        expect(request.headers.value('authorization'), 'Bearer catalog-key');
        expect(await request.fold<int>(0, (n, bytes) => n + bytes.length), 0);
        request.response.write(
          '{"data":[{"id":"model-b"},{"id":"model-a"},{"id":"model-b"}]}',
        );
        await request.response.close();
      });
      expect(
        await AddonApiClient().listModels(
          baseUrl: '$base/',
          apiKey: 'catalog-key',
        ),
        ['model-b', 'model-a'],
      );
    },
  );

  test(
    'catalog without key omits authorization and rejects malformed IDs',
    () async {
      server.listen((request) async {
        expect(request.headers.value('authorization'), isNull);
        request.response.write(
          jsonEncode({
            'data': [
              {'id': 'model\nprivate-key'},
            ],
          }),
        );
        await request.response.close();
      });
      await expectLater(
        AddonApiClient().listModels(baseUrl: base),
        throwsA(
          isA<AddonException>().having(
            (e) => e.message,
            'sanitized',
            'The service returned an invalid model list.',
          ),
        ),
      );
    },
  );

  test('catalog count is bounded', () async {
    server.listen((request) async {
      request.response.write(
        jsonEncode({
          'data': List.generate(257, (n) => {'id': 'model$n'}),
        }),
      );
      await request.response.close();
    });
    await expectLater(
      AddonApiClient().listModels(baseUrl: base),
      throwsA(isA<AddonException>()),
    );
  });

  test('catalog redirects are not followed or leak keys', () async {
    var requests = 0;
    server.listen((request) async {
      requests++;
      request.response.statusCode = 302;
      request.response.headers.set('location', '$base/other');
      request.response.write('catalog-key');
      await request.response.close();
    });
    await expectLater(
      AddonApiClient().listModels(baseUrl: base, apiKey: 'catalog-key'),
      throwsA(
        isA<AddonException>().having(
          (e) => e.message,
          'status',
          'Service request failed (HTTP 302).',
        ),
      ),
    );
    expect(requests, 1);
  });

  test('missing catalog gives safe HTTP error for manual entry', () async {
    server.listen((request) async {
      request.response.statusCode = 404;
      request.response.write('secret-provider-body');
      await request.response.close();
    });
    await expectLater(
      AddonApiClient().listModels(baseUrl: base),
      throwsA(
        isA<AddonException>().having(
          (e) => e.message,
          'status',
          'Service request failed (HTTP 404).',
        ),
      ),
    );
  });

  test('catalog timeout and cancellation close requests', () async {
    final received = Completer<void>();
    server.listen((request) async {
      if (!received.isCompleted) received.complete();
      await request.drain<void>();
    });
    await expectLater(
      AddonApiClient(
        timeout: const Duration(milliseconds: 50),
      ).listModels(baseUrl: base),
      throwsA(
        isA<AddonException>().having(
          (e) => e.message,
          'timeout',
          'Service request timed out.',
        ),
      ),
    );
    final cancellation = AddonCancellation();
    final future = AddonApiClient().listModels(
      baseUrl: base,
      cancellation: cancellation,
    );
    final check = expectLater(
      future,
      throwsA(
        isA<AddonException>().having(
          (e) => e.message,
          'cancel',
          'Request cancelled.',
        ),
      ),
    );
    cancellation.cancel();
    await check;
  });

  test('invalid catalog URL or key causes no request', () async {
    var requests = 0;
    server.listen((request) {
      requests++;
      request.response.close();
    });
    await expectLater(
      AddonApiClient().listModels(baseUrl: '$base?key=private'),
      throwsA(isA<AddonException>()),
    );
    await expectLater(
      AddonApiClient().listModels(baseUrl: base, apiKey: 'bad\nkey'),
      throwsA(isA<AddonException>()),
    );
    expect(requests, 0);
  });

  test('empty catalog preserves manual entry option', () async {
    server.listen((request) async {
      request.response.write('{"data":[]}');
      await request.response.close();
    });
    await expectLater(
      AddonApiClient().listModels(baseUrl: base),
      throwsA(
        isA<AddonException>().having(
          (e) => e.message,
          'manual',
          contains('manually'),
        ),
      ),
    );
  });

  test('transcription posts multipart to configured endpoint', () async {
    final received = Completer<String>();
    server.listen((request) async {
      expect(request.uri.path, '/v1/audio/transcriptions');
      expect(request.headers.contentType?.mimeType, 'multipart/form-data');
      received.complete(await latin1.decoder.bind(request).join());
      request.response.write('{"text":" hello "}');
      await request.response.close();
    });
    final text = await AddonApiClient().transcribe(
      profile: SttProfile(enabled: true, baseUrl: base),
      wav: wav(),
    );
    expect(text, 'hello');
    expect(await received.future, contains('large-v3-turbo'));
  });
  test(
    'empty transcription is reported as no speech, not a corrupt service',
    () async {
      server.listen((request) async {
        await request.drain<void>();
        request.response.write('{"text":"   "}');
        await request.response.close();
      });
      await expectLater(
        AddonApiClient().transcribe(
          profile: SttProfile(enabled: true, baseUrl: base),
          wav: wav(),
        ),
        throwsA(
          isA<AddonException>().having(
            (e) => e.message,
            'silence',
            contains('No speech was detected'),
          ),
        ),
      );
    },
  );
  test(
    '59-second WAV with metadata remains within import and upload limits',
    () async {
      const pcmBytes = 59 * 16000 * 2;
      const metadataBytes = 90000;
      final recording = Uint8List(44 + pcmBytes + 8 + metadataBytes);
      recording.setRange(0, 44, wav().sublist(0, 44));
      final data = ByteData.sublistView(recording);
      data.setUint32(4, recording.length - 8, Endian.little);
      data.setUint32(40, pcmBytes, Endian.little);
      final metadataOffset = 44 + pcmBytes;
      recording.setRange(
        metadataOffset,
        metadataOffset + 4,
        ascii.encode('JUNK'),
      );
      data.setUint32(metadataOffset + 4, metadataBytes, Endian.little);
      var receivedBytes = 0;
      server.listen((request) async {
        expect(request.uri.path, '/v1/audio/transcriptions');
        await for (final chunk in request) {
          receivedBytes += chunk.length;
        }
        request.response.write('{"text":"metadata recording"}');
        await request.response.close();
      });
      expect(
        await AddonApiClient().transcribe(
          profile: SttProfile(enabled: true, baseUrl: base),
          wav: recording,
        ),
        'metadata recording',
      );
      expect(receivedBytes, greaterThan(recording.length));
      expect(receivedBytes, lessThan(2001000));
    },
  );
  test('optimizer sends nonstream draft and returns text', () async {
    server.listen((request) async {
      expect(request.uri.path, '/v1/chat/completions');
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      expect(body['stream'], false);
      expect(request.headers.value('authorization'), 'Bearer private-key');
      request.response.write(
        '{"choices":[{"finish_reason":"stop","message":{"content":"Clean draft"}}]}',
      );
      await request.response.close();
    });
    expect(
      await AddonApiClient().optimize(profile: profile(), text: 'original'),
      'Clean draft',
    );
  });
  test('malformed responses are sanitized', () async {
    server.listen((request) async {
      await request.drain<void>();
      request.response.write('private-key secret-server-body');
      await request.response.close();
    });
    await expectLater(
      AddonApiClient().optimize(profile: profile(), text: 'draft'),
      throwsA(
        isA<AddonException>().having(
          (e) => e.message,
          'safe error',
          isNot(contains('private-key')),
        ),
      ),
    );
  });
  test('HTTP errors do not expose response body', () async {
    server.listen((request) async {
      await request.drain<void>();
      request.response.statusCode = 401;
      request.response.write('private-key');
      await request.response.close();
    });
    await expectLater(
      AddonApiClient().optimize(profile: profile(), text: 'draft'),
      throwsA(
        isA<AddonException>().having(
          (e) => e.message,
          'safe error',
          'Service request failed (HTTP 401).',
        ),
      ),
    );
  });
  test('response byte bound enforced', () async {
    server.listen((request) async {
      await request.drain<void>();
      request.response.write('x' * (AddonApiClient.maxResponseBytes + 1));
      await request.response.close();
    });
    await expectLater(
      AddonApiClient().optimize(profile: profile(), text: 'draft'),
      throwsA(
        isA<AddonException>().having(
          (e) => e.message,
          'limit',
          contains('too large'),
        ),
      ),
    );
  });
  test('timeout and cancellation close outstanding requests', () async {
    server.listen((request) async {
      await request.drain<void>();
    });
    await expectLater(
      AddonApiClient(
        timeout: const Duration(milliseconds: 50),
      ).optimize(profile: profile(), text: 'draft'),
      throwsA(
        isA<AddonException>().having(
          (e) => e.message,
          'timeout',
          contains('timed out'),
        ),
      ),
    );
    final cancellation = AddonCancellation(generation: 7);
    final future = AddonApiClient().optimize(
      profile: profile(),
      text: 'draft',
      cancellation: cancellation,
    );
    final assertion = expectLater(
      future,
      throwsA(
        isA<AddonException>().having(
          (e) => e.message,
          'cancel',
          contains('cancelled'),
        ),
      ),
    );
    cancellation.cancel();
    await assertion;
    expect(cancellation.generation, 7);
  });
  test('control phrases bypass optimizer without a request', () async {
    var requests = 0;
    server.listen((request) {
      requests++;
      request.response.close();
    });
    for (final text in [
      '停止。',
      'cancel!',
      '等等，先读代码',
      '改成测试',
      '停一下，不要执行命令，也不要删除文件',
      'STOP, do not execute commands or delete files',
      'cancel this operation',
      '停止：保留所有文件',
    ]) {
      expect(
        await AddonApiClient().optimize(profile: profile(), text: text),
        text,
      );
    }
    expect(requests, 0);
  });
  test('ordinary words sharing control prefixes are not controls', () {
    for (final text in [
      'stopwatch implementation',
      'cancellation token',
      'stopping logic',
      '取消按钮的样式',
    ]) {
      expect(isControlDraft(text), false);
    }
  });
  test('unsafe fields are rejected before multipart or headers', () async {
    var requests = 0;
    server.listen((request) {
      requests++;
      request.response.close();
    });
    for (final invalid in [
      SttProfile(enabled: true, baseUrl: base, model: 'm\r\nfield'),
      SttProfile(enabled: true, baseUrl: base, language: 'zh\r\nfield'),
      SttProfile(enabled: true, baseUrl: base, apiKey: 'key\tvalue'),
      SttProfile(enabled: true, baseUrl: base, apiKey: 'x' * 8193),
      SttProfile(enabled: true, baseUrl: '$base/${'x' * 2048}'),
    ]) {
      await expectLater(
        AddonApiClient().transcribe(profile: invalid, wav: wav()),
        throwsA(isA<AddonException>()),
      );
    }
    expect(requests, 0);
  });
  test('truncated, tool-call and control output rejected', () async {
    var response = 0;
    final bodies = [
      {
        'choices': [
          {
            'finish_reason': 'length',
            'message': {'content': 'partial'},
          },
        ],
      },
      {
        'choices': [
          {
            'finish_reason': 'stop',
            'message': {'content': 'draft', 'tool_calls': []},
          },
        ],
      },
      {
        'choices': [
          {
            'finish_reason': 'stop',
            'message': {'content': '停止'},
          },
        ],
      },
    ];
    server.listen((request) async {
      await request.drain<void>();
      request.response.write(jsonEncode(bodies[response++]));
      await request.response.close();
    });
    for (var i = 0; i < bodies.length; i++) {
      await expectLater(
        AddonApiClient().optimize(profile: profile(), text: 'read code'),
        throwsA(isA<AddonException>()),
      );
    }
  });
  test('disabled and oversized input rejected before request', () async {
    await expectLater(
      AddonApiClient().optimize(
        profile: const OptimizerProfile(),
        text: 'draft',
      ),
      throwsA(isA<AddonException>()),
    );
    await expectLater(
      AddonApiClient().transcribe(
        profile: SttProfile(enabled: true, baseUrl: base),
        wav: Uint8List(AddonApiClient.maxWavBytes + 1),
      ),
      throwsA(isA<AddonException>()),
    );
    await expectLater(
      AddonApiClient().optimize(profile: profile(), text: 'x' * 16001),
      throwsA(isA<AddonException>()),
    );
  });
}
