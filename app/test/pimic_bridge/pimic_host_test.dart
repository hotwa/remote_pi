import 'package:app/pimic_bridge/pimic_host.dart';
import 'package:app/pimic_bridge/pimic_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pimic_addons/pimic_addons.dart';

class _Storage implements AddonStorage {
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
  test(
    'construction is inert; missing/corrupt config keeps both tools off',
    () async {
      final storage = _Storage();
      final host = PimicHost(store: AddonConfigStore(storage: storage));
      expect(storage.reads, 0);
      expect(host.enabled, false);
      await host.ensureLoaded();
      expect(storage.reads, 1);
      await host.ensureLoaded();
      expect(storage.reads, 1);
      expect(host.enabled, false);
      host.dispose();
      storage.value = 'not json';
      final corrupt = PimicHost(store: AddonConfigStore(storage: storage));
      await corrupt.ensureLoaded();
      expect(corrupt.config.stt.enabled, false);
      expect(corrupt.config.optimizer.enabled, false);
      corrupt.dispose();
    },
  );

  testWidgets('default off adds no composer action or native audio calls', (
    tester,
  ) async {
    final host = PimicHost(store: AddonConfigStore(storage: _Storage()));
    final controller = TextEditingController(text: 'keep original draft');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PimicComposerTool(
            host: host,
            controller: controller,
            disabled: false,
            target: 'peer:main',
            currentTarget: () => 'peer:main',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pimic-draft-tools')), findsNothing);
    expect(find.byType(IconButton), findsNothing);
    expect(controller.text, 'keep original draft');
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    host.dispose();
  });

  testWidgets('optimizer only allows text without any microphone plugin', (
    tester,
  ) async {
    final host = PimicHost(store: AddonConfigStore(storage: _Storage()));
    host.acceptSaved(
      const AddonConfig(
        optimizer: OptimizerProfile(
          enabled: true,
          baseUrl: 'http://127.0.0.1:1/v1',
          model: 'fake',
        ),
      ),
    );
    final controller = TextEditingController(text: 'check README');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PimicComposerTool(
            host: host,
            controller: controller,
            disabled: false,
            target: 'peer:main',
            currentTarget: () => 'peer:main',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pimic-draft-tools')));
    await tester.pumpAndSettle();
    expect(find.text('Record'), findsNothing);
    await tester.enterText(find.byType(TextField), 'review project only');
    await tester.tap(find.text('Use draft'));
    await tester.pumpAndSettle();
    expect(controller.text, 'review project only');
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    host.dispose();
  });

  testWidgets('session switch discards a pending draft without sending', (
    tester,
  ) async {
    final host = PimicHost(store: AddonConfigStore(storage: _Storage()));
    host.acceptSaved(
      const AddonConfig(
        optimizer: OptimizerProfile(
          enabled: true,
          baseUrl: 'http://127.0.0.1:1/v1',
          model: 'fake',
        ),
      ),
    );
    var target = 'peer:main';
    final controller = TextEditingController(text: 'original');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PimicComposerTool(
            host: host,
            controller: controller,
            disabled: false,
            target: target,
            currentTarget: () => target,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pimic-draft-tools')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'old target draft');
    target = 'other:room';
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(controller.text, 'original');
    expect(find.text('Use draft'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    host.dispose();
  });
}
