import 'package:flutter_test/flutter_test.dart';
import 'package:dropflow/core/errors/exceptions.dart';
import 'package:dropflow/data/transports/webrtc/signaling_client.dart';
import 'package:dropflow/domain/models/device_identity.dart';

void main() {
  late SignalingClient signalingClient;

  final hostIdentity = DeviceIdentity(
    deviceId: 'host-123',
    alias: 'Host Device',
    publicKeyBase64: 'host-pubkey',
    fingerprint: 'AA:BB:CC:DD:EE:FF',
    publicKeyBytes: List.filled(32, 3),
  );

  final clientIdentity = DeviceIdentity(
    deviceId: 'client-456',
    alias: 'Client Device',
    publicKeyBase64: 'client-pubkey',
    fingerprint: '11:22:33:44:55:66',
    publicKeyBytes: List.filled(32, 4),
  );

  setUp(() {
    signalingClient = SignalingClient();
  });

  tearDown(() {
    signalingClient.dispose();
  });

  group('SignalingClient Tests', () {
    test('Host creates session and receives 6-digit formatted PIN', () async {
      final pin = await signalingClient.createSession(
        hostIdentity: hostIdentity,
        sdpOffer: 'v=0\r\no=host ...',
      );

      expect(pin, matches(r'^\d{3} \d{3}$'));
      final normalized = SignalingClient.normalizePin(pin);
      expect(normalized.length, 6);
    });

    test('Client joins session with PIN and completes SDP exchange', () async {
      final pin = await signalingClient.createSession(
        hostIdentity: hostIdentity,
        sdpOffer: 'v=0\r\no=host offer sdp',
      );

      final joinFuture = signalingClient.joinSession(
        pin: pin,
        clientIdentity: clientIdentity,
      );

      final sessionData = await joinFuture;
      expect(sessionData.sdpOffer, 'v=0\r\no=host offer sdp');
      expect(sessionData.hostIdentity.fingerprint, hostIdentity.fingerprint);

      // Client submits answer
      await signalingClient.submitAnswer(
        pin: pin,
        sdpAnswer: 'v=0\r\no=client answer sdp',
      );

      // Host receives answer
      final receivedAnswer = await signalingClient.awaitAnswer(
        pin: pin,
        timeout: const Duration(seconds: 2),
      );
      expect(receivedAnswer, 'v=0\r\no=client answer sdp');
    });

    test('Invalid PIN throws PIN_EXPIRED exception', () async {
      expect(
        () => signalingClient.joinSession(
          pin: '999 999',
          clientIdentity: clientIdentity,
        ),
        throwsA(isA<NetworkException>().having((e) => e.code, 'code', 'PIN_EXPIRED')),
      );
    });

    test('3-Strike rate limiting destroys session on 3rd failed attempt', () async {
      final pin = await signalingClient.createSession(
        hostIdentity: hostIdentity,
        sdpOffer: 'v=0\r\no=host offer',
      );

      // Strike 1
      signalingClient.recordFailedAttempt(pin);
      // Strike 2
      signalingClient.recordFailedAttempt(pin);
      // Strike 3 (locks and destroys session)
      signalingClient.recordFailedAttempt(pin);

      expect(
        () => signalingClient.joinSession(
          pin: pin,
          clientIdentity: clientIdentity,
        ),
        throwsA(isA<NetworkException>().having((e) => e.code, 'code', 'PIN_EXPIRED')),
      );
    });
  });
}
