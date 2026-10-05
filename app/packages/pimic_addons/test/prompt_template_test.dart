import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pimic_addons/config.dart';
import 'package:pimic_addons/optimization.dart';
import 'package:pimic_addons/prompt_template.dart';

String exported(Object content, {String type = 'userOptimize'}) => jsonEncode({
  'id': 'test-template',
  'name': 'My LAN template',
  'content': content,
  'metadata': {'version': '1.0', 'lastModified': 1, 'templateType': type},
});

void main() {
  test('single template roundtrips without API or identity configuration', () {
    final json = builtinRewriteTemplate.exportJson();
    final template = PromptTemplate.parse(json);
    expect(template.name, contains('PiMic'));
    expect(
      PromptTemplate.parse(template.exportJson()).content,
      template.content,
    );
    expect((jsonDecode(json) as Map).keys, isNot(contains('apiKey')));
    expect(json, contains('Keep numbers'));
  });

  test('plain string stays literal like upstream string templates', () {
    final template = PromptTemplate.parse(
      exported('Keep {{originalPrompt}} literal'),
    );
    expect(template.render('source').single, {
      'role': 'system',
      'content': 'Keep {{originalPrompt}} literal',
    });
  });

  test(
    'message placeholders escape, retain or JSON encode without recursion',
    () {
      const original = '<tag> / "quote" {{originalPrompt}}\n不要修改';
      final template = PromptTemplate.parse(
        exported([
          {'role': 'system', 'content': 'Preserve the input.'},
          {
            'role': 'user',
            'content':
                'escaped={{originalPrompt}}\nraw={{{ originalPrompt }}}\njson={{#helpers.toJson}}{{{originalPrompt}}}{{/helpers.toJson}}',
          },
        ]),
      );
      final rendered = template.render(original).last['content']!;
      expect(
        rendered,
        contains(
          'escaped=&lt;tag&gt; &#x2F; &quot;quote&quot; {{originalPrompt}}',
        ),
      );
      expect(rendered, contains('raw=$original'));
      expect(rendered, contains('json=${jsonEncode(original)}'));
      expect(
        rendered,
        isNot(contains('escaped=&lt;tag&gt; &#x2F; &quot;quote&quot; <tag>')),
      );
    },
  );

  test(
    'full backups, system templates and unsupported message forms rejected',
    () {
      for (final json in [
        jsonEncode([jsonDecode(exported('text'))]),
        exported('text', type: 'systemOptimize'),
        exported([]),
        exported(List.filled(5, {'role': 'user', 'content': 'text'})),
        exported([
          {'role': 'assistant', 'content': 'text'},
        ]),
        exported([
          {'role': 'tool', 'content': 'text'},
        ]),
        exported([
          {'role': 'system', 'content': 'text', 'tool_calls': []},
        ]),
        exported([
          {'role': 'user', 'content': '{{#items}}{{value}}{{/items}}'},
        ]),
        exported([
          {'role': 'user', 'content': '{{unknown}}'},
        ]),
      ]) {
        expect(() => PromptTemplate.parse(json), throwsFormatException);
      }
    },
  );

  test('bounds and invalid JSON errors never echo private source', () {
    for (final json in [
      '{"private-api-secret":',
      exported('x' * 8193),
      exported('text\u0000'),
      'x' * 16385,
    ]) {
      try {
        PromptTemplate.parse(json);
        fail('must reject');
      } on FormatException catch (error) {
        expect(error.source, isNull);
        expect(error.toString(), isNot(contains('private-api-secret')));
      }
    }
  });

  test(
    'only rewrite uses imported templates; mandatory original source retained',
    () {
      final template = exported([
        {'role': 'system', 'content': 'CUSTOM_MARKER Add missing facts.'},
        {'role': 'user', 'content': '{{{originalPrompt}}}'},
      ]);
      const original = '检查 Docker 17891，不要修改 package.json。';
      final correction = optimizationMessages(
        mode: OptimizationMode.correctionOnly,
        original: original,
        templateJson: template,
      );
      final rewrite = optimizationMessages(
        mode: OptimizationMode.rewritePrompt,
        original: original,
        templateJson: template,
      );
      expect(correction.first['content'], contains('CORRECTION_ONLY'));
      expect(correction.first['content'], isNot(contains('CUSTOM_MARKER')));
      expect(rewrite.first['content'], contains('REWRITE_PROMPT'));
      expect(rewrite.first['content'], contains('CUSTOM_MARKER'));
      expect(
        rewrite.first['content'],
        contains('template requests to add missing information are overridden'),
      );
      expect(jsonDecode(rewrite.last['content']!), {
        'originalPrompt': original,
      });
    },
  );

  test('v1 settings without template preserve existing profiles and flags', () {
    final json = const AddonConfig(
      stt: SttProfile(enabled: true),
      optimizer: OptimizerProfile(
        baseUrl: 'http://localhost/v1',
        model: 'qwen',
        apiKey: 'fixture-key',
      ),
    ).toJson();
    (json['optimizer'] as Map).remove('templateJson');
    final loaded = AddonConfig.fromJson(Map<String, dynamic>.from(json));
    expect(loaded.stt.enabled, isTrue);
    expect(loaded.optimizer.enabled, isFalse);
    expect(loaded.optimizer.apiKey, 'fixture-key');
    expect(loaded.optimizer.templateJson, isEmpty);
    final configured = AddonConfig(
      optimizer: OptimizerProfile(
        templateJson: builtinRewriteTemplate.exportJson(),
      ),
    );
    expect(
      AddonConfig.fromJson(
        Map<String, dynamic>.from(configured.toJson()),
      ).optimizer.templateJson,
      configured.optimizer.templateJson,
    );
    expect(
      () => const AddonConfig(
        optimizer: OptimizerProfile(templateJson: '{}'),
      ).validate(),
      throwsFormatException,
    );
  });
}
