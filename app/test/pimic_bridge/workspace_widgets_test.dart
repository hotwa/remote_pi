import 'package:app/pimic_bridge/pimic_host.dart';
import 'package:app/pimic_bridge/workspace_widgets.dart';
import 'package:app/ui/chat/widgets/input_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pimic_addons/pimic_addons.dart';

void main() {
  PimicHost enabledHost() =>
      PimicHost()..acceptSaved(const AddonConfig(workspaceToolsEnabled: true));
  Future<void> pumpComposer(
    WidgetTester tester,
    PimicHost host,
    String target, {
    String? selected,
    List<String>? sends,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PimicWorkspaceComposer(
          host: host,
          target: target,
          currentTarget: () => selected ?? target,
          builder: (key, draft, changed, current) => InputBar(
            draftTarget: key,
            initialDraft: draft,
            onDraftChanged: changed,
            disabled: !current,
            onSend: (text) => sends?.add(text),
          ),
        ),
      ),
    ),
  );
  Finder draft() => find.byType(TextField);

  testWidgets(
    'A to B to A restores isolated drafts; send clears only its target',
    (tester) async {
      final host = enabledHost();
      final sends = <String>[];
      await pumpComposer(tester, host, 'peer-a:room', sends: sends);
      await tester.enterText(draft(), 'A unsent');
      await pumpComposer(tester, host, 'peer-b:room', sends: sends);
      expect(tester.widget<TextField>(draft()).controller!.text, isEmpty);
      await tester.enterText(draft(), 'B unsent');
      await pumpComposer(tester, host, 'peer-a:room', sends: sends);
      expect(tester.widget<TextField>(draft()).controller!.text, 'A unsent');
      expect(sends, isEmpty);
      await tester.tap(find.byKey(const Key('input-bar-action')));
      await tester.pumpAndSettle();
      expect(sends, ['A unsent']);
      expect(
        host.workspaceMemory.read(const WorkspaceKey('peer-a', 'room')).text,
        isEmpty,
      );
      await pumpComposer(tester, host, 'peer-b:room', sends: sends);
      expect(tester.widget<TextField>(draft()).controller!.text, 'B unsent');
      await tester.pumpWidget(const SizedBox());
      host.dispose();
    },
  );
  testWidgets(
    'enabling while typing preserves text; disabling keeps current text and clears cache',
    (tester) async {
      final host = PimicHost()..acceptSaved(const AddonConfig());
      await pumpComposer(tester, host, 'peer:room');
      await tester.enterText(draft(), 'already typed');
      host.acceptSaved(const AddonConfig(workspaceToolsEnabled: true));
      await tester.pump();
      expect(
        tester.widget<TextField>(draft()).controller!.text,
        'already typed',
      );
      expect(
        host.workspaceMemory.read(const WorkspaceKey('peer', 'room')).text,
        'already typed',
      );
      host.acceptSaved(const AddonConfig());
      await tester.pump();
      expect(
        tester.widget<TextField>(draft()).controller!.text,
        'already typed',
      );
      expect(host.workspaceMemory.count, 0);
      await tester.pumpWidget(const SizedBox());
      host.dispose();
    },
  );
  testWidgets('selection mismatch disables send and preserves source draft', (
    tester,
  ) async {
    final host = enabledHost();
    final sends = <String>[];
    await pumpComposer(tester, host, 'peer:a', sends: sends);
    await tester.enterText(draft(), 'A only');
    await pumpComposer(
      tester,
      host,
      'peer:a',
      selected: 'peer:b',
      sends: sends,
    );
    expect(tester.widget<TextField>(draft()).enabled, isFalse);
    await tester.tap(find.byKey(const Key('input-bar-action')));
    expect(sends, isEmpty);
    expect(
      host.workspaceMemory.read(const WorkspaceKey('peer', 'a')).text,
      'A only',
    );
    await tester.pumpWidget(const SizedBox());
    host.dispose();
  });
  testWidgets(
    'cleared identity generation prevents late callbacks repopulating old drafts',
    (tester) async {
      final host = enabledHost();
      ValueChanged<String>? callback;
      await tester.pumpWidget(
        MaterialApp(
          home: PimicWorkspaceComposer(
            host: host,
            target: 'peer:a',
            currentTarget: () => 'peer:a',
            builder: (_, _, changed, _) {
              callback = changed;
              return const SizedBox();
            },
          ),
        ),
      );
      callback!('old text');
      host.clearWorkspaceCache();
      callback!('late old text');
      expect(host.workspaceMemory.count, 0);
      await tester.pumpWidget(const SizedBox());
      host.dispose();
    },
  );
  testWidgets(
    'toolbar default off; enabled actions remain visible with a typed draft',
    (tester) async {
      final host = PimicHost()..acceptSaved(const AddonConfig());
      var actions = 0;
      String? blocked = '先结束录音';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                PimicWorkspaceActions(
                  host: host,
                  target: 'peer:a',
                  blockReason: () => blocked,
                  onActions: () => actions++,
                  actionsReason: '离线',
                ),
                InputBar(onSend: (_) {}),
              ],
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('pimic-pi-actions')), findsNothing);
      host.acceptSaved(const AddonConfig(workspaceToolsEnabled: true));
      await tester.pump();
      await tester.enterText(draft(), 'typed draft');
      await tester.tap(find.byKey(const Key('pimic-pi-actions')));
      expect(actions, 0);
      await tester.pumpAndSettle();
      blocked = null;
      await tester.tap(find.byKey(const Key('pimic-pi-actions')));
      expect(actions, 1);
      blocked = '先结束录音';
      await tester.tap(find.byKey(const Key('pimic-workspace-switch')));
      await tester.pump();
      expect(find.text('先结束录音'), findsOneWidget);
      expect(host.enabled, isFalse);
      await tester.pumpWidget(const SizedBox());
      host.dispose();
    },
  );
  testWidgets('scroll position restores per room and clears with feature off', (
    tester,
  ) async {
    final host = enabledHost();
    Future<void> page(String target) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PimicWorkspaceHistory(
            host: host,
            target: target,
            builder: (controller) => ListView.builder(
              controller: controller,
              itemExtent: 60,
              itemCount: 100,
              itemBuilder: (_, i) => Text('Row $i'),
            ),
          ),
        ),
      ),
    );
    await page('peer:a');
    await tester.drag(find.byType(ListView), const Offset(0, -350));
    await tester.pumpAndSettle();
    final saved = host.workspaceMemory
        .read(const WorkspaceKey('peer', 'a'))
        .scroll;
    expect(saved, greaterThan(0));
    await page('peer:b');
    expect(
      tester.widget<ListView>(find.byType(ListView)).controller!.offset,
      0,
    );
    await page('peer:a');
    expect(
      tester.widget<ListView>(find.byType(ListView)).controller!.offset,
      saved,
    );
    host.acceptSaved(const AddonConfig());
    await tester.pump();
    expect(host.workspaceMemory.count, 0);
    expect(tester.widget<ListView>(find.byType(ListView)).controller, isNull);
    await tester.pumpWidget(const SizedBox());
    host.dispose();
  });
}
