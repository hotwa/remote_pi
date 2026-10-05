import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pimic_addons/config.dart';
import 'package:pimic_addons/settings_page.dart';
import 'config_test.dart' show MemoryStorage;

void main() {
  testWidgets(
    'loads off defaults, keys masked and enabled invalid shows error',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final storage = MemoryStorage();
      await tester.pumpWidget(
        MaterialApp(
          home: AddonSettingsPage(store: AddonConfigStore(storage: storage)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<SwitchListTile>(find.byType(SwitchListTile))
            .every((w) => !w.value),
        true,
      );
      expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .where((w) => w.obscureText)
            .length,
        2,
      );
      await tester.ensureVisible(find.text('Draft cleanup'));
      await tester.tap(find.text('Draft cleanup'));
      await tester.pump();
      await tester.ensureVisible(find.text('Save settings'));
      await tester.tap(find.text('Save settings'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Enter an HTTP'), findsOneWidget);
      expect(storage.value, isNull);
    },
  );
}
