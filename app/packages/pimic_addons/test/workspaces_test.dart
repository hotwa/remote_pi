import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pimic_addons/pimic_addons.dart';

void main() {
  test(
    'old configuration defaults off; workspace tools need no model profile',
    () {
      final old = const AddonConfig(stt: SttProfile(enabled: true)).toJson()
        ..remove('workspaceToolsEnabled');
      final loaded = AddonConfig.fromJson(Map<String, dynamic>.from(old));
      expect(loaded.workspaceToolsEnabled, isFalse);
      expect(loaded.stt.enabled, isTrue);
      const config = AddonConfig(workspaceToolsEnabled: true);
      config.validate();
      expect(
        AddonConfig.fromJson(
          Map<String, dynamic>.from(config.toJson()),
        ).workspaceToolsEnabled,
        isTrue,
      );
      expect(config.stt.enabled || config.optimizer.enabled, isFalse);
    },
  );
  test(
    'stable peer and room IDs prevent same-label and delimiter collisions',
    () {
      final memory = WorkspaceMemory();
      const a = WorkspaceKey('peer1', 'room'),
          b = WorkspaceKey('peer2', 'room');
      memory.saveText(a, 'A draft');
      memory.saveText(b, 'B draft');
      expect(memory.read(a).text, 'A draft');
      expect(memory.read(b).text, 'B draft');
      expect(
        const WorkspaceKey('a:b', 'c').id,
        isNot(const WorkspaceKey('a', 'b:c').id),
      );
    },
  );
  test(
    'text and scroll are independent and negative or nonfinite offsets ignored',
    () {
      final memory = WorkspaceMemory();
      const a = WorkspaceKey('peer', 'room');
      memory.saveText(a, 'draft');
      memory.saveScroll(a, 72);
      memory.saveText(a, 'new draft');
      for (final n in [-1.0, double.nan, double.infinity]) {
        memory.saveScroll(a, n);
      }
      expect(memory.read(a).text, 'new draft');
      expect(memory.read(a).scroll, 72);
    },
  );
  test(
    'LRU bounds target count and total characters; read preserves recent draft',
    () {
      final memory = WorkspaceMemory();
      const first = WorkspaceKey('peer', '0');
      for (var i = 0; i < 32; i++) {
        memory.saveText(WorkspaceKey('peer', '$i'), '$i');
      }
      memory.read(first);
      memory.saveText(const WorkspaceKey('peer', '32'), '32');
      expect(memory.count, 32);
      expect(memory.read(first).text, '0');
      expect(memory.read(const WorkspaceKey('peer', '1')).text, isEmpty);
      memory.clear();
      for (var i = 0; i < 12; i++) {
        memory.saveText(WorkspaceKey('peer', '$i'), 'x' * 64000);
      }
      expect(memory.characters, lessThanOrEqualTo(512000));
      expect(memory.count, 8);
    },
  );
  test(
    'oversize drafts are marked instead of silently truncated; shrinking recovers',
    () {
      final memory = WorkspaceMemory();
      const key = WorkspaceKey('peer', 'room');
      expect(memory.saveText(key, 'x' * 64001), isFalse);
      expect(memory.read(key).tooLarge, isTrue);
      expect(memory.read(key).text, isEmpty);
      memory.saveScroll(key, 55);
      expect(memory.read(key).tooLarge, isTrue);
      expect(memory.saveText(key, 'smaller draft'), isTrue);
      expect(memory.read(key).tooLarge, isFalse);
    },
  );
  test('favorites bounded and clearing removes all ephemeral state', () {
    final memory = WorkspaceMemory();
    for (var i = 0; i < 140; i++) {
      memory.toggleFavorite(WorkspaceKey('peer', '$i'));
    }
    expect(memory.favorites.length, 128);
    const key = WorkspaceKey('peer', '139');
    memory.toggleFavorite(key);
    expect(memory.isFavorite(key), isFalse);
    memory.saveText(key, 'private draft');
    memory.clear();
    expect(memory.favorites, isEmpty);
    expect(memory.count, 0);
  });
  const targets = [
    WorkspaceTarget(
      key: WorkspaceKey('peer-a', 'alpha'),
      device: 'Mac-7',
      title: 'App',
      path: '/work/app',
      online: true,
    ),
    WorkspaceTarget(
      key: WorkspaceKey('peer-a', 'docs'),
      device: 'Mac-7',
      title: 'Docs',
      path: '/work/docs',
    ),
    WorkspaceTarget(
      key: WorkspaceKey('peer-b', 'alpha'),
      device: 'Mac-5',
      title: 'App',
      path: '/work/app',
      online: true,
      working: true,
    ),
  ];
  testWidgets(
    'picker groups and searches by device/project, selecting uses identity',
    (tester) async {
      WorkspaceTarget? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspacePicker(
              targets: targets,
              memory: WorkspaceMemory(),
              current: targets.first.key,
              onSelect: (t) => selected = t,
            ),
          ),
        ),
      );
      expect(find.text('Mac-5'), findsOneWidget);
      expect(find.text('Mac-7'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('workspace-search')),
        'Mac-5',
      );
      await tester.pump();
      expect(find.text('Mac-7'), findsNothing);
      await tester.tap(
        find.byKey(ValueKey('workspace-${targets.last.key.id}')),
      );
      expect(selected!.key, targets.last.key);
    },
  );
  testWidgets(
    'favorites do not change target; relay loss marks presence unknown',
    (tester) async {
      var selected = 0;
      final memory = WorkspaceMemory();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspacePicker(
              targets: targets,
              memory: memory,
              relayConnected: false,
              onSelect: (_) => selected++,
            ),
          ),
        ),
      );
      expect(find.text('连接状态未知'), findsNWidgets(3));
      await tester.tap(find.byTooltip('收藏').first);
      await tester.pump();
      expect(selected, 0);
      await tester.tap(find.byKey(const Key('workspace-favorites')));
      await tester.pump();
      expect(find.text('App'), findsOneWidget);
      expect(find.text('Docs'), findsNothing);
    },
  );
}
