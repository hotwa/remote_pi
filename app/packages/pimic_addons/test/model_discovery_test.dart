import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pimic_addons/api_client.dart';
import 'package:pimic_addons/config.dart';
import 'package:pimic_addons/model_discovery.dart';
import 'package:pimic_addons/settings_page.dart';
import 'config_test.dart' show MemoryStorage;

class CatalogApi extends AddonApiClient {
  final pending = <Completer<List<String>>>[];
  final cancellations = <AddonCancellation>[];
  @override
  Future<List<String>> listModels({
    required String baseUrl,
    String apiKey = '',
    AddonCancellation? cancellation,
  }) {
    cancellations.add(cancellation!);
    final result = Completer<List<String>>();
    pending.add(result);
    return result.future;
  }
}

void main() {
  late TextEditingController url, key, model;
  late CatalogApi api;
  setUp(() {
    url = TextEditingController(text: 'http://localhost:123/v1');
    key = TextEditingController();
    model = TextEditingController(text: 'manual');
    api = CatalogApi();
  });
  tearDown(() {
    url.dispose();
    key.dispose();
    model.dispose();
  });

  Widget page() => MaterialApp(
    home: Scaffold(
      body: ModelDiscovery(baseUrl: url, apiKey: key, model: model, api: api),
    ),
  );

  testWidgets(
    'lookup releases URL focus so choosing a model does not reopen keyboard',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextField(controller: url, focusNode: focus),
                ModelDiscovery(
                  baseUrl: url,
                  apiKey: key,
                  model: model,
                  api: api,
                ),
              ],
            ),
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasFocus, true);
      await tester.tap(find.text('Load models'));
      api.pending.single.complete(['chosen']);
      await tester.pumpAndSettle();
      expect(focus.hasFocus, false);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('chosen').last);
      await tester.pumpAndSettle();
      expect(model.text, 'chosen');
      expect(focus.hasFocus, false);
    },
  );

  testWidgets(
    'no automatic request; selection is explicit and manual model stays',
    (tester) async {
      await tester.pumpWidget(page());
      expect(api.pending, isEmpty);
      await tester.tap(find.text('Load models'));
      await tester.pump();
      api.pending.single.complete(['a', 'b']);
      await tester.pumpAndSettle();
      expect(model.text, 'manual');
      expect(find.textContaining('catalog only'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('b').last);
      await tester.pumpAndSettle();
      expect(model.text, 'b');
    },
  );

  testWidgets(
    'address change cancels and late result cannot replace new catalog',
    (tester) async {
      await tester.pumpWidget(page());
      await tester.tap(find.text('Load models'));
      url.text = 'http://other:456/v1';
      await tester.pump();
      expect(api.cancellations.first.isCancelled, true);
      await tester.tap(find.text('Load models'));
      api.pending.last.complete(['new']);
      await tester.pumpAndSettle();
      api.pending.first.complete(['old']);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      expect(find.text('new'), findsOneWidget);
      expect(find.text('old'), findsNothing);
      expect(model.text, 'manual');
    },
  );

  testWidgets('key change invalidates a previously loaded catalog', (
    tester,
  ) async {
    await tester.pumpWidget(page());
    await tester.tap(find.text('Load models'));
    api.pending.single.complete(['a']);
    await tester.pumpAndSettle();
    key.text = 'another-key';
    await tester.pump();
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(model.text, 'manual');
  });

  testWidgets('explicit cancel, background and disposal ignore late results', (
    tester,
  ) async {
    await tester.pumpWidget(page());
    await tester.tap(find.text('Load models'));
    await tester.pump();
    await tester.tap(find.text('Cancel lookup'));
    api.pending.first.complete(['cancelled-result']);
    await tester.pumpAndSettle();
    expect(api.cancellations.first.isCancelled, true);
    expect(find.textContaining('cancelled.'), findsOneWidget);
    await tester.tap(find.text('Load models'));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    api.pending[1].complete(['background-result']);
    await tester.pumpAndSettle();
    expect(api.cancellations[1].isCancelled, true);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.tap(find.text('Load models'));
    await tester.pumpWidget(const SizedBox());
    expect(api.cancellations.last.isCancelled, true);
    api.pending.last.complete(['disposed-result']);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('unsupported catalog is useful error and manual model survives', (
    tester,
  ) async {
    await tester.pumpWidget(page());
    await tester.tap(find.text('Load models'));
    api.pending.single.completeError(
      const AddonException('Service request failed (HTTP 404).'),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('enter the model manually'), findsOneWidget);
    expect(model.text, 'manual');
  });

  testWidgets('settings discovery neither enables flags nor saves config', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = MemoryStorage();
    await tester.pumpWidget(
      MaterialApp(
        home: AddonSettingsPage(
          store: AddonConfigStore(storage: storage),
          api: api,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(api.pending, isEmpty);
    final catalog = find.byKey(const Key('stt-model-discovery'));
    await tester.tap(
      find.descendant(of: catalog, matching: find.text('Load models')),
    );
    api.pending.single.complete(['stt-a']);
    await tester.pumpAndSettle();
    expect(storage.value, isNull);
    expect(
      tester
          .widgetList<SwitchListTile>(find.byType(SwitchListTile))
          .every((w) => !w.value),
      true,
    );
  });
}
