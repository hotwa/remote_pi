import 'package:app/config/dependencies.dart';
import 'package:app/pairing/owner_identity_bridge.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/ui/sync_required/sync_required_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:remote_pi_identity/remote_pi_identity.dart';

void main() {
  for (final available in [false, true]) {
    testWidgets('recheck reloads cached router verdict only when identity is ready: $available', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = InMemoryOwnerIdentityStore(syncAvailable: available);
      final bridge = OwnerIdentityBridge(store, PairingStorage());
      injector.addInstance<OwnerIdentityBridge>(bridge);
      injector.commit();
      addTearDown(() async { bridge.dispose(); disposeDependencies(); await store.dispose(); });
      var reloads = 0;
      var gate = true;
      final router = GoRouter(initialLocation: '/sync-required',
        redirect: (ctx, state) => gate && state.uri.path != '/sync-required' ? '/sync-required' : null,
        routes: [
          GoRoute(path: '/sync-required', builder: (ctx, state) => SyncRequiredPage(reloadBoot: () async {
            reloads++; gate = false;
          })),
          GoRoute(path: '/boot', builder: (ctx, state) => const Scaffold(body: Text('READY'))),
        ],
      );
      addTearDown(router.dispose);
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check again')); await tester.pumpAndSettle();
      expect(reloads, available ? 1 : 0);
      expect(find.text('READY'), available ? findsOneWidget : findsNothing);
    });
  }
}
