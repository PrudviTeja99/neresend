import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neresend/data/services/transfer_orchestrator.dart';
import 'package:neresend/domain/models/device_identity.dart';
import 'package:neresend/domain/models/discovered_peer.dart';
import 'package:neresend/domain/models/remote_session_info.dart';
import 'package:neresend/domain/models/transfer_progress.dart';
import 'package:neresend/data/services/identity_service.dart';
import 'package:neresend/domain/contracts/secure_storage_port.dart';
import 'package:neresend/presentation/screens/main_scaffold_screen.dart';
import 'package:neresend/presentation/screens/settings_modal.dart';
import 'package:neresend/presentation/state/identity_provider.dart';
import 'package:neresend/presentation/state/orchestrator_provider.dart';
import 'package:neresend/presentation/state/readiness_state_provider.dart';
import 'package:neresend/presentation/state/trusted_device_provider.dart';
import 'package:neresend/presentation/widgets/center_device_avatar.dart';
import 'package:neresend/presentation/widgets/edit_device_name_dialog.dart';

class FakeTestSecureStorage implements SecureStoragePort {
  final Map<String, String> _data = {};

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<Map<String, String>> readAll() async => Map.from(_data);

  @override
  Future<void> write(String key, String value) async => _data[key] = value;
}

class TestIdentityNotifier extends StateNotifier<AsyncValue<DeviceIdentity>>
    implements IdentityNotifier {
  DeviceIdentity _identity;

  TestIdentityNotifier(this._identity) : super(AsyncValue.data(_identity));

  @override
  Future<void> loadIdentity() async {}

  @override
  Future<void> updateAlias(String newAlias) async {
    _identity = _identity.copyWith(alias: newAlias);
    state = AsyncValue.data(_identity);
  }
}

class FakeTestOrchestrator implements TransferOrchestrator {
  final StreamController<TransferProgress> _progressController =
      StreamController<TransferProgress>.broadcast();
  final StreamController<List<DiscoveredPeer>> _peersController =
      StreamController<List<DiscoveredPeer>>.broadcast();
  final StreamController<IncomingTransferPrompt> _promptController =
      StreamController<IncomingTransferPrompt>.broadcast();

  @override
  Stream<TransferProgress> get onProgress => _progressController.stream;

  @override
  Stream<List<DiscoveredPeer>> get onPeersChanged => _peersController.stream;

  @override
  Stream<IncomingTransferPrompt> get onIncomingTransferPrompt =>
      _promptController.stream;

  @override
  List<DiscoveredPeer> get currentPeers => const [];

  @override
  bool get isReady => true;

  @override
  RemoteSessionInfo? get activeRemoteSession => null;

  @override
  Future<RemoteSessionInfo> startRemoteHostSession({
    String? preferredPin,
    bool forceNew = false,
  }) async {
    return RemoteSessionInfo(
      sessionId: 'test_sess',
      authToken: 'test_tok',
      pin: '550 573',
      inviteUri: 'neresend://pair?session=test_sess&pin=550573',
      createdAt: DateTime.now(),
      ttl: const Duration(minutes: 5),
    );
  }

  @override
  Future<void> disposeActiveRemoteHostSession() async {}

  @override
  void updateLocalIdentity(DeviceIdentity newIdentity) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const initialIdentity = DeviceIdentity(
    deviceId: 'a1b2c3d4e5f60011',
    alias: 'Swift Falcon',
    publicKeyBase64: 'mock_base64_pubkey',
    fingerprint: 'A1:B2:C3:D4:E5:F6',
    publicKeyBytes: [1, 2, 3],
  );

  group('Device Name Customization & Randomization Tests', () {
    testWidgets(
        'EditDeviceNameDialog displays alias and allows randomizing and saving',
        (tester) async {
      late TestIdentityNotifier notifier;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            identityStateProvider.overrideWith((ref) {
              notifier = TestIdentityNotifier(initialIdentity);
              return notifier;
            }),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: EditDeviceNameDialog(currentAlias: 'Swift Falcon'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Edit Device Name'), findsOneWidget);
      expect(find.text('Swift Falcon'), findsOneWidget);
      expect(find.text('🎲'), findsOneWidget);

      // Tap Randomize 🎲 button
      await tester.tap(find.text('🎲'));
      await tester.pumpAndSettle();

      // The text field should no longer say 'Swift Falcon'
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, isNot(equals('Swift Falcon')));
      expect(textField.controller?.text.isNotEmpty, isTrue);

      // Enter a specific custom name and save
      await tester.enterText(find.byType(TextField), 'Custom Laptop');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(notifier.state.value?.alias, 'Custom Laptop');
    });

    testWidgets(
        'NearbyTabScreen center avatar opens EditDeviceNameDialog on tap',
        (tester) async {
      final fakeOrchestrator = FakeTestOrchestrator();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            identityStateProvider
                .overrideWith((ref) => TestIdentityNotifier(initialIdentity)),
            readinessStateProvider.overrideWithValue(ReadinessState.ready),
            transferOrchestratorProvider
                .overrideWith((ref) => Future.value(fakeOrchestrator)),
          ],
          child: const MaterialApp(
            home: MainScaffoldScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(CenterDeviceAvatar), findsOneWidget);
      expect(find.text('Swift Falcon'), findsOneWidget);

      // Tap the avatar
      await tester.tap(find.byType(CenterDeviceAvatar));
      await tester.pump(const Duration(milliseconds: 300));

      // Verify EditDeviceNameDialog appeared
      expect(find.text('Edit Device Name'), findsOneWidget);
    });

    testWidgets('RemoteTabScreen displays YOUR DEVICE NAME and allows editing',
        (tester) async {
      final fakeOrchestrator = FakeTestOrchestrator();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            identityStateProvider
                .overrideWith((ref) => TestIdentityNotifier(initialIdentity)),
            readinessStateProvider.overrideWithValue(ReadinessState.ready),
            transferOrchestratorProvider
                .overrideWith((ref) => Future.value(fakeOrchestrator)),
          ],
          child: const MaterialApp(
            home: MainScaffoldScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Switch to Remote tab
      await tester.tap(find.text('Remote'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('YOUR DEVICE NAME'), findsOneWidget);
      expect(find.text('Swift Falcon'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);

      // Tap Edit
      await tester.tap(find.text('Edit'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Edit Device Name'), findsOneWidget);
    });

    testWidgets('SettingsModal supports alias editing with 🎲 Randomize button',
        (tester) async {
      final fakeStorage = FakeTestSecureStorage();
      final fakeIdentityService = IdentityService(secureStorage: fakeStorage);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            identityStateProvider
                .overrideWith((ref) => TestIdentityNotifier(initialIdentity)),
            trustedDeviceProvider.overrideWith(
                (ref) => TrustedDeviceNotifier(fakeIdentityService)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SettingsModal(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('DEVICE IDENTITY'), findsOneWidget);
      expect(find.text('Swift Falcon'), findsOneWidget);

      // Tap edit icon
      await tester.tap(find.byIcon(Icons.edit));
      await tester.pumpAndSettle();

      // Now 🎲 randomize and check icons should be visible
      expect(find.text('🎲'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);

      // Tap 🎲 Randomize
      await tester.tap(find.text('🎲'));
      await tester.pumpAndSettle();

      // Tap check (Save)
      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();
    });
  });
}
