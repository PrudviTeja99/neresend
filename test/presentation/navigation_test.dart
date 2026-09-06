import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neresend/presentation/screens/main_scaffold_screen.dart';
import 'package:neresend/presentation/state/identity_provider.dart';
import 'package:neresend/presentation/state/readiness_state_provider.dart';
import 'package:neresend/domain/models/device_identity.dart';

void main() {
  testWidgets(
      'MainScaffoldScreen renders 2 tabs and switches between Nearby and Remote',
      (tester) async {
    const mockIdentity = DeviceIdentity(
      deviceId: 'a1b2c3d4e5f60011',
      alias: 'Test Desktop',
      publicKeyBase64: 'mock_base64_pubkey',
      fingerprint: 'A1:B2:C3:D4:E5:F6',
      publicKeyBytes: [1, 2, 3],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          identityStateProvider
              .overrideWith((ref) => MockIdentityNotifier(mockIdentity)),
          readinessStateProvider.overrideWithValue(ReadinessState.ready),
        ],
        child: MaterialApp(
          home: const MainScaffoldScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Initial state: Nearby tab is active
    expect(find.text('Nearby'), findsOneWidget);
    expect(find.text('Remote'), findsOneWidget);
    expect(find.text('Ready to receive'), findsOneWidget);
    expect(find.text('Test Desktop'), findsOneWidget);

    // Switch to Remote tab
    await tester.tap(find.text('Remote'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Receive Remotely'), findsOneWidget);
    expect(find.text('Send to Remote Peer'), findsOneWidget);
  });
}

class MockIdentityNotifier extends StateNotifier<AsyncValue<DeviceIdentity>>
    implements IdentityNotifier {
  MockIdentityNotifier(DeviceIdentity identity)
      : super(AsyncValue.data(identity));

  @override
  Future<void> loadIdentity() async {}

  @override
  Future<void> updateAlias(String newAlias) async {}
}
