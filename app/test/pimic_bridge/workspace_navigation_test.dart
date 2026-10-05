import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/pimic_bridge/pimic_host.dart';
import 'package:app/pimic_bridge/workspace_widgets.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/routing/adaptive.dart';
import 'package:app/ui/chat/widgets/input_bar.dart';
import 'package:app/ui/home/states/home_state.dart';
import 'package:app/ui/home/viewmodels/home_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pimic_addons/pimic_addons.dart';
import 'package:provider/provider.dart';

class _Store implements FlutterSecureStorage {
  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _peers = [
  PeerRecord(
    remoteEpk: 'AAAA',
    sessionName: 'Mac7',
    relayUrl: 'https://unused.invalid',
    pairedAt: '2026-10-04',
  ),
  PeerRecord(
    remoteEpk: 'BBBB',
    sessionName: 'Mac5',
    relayUrl: 'https://unused.invalid',
    pairedAt: '2026-10-04',
  ),
];
const _rooms = {
  'AAAA': [
    RoomInfo(
      roomId: 'main',
      startedAt: 0,
      name: 'Project A',
      cwd: '/projects/a',
    ),
  ],
  'BBBB': [
    RoomInfo(
      roomId: 'main',
      startedAt: 0,
      name: 'Project B',
      cwd: '/projects/b',
    ),
  ],
};

class _Peers extends PairingStorage {
  @override
  Future<List<PeerRecord>> listPeers() async => _peers;
  @override
  Future<void> savePeer(PeerRecord peer) async {}
}

class _Home extends HomeViewModel {
  _Home(this.peers, Preferences prefs, this.conn, this.onOpen)
    : super(peers, prefs, conn);
  final _Peers peers;
  final ConnectionManager conn;
  final VoidCallback onOpen;
  @override
  HomeState get state => const HomeList(peers: _peers, roomsByPeer: _rooms);
  @override
  bool get isRelayConnected => true;
  @override
  bool isRoomLive(String epk, String roomId) => true;
  @override
  bool isRoomWorking(String epk, String roomId) => false;
  @override
  Future<void> openSession(String epk, {String? roomId}) {
    onOpen();
    return super.openSession(epk, roomId: roomId);
  }

  @override
  void dispose() {
    super.dispose();
    conn.dispose();
    peers.dispose();
  }
}

void main() {
  for (final scenario in [
    'route',
    'disabled',
    'external selection',
    'identity reset',
  ]) {
    testWidgets('workspace modal: $scenario', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final host = PimicHost()
        ..acceptSaved(const AddonConfig(workspaceToolsEnabled: true));
      final prefs = Preferences(_Store());
      await prefs.setSelectedRoom(epk: 'AAAA', roomId: 'main');
      final selection = SessionSelection();
      var selections = 0;
      final sends = <String>[];
      final router = GoRouter(
        initialLocation: '/chat',
        initialExtra: const {'target': 'AAAA:main'},
        routes: [
          GoRoute(
            path: '/chat',
            builder: (context, state) {
              final target = (state.extra! as Map)['target'] as String;
              return Scaffold(
                body: Column(
                  children: [
                    Text(target, key: const Key('bound-target')),
                    PimicWorkspaceActions(
                      host: host,
                      target: target,
                      blockReason: () => null,
                      onActions: () {},
                      actionsReason: '',
                      createHome: () {
                        final peers = _Peers();
                        final conn = ConnectionManager(
                          storage: peers,
                          factory: (_, _) async =>
                              throw StateError('Unexpected network'),
                        );
                        return _Home(peers, prefs, conn, () => selections++);
                      },
                    ),
                    PimicWorkspaceComposer(
                      host: host,
                      target: target,
                      currentTarget: () => prefs.selectedRoomRaw,
                      builder: (key, draft, change, current) => InputBar(
                        draftTarget: key,
                        initialDraft: draft,
                        onDraftChanged: change,
                        disabled: !current,
                        onSend: sends.add,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: prefs),
            ChangeNotifierProvider.value(value: selection),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'A unsent');
      await tester.tap(find.byKey(const Key('pimic-workspace-switch')));
      await tester.pumpAndSettle();
      expect(find.byType(WorkspacePicker), findsOneWidget);
      if (scenario == 'route') {
        await tester.tap(
          find.byKey(
            ValueKey('workspace-${const WorkspaceKey('BBBB', 'main').id}'),
          ),
        );
        await tester.pumpAndSettle();
        expect(prefs.selectedRoomRaw, 'BBBB:main');
        expect(selection.matches('BBBB', 'main'), isTrue);
        expect(find.text('BBBB:main'), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );
        await tester.enterText(find.byType(TextField), 'B unsent');
        await tester.tap(find.byKey(const Key('pimic-workspace-switch')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            ValueKey('workspace-${const WorkspaceKey('AAAA', 'main').id}'),
          ),
        );
        await tester.pumpAndSettle();
        expect(prefs.selectedRoomRaw, 'AAAA:main');
        expect(find.text('AAAA:main'), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'A unsent',
        );
        expect(
          host.workspaceMemory.read(const WorkspaceKey('BBBB', 'main')).text,
          'B unsent',
        );
        expect(selections, 2);
      } else {
        if (scenario == 'disabled') {
          host.acceptSaved(const AddonConfig());
        } else if (scenario == 'external selection') {
          await prefs.setSelectedRoom(epk: 'CCCC', roomId: 'other');
        } else {
          host.clearWorkspaceCache();
        }
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        expect(find.byType(WorkspacePicker), findsNothing);
        expect(find.text('AAAA:main'), findsOneWidget);
        expect(selections, 0);
        expect(
          prefs.selectedRoomRaw,
          scenario == 'external selection' ? 'CCCC:other' : 'AAAA:main',
        );
      }
      expect(sends, isEmpty);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      host.dispose();
      prefs.dispose();
      selection.dispose();
    });
  }
}
