import 'package:flutter_test/flutter_test.dart';
import 'package:dropflow/data/discovery/remote_discovery_driver.dart';
import 'package:dropflow/data/transports/webrtc/signaling_client.dart';
import 'package:dropflow/domain/models/device_identity.dart';
import 'package:dropflow/domain/models/transfer_mode.dart';

void main() {
  late SignalingClient signalingClient;
  late RemoteDiscoveryDriver hostDriver;
  late RemoteDiscoveryDriver clientDriver;

  final hostIdentity = DeviceIdentity(
    deviceId: 'host-id-1',
    alias: 'Host Alpha',
    publicKeyBase64: 'host-key',
    fingerprint: '11:11:11:11:11:11',
    publicKeyBytes: List.filled(32, 1),
  );

  final clientIdentity = DeviceIdentity(
    deviceId: 'client-id-2',
    alias: 'Client Beta',
    publicKeyBase64: 'client-key',
    fingerprint: '22:22:22:22:22:22',
    publicKeyBytes: List.filled(32, 2),
  );

  setUp(() {
    signalingClient = SignalingClient();
    hostDriver = RemoteDiscoveryDriver(
      localIdentity: hostIdentity,
      signalingClient: signalingClient,
    );
    clientDriver = RemoteDiscoveryDriver(
      localIdentity: clientIdentity,
      signalingClient: signalingClient,
    );
  });

  tearDown(() async {
    await hostDriver.dispose();
    await clientDriver.dispose();
  });

  group('RemoteDiscoveryDriver Tests', () {
    test('Host creates PIN session and client pairs successfully', () async {
      await hostDriver.startDiscovery();
      await clientDriver.startDiscovery();

      final pin = await hostDriver.createHostSession(sdpOffer: 'v=0\r\no=host');
      expect(hostDriver.activeHostPin, pin);

      final pairResult = await clientDriver.pairWithPin(
        pin: pin,
        sdpAnswer: 'v=0\r\no=client',
      );

      expect(pairResult.sdpOffer, 'v=0\r\no=host');
      expect(pairResult.hostPeer.fingerprint, hostIdentity.fingerprint);
      expect(pairResult.hostPeer.supportedMode, TransferMode.remote);
      expect(clientDriver.currentPeers.length, 1);
      expect(clientDriver.currentPeers.first.alias, 'Host Alpha');

      final clientAnswer = await hostDriver.awaitClientAnswer(pin: pin);
      expect(clientAnswer, 'v=0\r\no=client');
    });

    test('Stopping discovery clears active host PIN and peer lists', () async {
      await hostDriver.startDiscovery();
      await hostDriver.createHostSession(sdpOffer: 'v=0');
      expect(hostDriver.activeHostPin, isNotNull);

      await hostDriver.stopDiscovery();
      expect(hostDriver.activeHostPin, isNull);
      expect(hostDriver.currentPeers, isEmpty);
    });
  });
}
