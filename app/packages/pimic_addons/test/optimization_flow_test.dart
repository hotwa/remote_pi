import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pimic_addons/api_client.dart';
import 'package:pimic_addons/config.dart';
import 'package:pimic_addons/draft_session.dart';
import 'package:pimic_addons/optimization.dart';

import 'draft_session_test.dart' show FakeClient, enabledConfig;

void main() {
  test(
    'default correction, explicit rewrite, and mode change cancels late suggestion',
    () async {
      final client = FakeClient()..optimizeCompletion = Completer<String>();
      final session = DraftSession(
        config: enabledConfig,
        initialText: '检查项目',
        client: client,
      );
      expect(session.optimizationMode, OptimizationMode.correctionOnly);
      final pending = session.optimize();
      expect(client.lastMode, OptimizationMode.correctionOnly);
      final cancellation = client.lastCancellation!;
      session.selectOptimizationMode(OptimizationMode.rewritePrompt);
      expect(cancellation.isCancelled, isTrue);
      client.optimizeCompletion!.complete('stale correction');
      await pending;
      expect(session.suggestedDraft, isNull);
      expect(session.editableDraft, '检查项目');
      client.optimizeCompletion = null;
      await session.optimize();
      expect(client.lastMode, OptimizationMode.rewritePrompt);
      expect(session.suggestedDraft, 'cleaned suggestion');
      session.dispose();
    },
  );

  test(
    'critical change requires acknowledgement, keeps original, resets on edit and mode',
    () async {
      final client = FakeClient()..optimizeCompletion = Completer<String>();
      const original = '检查17891，不要修改文件。';
      final session = DraftSession(
        config: enabledConfig,
        initialText: original,
        client: client,
      );
      final pending = session.optimize();
      client.optimizeCompletion!.complete('修改17890。');
      await pending;
      expect(session.review!.needsAcknowledgement, isTrue);
      expect(session.canUseSuggestion, isFalse);
      session.useSuggestion();
      expect(session.useDraft(), original);
      session.acknowledgeChanges(true);
      expect(session.canUseSuggestion, isTrue);
      session.acknowledgeChanges(false);
      expect(session.canUseSuggestion, isFalse);
      session.acknowledgeChanges(true);
      session.useSuggestion();
      expect(session.editableDraft, '修改17890。');
      expect(session.changesAcknowledged, isFalse);
      session.selectOptimizationMode(OptimizationMode.rewritePrompt);
      expect(session.review, isNull);
      expect(session.suggestedDraft, isNull);
      session.dispose();
    },
  );

  test(
    'editing or opting out clears acknowledgement and suggestions',
    () async {
      final session = DraftSession(
        config: enabledConfig,
        initialText: '不要修改。',
        client: FakeClient(),
      );
      await session.optimize();
      session.acknowledgeChanges(true);
      session.editDraft('新稿');
      expect(session.review, isNull);
      expect(session.changesAcknowledged, isFalse);
      await session.optimize();
      session.acknowledgeChanges(true);
      session.cancelOptimization();
      expect(session.suggestedDraft, isNull);
      expect(session.changesAcknowledged, isFalse);
      expect(session.editableDraft, '新稿');
      session.dispose();
    },
  );

  test('real HTTP request uses selected mode and source envelope', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final bodies = <Map<String, dynamic>>[];
    server.listen((request) async {
      expect(request.uri.path, '/v1/chat/completions');
      bodies.add(
        jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>,
      );
      request.response.write(
        '{"choices":[{"finish_reason":"stop","message":{"content":"检查项目。"}}]}',
      );
      await request.response.close();
    });
    final profile = OptimizerProfile(
      enabled: true,
      baseUrl: 'http://127.0.0.1:${server.port}/v1',
      model: 'fixture-qwen',
      templateJson: builtinRewriteTemplate.exportJson(),
    );
    final api = AddonApiClient();
    await api.optimize(profile: profile, text: '检查项目。');
    await api.optimize(
      profile: profile,
      text: '检查项目。',
      mode: OptimizationMode.rewritePrompt,
    );
    expect(
      (bodies[0]['messages'] as List).first['content'],
      contains('CORRECTION_ONLY'),
    );
    expect(
      (bodies[1]['messages'] as List).first['content'],
      contains('REWRITE_PROMPT'),
    );
    expect(jsonDecode((bodies[1]['messages'] as List).last['content']), {
      'originalPrompt': '检查项目。',
    });
    expect(bodies.every((body) => body['stream'] == false), isTrue);
  });

  test('invalid rewrite template fails before any HTTP request', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var calls = 0;
    server.listen((request) async {
      calls++;
      await request.response.close();
    });
    await expectLater(
      AddonApiClient().optimize(
        profile: OptimizerProfile(
          enabled: true,
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
          model: 'fixture',
          templateJson: '{}',
        ),
        text: '检查项目',
        mode: OptimizationMode.rewritePrompt,
      ),
      throwsA(isA<AddonException>()),
    );
    expect(calls, 0);
  });
}
