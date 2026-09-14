import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:neresend/data/discovery/remote_discovery_driver.dart';
import 'package:neresend/domain/models/device_identity.dart';
import 'package:neresend/domain/models/discovered_peer.dart';
import 'package:neresend/domain/models/remote_session_info.dart';
import 'package:neresend/domain/models/transfer_mode.dart';

void main() {
  late RemoteDiscoveryDriver hostDriver;

  final hostIdentity = DeviceIdentity(
    deviceId: 'host-id-1',
    alias: 'Host Alpha',
    publicKeyBase64: base64Encode(List.filled(32, 1)),
    fingerprint: '11:11:11:11:11:11',
    publicKeyBytes: List.filled(32, 1),
  );

  setUp(() {
    hostDriver = RemoteDiscoveryDriver(
      localIdentity: hostIdentity,
    );
  });

  tearDown(() async {
    await hostDriver.dispose();
  });

  group('RemoteDiscoveryDriver Tests', () {
    test('Host sets active session and retrieves PIN and session info', () async {
      await hostDriver.startDiscovery();

      final sessionInfo = RemoteSessionInfo(
        sessionId: 'sess-123',
        authToken: 'token-abc',
        pin: '550 573',
        inviteUri: 'neresend://pair?session=sess-123&token=token-abc&pin=550573',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

      hostDriver.setActiveHostSession(sessionInfo);
      expect(hostDriver.activeHostPin, equals('550 573'));
      expect(hostDriver.activeHostSession?.sessionId, equals('sess-123'));
      expect(hostDriver.isDiscovering, isTrue);
    });

    test('Registers and removes discovered remote peers', () async {
      final peer = DiscoveredPeer(
        id: 'client-1',
        alias: 'Client Beta',
        deviceType: DeviceType.android,
        ipAddress: '0.0.0.0',
        port: 0,
        supportedMode: TransferMode.remote,
        identityPublicKey: base64Encode(List.filled(32, 2)),
        fingerprint: '22:22:22:22:22:22',
        lastSeen: DateTime.now(),
      );

      hostDriver.registerPeer(peer);
      expect(hostDriver.currentPeers.length, equals(1));
      expect(hostDriver.currentPeers.first.alias, equals('Client Beta'));

      hostDriver.removePeer(peer.fingerprint);
      expect(hostDriver.currentPeers, isEmpty);
    });

    test('Stopping discovery clears active host session and peer lists', () async {
      await hostDriver.startDiscovery();
      hostDriver.setActiveHostSession(
        RemoteSessionInfo(
          sessionId: 'sess-456',
          authToken: 'token-xyz',
          pin: '123 456',
          inviteUri: 'neresend://pair?session=sess-456&token=token-xyz&pin=123456',
          createdAt: DateTime.now(),
        ),
      );
      expect(hostDriver.activeHostPin, isNotNull);

      await hostDriver.stopDiscovery();
      expect(hostDriver.activeHostPin, isNull);
      expect(hostDriver.currentPeers, isEmpty);
      expect(hostDriver.isDiscovering, isFalse);
    });
  });
}
