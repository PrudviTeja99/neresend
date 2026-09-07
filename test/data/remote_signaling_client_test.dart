import 'package:flutter_test/flutter_test.dart';
import 'package:neresend/core/errors/exceptions.dart';
import 'package:neresend/data/transports/webrtc/remote_signaling_client.dart';
import 'package:neresend/domain/models/device_identity.dart';

void main() {
  late RemoteSignalingClient signalingClient;

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
    signalingClient = RemoteSignalingClient();
  });

  tearDown(() {
    signalingClient.dispose();
  });

  group('RemoteSignalingClient Tests', () {
    test('Host creates session and receives 6-digit PIN and structured invite URI', () async {
      final info = await signalingClient.createSession(
        hostIdentity: hostIdentity,
        sdpOffer: 'v=0\r\no=host ...',
      );

      expect(info.pin, matches(r'^\d{3} \d{3}$'));
      expect(info.sessionId.length, 32); // 128-bit hex = 32 chars
      expect(info.authToken.length, 16); // 64-bit hex = 16 chars
      expect(info.inviteUri, startsWith('neresend://pair?session='));
      expect(info.isExpired, isFalse);
      expect(info.secondsRemaining, greaterThan(0));

      final normalized = RemoteSignalingClient.normalizePin(info.pin);
      expect(normalized.length, 6);
    });

    test('RemoteSessionInfo parseInviteUri parses both URI and raw PIN correctly', () {
      const uri = 'neresend://pair?session=abcdef1234567890abcdef1234567890&token=1234567890abcdef&pin=550573';
      final parsedUri = RemoteSessionInfo.parseInviteUri(uri);
      expect(parsedUri.sessionId, 'abcdef1234567890abcdef1234567890');
      expect(parsedUri.authToken, '1234567890abcdef');
      expect(parsedUri.pin, '550573');

      final parsedPin = RemoteSessionInfo.parseInviteUri('550 573');
      expect(parsedPin.sessionId, isNull);
      expect(parsedPin.authToken, isNull);
      expect(parsedPin.pin, '550 573');
    });

    test('Client joins session with 6-digit PIN and completes SDP exchange', () async {
      final info = await signalingClient.createSession(
        hostIdentity: hostIdentity,
        sdpOffer: 'v=0\r\no=host offer sdp',
      );

      final joinResult = await signalingClient.joinSession(
        pinOrUri: info.pin,
        clientIdentity: clientIdentity,
      );

      expect(joinResult.sdpOffer, 'v=0\r\no=host offer sdp');
      expect(joinResult.hostIdentity.fingerprint, hostIdentity.fingerprint);
      expect(joinResult.sessionInfo.sessionId, info.sessionId);

      // Client submits answer
      await signalingClient.submitAnswer(
        sessionId: info.sessionId,
        sdpAnswer: 'v=0\r\no=client answer sdp',
      );

      // Host receives answer
      final receivedAnswer = await signalingClient.awaitAnswer(
        sessionId: info.sessionId,
        timeout: const Duration(seconds: 2),
      );
      expect(receivedAnswer, 'v=0\r\no=client answer sdp');
    });

    test('Client joins session with QR invite URI', () async {
      final info = await signalingClient.createSession(
        hostIdentity: hostIdentity,
        sdpOffer: 'v=0\r\no=host qr offer',
      );

      final joinResult = await signalingClient.joinSession(
        pinOrUri: info.inviteUri,
        clientIdentity: clientIdentity,
      );

      expect(joinResult.sdpOffer, 'v=0\r\no=host qr offer');
      expect(joinResult.sessionInfo.sessionId, info.sessionId);
    });

    test('Invalid PIN throws PIN_EXPIRED exception', () async {
      expect(
        () => signalingClient.joinSession(
          pinOrUri: '999 999',
          clientIdentity: clientIdentity,
        ),
        throwsA(isA<NetworkException>()
            .having((e) => e.code, 'code', 'PIN_EXPIRED')),
      );
    });

    test('3-Strike rate limiting destroys session on 3rd failed attempt', () async {
      final info = await signalingClient.createSession(
        hostIdentity: hostIdentity,
        sdpOffer: 'v=0\r\no=host offer',
      );

      // Strike 1
      signalingClient.recordFailedAttempt(info.pin);
      // Strike 2
      signalingClient.recordFailedAttempt(info.pin);
      // Strike 3 (locks and destroys session)
      signalingClient.recordFailedAttempt(info.pin);

      expect(
        () => signalingClient.joinSession(
          pinOrUri: info.pin,
          clientIdentity: clientIdentity,
        ),
        throwsA(isA<NetworkException>()
            .having((e) => e.code, 'code', 'PIN_EXPIRED')),
      );
    });
  });
}
