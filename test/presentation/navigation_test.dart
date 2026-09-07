import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neresend/presentation/screens/main_scaffold_screen.dart';
import 'package:neresend/presentation/state/identity_provider.dart';
import 'package:neresend/presentation/state/readiness_state_provider.dart';
import 'package:neresend/presentation/widgets/center_device_avatar.dart';
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
        child: const MaterialApp(
          home: MainScaffoldScreen(),
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

  testWidgets(
      'NearbyTabScreen centers avatar and docks action bar at bottom on desktop & mobile',
      (tester) async {
    const mockIdentity = DeviceIdentity(
      deviceId: 'a1b2c3d4e5f60011',
      alias: 'Test Desktop',
      publicKeyBase64: 'mock_base64_pubkey',
      fingerprint: 'A1:B2:C3:D4:E5:F6',
      publicKeyBytes: [1, 2, 3],
    );

    // Test Desktop Window Size (1280x800)
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          identityStateProvider
              .overrideWith((ref) => MockIdentityNotifier(mockIdentity)),
          readinessStateProvider.overrideWithValue(ReadinessState.ready),
        ],
        child: const MaterialApp(
          home: MainScaffoldScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify avatar is horizontally and vertically centered in viewport
    final avatarCenter = tester.getCenter(find.byType(CenterDeviceAvatar));
    expect(
        avatarCenter.dx, closeTo(640, 20.0)); // centered horizontally in 1280
    expect(avatarCenter.dy, closeTo(480, 50.0)); // centered in body (800 - ~112 appBar)

    // Verify bottom action button is docked near the bottom
    final buttonCenter = tester.getCenter(find.text('Select Peer to Send'));
    expect(buttonCenter.dx, closeTo(640, 20.0));
    expect(
        buttonCenter.dy, greaterThan(700.0)); // Near bottom of 800px viewport

    // Ensure button and avatar do NOT overlap
    final avatarBottom = tester.getBottomLeft(find.text('Ready to receive')).dy;
    final buttonTop = tester.getTopLeft(find.text('Select Peer to Send')).dy;
    expect(buttonTop, greaterThan(avatarBottom + 50.0));

    // Test Mobile Screen Size (400x800)
    tester.view.physicalSize = const Size(400, 800);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final mobileAvatarCenter = tester.getCenter(find.byType(CenterDeviceAvatar));
    expect(mobileAvatarCenter.dx,
        closeTo(200, 15.0)); // centered horizontally in 400
    expect(mobileAvatarCenter.dy,
        closeTo(480, 50.0)); // centered in body
    final mobileButtonCenter =
        tester.getCenter(find.text('Select Peer to Send'));
    expect(mobileButtonCenter.dx, closeTo(200, 15.0));
    expect(mobileButtonCenter.dy, greaterThan(700.0));
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
