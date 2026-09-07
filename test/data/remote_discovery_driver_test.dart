import 'package:flutter_test/flutter_test.dart';
import 'package:neresend/data/discovery/remote_discovery_driver.dart';
import 'package:neresend/data/transports/webrtc/remote_signaling_client.dart';
import 'package:neresend/domain/models/device_identity.dart';
import 'package:neresend/domain/models/transfer_mode.dart';

void main() {
  late RemoteSignalingClient signalingClient;
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
    signalingClient = RemoteSignalingClient();
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
    test('Host creates PIN session and client pairs successfully via PIN', () async {
      await hostDriver.startDiscovery();
      await clientDriver.startDiscovery();

      final sessionInfo = await hostDriver.createHostSession(sdpOffer: 'v=0\r\no=host');
      expect(hostDriver.activeHostPin, sessionInfo.pin);
      expect(sessionInfo.sessionId.isNotEmpty, isTrue);

      final pairResult = await clientDriver.pairWithPin(
        pinOrUri: sessionInfo.pin,
        sdpAnswer: 'v=0\r\no=client',
      );

      expect(pairResult.sdpOffer, 'v=0\r\no=host');
      expect(pairResult.hostPeer.fingerprint, hostIdentity.fingerprint);
      expect(pairResult.hostPeer.supportedMode, TransferMode.remote);
      expect(clientDriver.currentPeers.length, 1);
      expect(clientDriver.currentPeers.first.alias, 'Host Alpha');

      final clientAnswer = await hostDriver.awaitClientAnswer(sessionId: sessionInfo.sessionId);
      expect(clientAnswer, 'v=0\r\no=client');
    });

    test('Client pairs successfully via QR URI', () async {
      await hostDriver.startDiscovery();
      await clientDriver.startDiscovery();

      final sessionInfo = await hostDriver.createHostSession(sdpOffer: 'v=0\r\no=host-qr');
      expect(sessionInfo.inviteUri, startsWith('neresend://pair?session='));

      final pairResult = await clientDriver.pairWithPin(
        pinOrUri: sessionInfo.inviteUri,
        sdpAnswer: 'v=0\r\no=client-qr',
      );

      expect(pairResult.sdpOffer, 'v=0\r\no=host-qr');
      expect(pairResult.sessionInfo.sessionId, sessionInfo.sessionId);

      final clientAnswer = await hostDriver.awaitClientAnswer(sessionId: sessionInfo.sessionId);
      expect(clientAnswer, 'v=0\r\no=client-qr');
    });

    test('Stopping discovery clears active host session and peer lists', () async {
      await hostDriver.startDiscovery();
      await hostDriver.createHostSession(sdpOffer: 'v=0');
      expect(hostDriver.activeHostPin, isNotNull);

      await hostDriver.stopDiscovery();
      expect(hostDriver.activeHostPin, isNull);
      expect(hostDriver.currentPeers, isEmpty);
    });
  });
}
