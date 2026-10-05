import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pimic_addons/config.dart';
import 'package:pimic_addons/optimization.dart';
import 'package:pimic_addons/settings_page.dart';
import 'package:pimic_addons/template_tools.dart';

import 'config_test.dart' show MemoryStorage;
import 'draft_session_test.dart' show FakeClient;
import 'draft_sheet_test.dart' show openSheet, requestCleanup;

void main() {
  testWidgets(
    'mode selection stays local, default correction, rewrite requires request',
    (tester) async {
      final client = FakeClient();
      await openSheet(tester, client: client, initialText: '检查项目');
      expect(find.byKey(const Key('optimization-mode')), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('optimize-this-draft')));
      await tester.tap(find.byKey(const Key('optimize-this-draft')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SegmentedButton<OptimizationMode>>(
              find.byKey(const Key('optimization-mode')),
            )
            .selected,
        {OptimizationMode.correctionOnly},
      );
      await tester.ensureVisible(find.text('整理提示词'));
      await tester.tap(find.text('整理提示词'));
      await tester.pumpAndSettle();
      expect(client.optimizeCalls, 0);
      await tester.ensureVisible(find.byKey(const Key('optimize-draft')));
      await tester.tap(find.byKey(const Key('optimize-draft')));
      await tester.pumpAndSettle();
      expect(client.lastMode, OptimizationMode.rewritePrompt);
      await tester.tap(find.byTooltip('Close draft'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'changed restriction blocks suggestion until explicit acknowledgement',
    (tester) async {
      final client = FakeClient()..optimizeCompletion = Completer<String>();
      await openSheet(tester, client: client, initialText: '检查17891，不要修改文件。');
      await requestCleanup(tester);
      await tester.pump();
      client.optimizeCompletion!.complete('修改17890。');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('protected-change-review')), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('use-suggestion')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('editable-draft')))
            .controller!
            .text,
        '检查17891，不要修改文件。',
      );
      await tester.ensureVisible(
        find.byKey(const Key('acknowledge-protected-changes')),
      );
      await tester.tap(find.byKey(const Key('acknowledge-protected-changes')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('use-suggestion')))
            .onPressed,
        isNotNull,
      );
      await tester.ensureVisible(find.byKey(const Key('use-suggestion')));
      await tester.tap(find.byKey(const Key('use-suggestion')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('editable-draft')))
            .controller!
            .text,
        '修改17890。',
      );
      await tester.tap(find.byTooltip('Close draft'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('import validates locally and export contains template only', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TemplateTools(controller: controller),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('prompt-template-tools')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-prompt-template')));
    await tester.pumpAndSettle();
    expect(
      (jsonDecode(copied!) as Map)['metadata']['templateType'],
      'userOptimize',
    );
    expect(copied, isNot(contains('apiKey')));
    await tester.tap(find.byKey(const Key('import-prompt-template')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('prompt-template-json')), '{}');
    await tester.tap(find.byKey(const Key('confirm-prompt-template')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('prompt-template-error')), findsOneWidget);
    expect(controller.text, isEmpty);
    await tester.enterText(
      find.byKey(const Key('prompt-template-json')),
      builtinRewriteTemplate.exportJson(),
    );
    await tester.tap(find.byKey(const Key('confirm-prompt-template')));
    await tester.pumpAndSettle();
    expect(controller.text, builtinRewriteTemplate.exportJson());
    await tester.ensureVisible(find.byKey(const Key('reset-prompt-template')));
    await tester.tap(find.byKey(const Key('reset-prompt-template')));
    await tester.pumpAndSettle();
    expect(controller.text, isEmpty);
  });

  testWidgets(
    'save imported template retains disabled flags and stored endpoints',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final storage = MemoryStorage();
      final store = AddonConfigStore(storage: storage);
      await store.save(
        const AddonConfig(
          optimizer: OptimizerProfile(
            baseUrl: 'http://fixture.local/v1',
            model: 'future-qwen',
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AddonSettingsPage(store: store),
                  ),
                ),
                child: const Text('Settings'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('prompt-template-tools')),
      );
      await tester.tap(find.byKey(const Key('prompt-template-tools')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('import-prompt-template')),
      );
      await tester.tap(find.byKey(const Key('import-prompt-template')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('prompt-template-json')),
        builtinRewriteTemplate.exportJson(),
      );
      await tester.tap(find.byKey(const Key('confirm-prompt-template')));
      await tester.pumpAndSettle();
      expect((await store.load()).optimizer.templateJson, isEmpty);
      await tester.ensureVisible(find.text('Save settings'));
      await tester.tap(find.text('Save settings'));
      await tester.pumpAndSettle();
      final loaded = await store.load();
      expect(loaded.stt.enabled, isFalse);
      expect(loaded.optimizer.enabled, isFalse);
      expect(loaded.optimizer.baseUrl, 'http://fixture.local/v1');
      expect(loaded.optimizer.model, 'future-qwen');
      expect(
        loaded.optimizer.templateJson,
        builtinRewriteTemplate.exportJson(),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
