import 'package:app/pimic_bridge/identity/local_identity_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('cancel leaves original sync mode untouched', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalIdentityEntry(
            activate: () async {
              calls++;
            },
            onReady: () {
              calls++;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    expect(find.textContaining('重新配对 Pi'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(calls, 0);
  });
  testWidgets('explicit confirmation saves before original recheck', (
    tester,
  ) async {
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalIdentityEntry(
            activate: () async {
              calls.add('saved');
            },
            onReady: () {
              calls.add('boot');
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用本地身份'));
    await tester.pumpAndSettle();
    expect(calls, ['saved', 'boot']);
  });
  testWidgets('storage errors remain visible and do not boot', (tester) async {
    var booted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalIdentityEntry(
            activate: () async => throw StateError('secret error details'),
            onReady: () {
              booted = true;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用本地身份'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已有数据保持不变'), findsOneWidget);
    expect(find.textContaining('secret error details'), findsNothing);
    expect(booted, false);
  });
}
