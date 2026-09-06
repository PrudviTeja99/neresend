import 'dart:async';
import 'dart:math';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/exceptions.dart';
import '../../../domain/models/device_identity.dart';

/// Active signaling session record storing SDP offers, answers, and ICE candidate streams
class SignalingSessionRecord {
  final String pin;
  final DeviceIdentity hostIdentity;
  final String sdpOffer;
  final DateTime createdAt;
  int failedAttempts = 0;

  String? sdpAnswer;
  DeviceIdentity? clientIdentity;

  final StreamController<String> hostIceCandidates = StreamController<String>.broadcast();
  final StreamController<String> clientIceCandidates = StreamController<String>.broadcast();
  final Completer<String> answerCompleter = Completer<String>();

  SignalingSessionRecord({
    required this.pin,
    required this.hostIdentity,
    required this.sdpOffer,
    required this.createdAt,
  });

  bool get isExpired => DateTime.now().difference(createdAt) > AppConstants.remotePinTtl;
}

/// Client managing 10-minute session PIN matching, 3-strike brute-force defense, and SDP/ICE swap
class SignalingClient {
  final Map<String, SignalingSessionRecord> _sessions = {};
  Timer? _cleanupTimer;

  SignalingClient() {
    _cleanupTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _cleanupExpiredSessions(),
    );
  }

  /// Formats a random 6-digit PIN string ("749 312")
  static String generatePin() {
    final rand = Random.secure();
    final p1 = (rand.nextInt(900) + 100).toString();
    final p2 = (rand.nextInt(900) + 100).toString();
    return '$p1 $p2';
  }

  /// Clean PIN string (strips spaces)
  static String normalizePin(String pin) {
    return pin.replaceAll(RegExp(r'\s+'), '').trim();
  }

  /// Host creates a new 10-minute session carrying its SDP offer
  Future<String> createSession({
    required DeviceIdentity hostIdentity,
    required String sdpOffer,
  }) async {
    final pin = generatePin();
    final normalized = normalizePin(pin);

    final record = SignalingSessionRecord(
      pin: normalized,
      hostIdentity: hostIdentity,
      sdpOffer: sdpOffer,
      createdAt: DateTime.now(),
    );

    _sessions[normalized] = record;
    return pin;
  }

  /// Client joins an active session using the 6-digit PIN
  Future<({String sdpOffer, DeviceIdentity hostIdentity})> joinSession({
    required String pin,
    required DeviceIdentity clientIdentity,
  }) async {
    final normalized = normalizePin(pin);
    final session = _sessions[normalized];

    if (session == null || session.isExpired) {
      if (session != null && session.isExpired) {
        _sessions.remove(normalized);
      }
      throw const NetworkException('Invalid or expired 6-digit PIN', code: 'PIN_EXPIRED');
    }

    // 3-Strike Rate Limiting Guard
    if (session.failedAttempts >= AppConstants.maxPinFailedAttempts) {
      _sessions.remove(normalized);
      throw const NetworkException(
        'Too many invalid PIN attempts; session destroyed for security.',
        code: 'PIN_LOCKED',
      );
    }

    session.clientIdentity = clientIdentity;
    return (sdpOffer: session.sdpOffer, hostIdentity: session.hostIdentity);
  }

  /// Client submits its SDP answer
  Future<void> submitAnswer({
    required String pin,
    required String sdpAnswer,
  }) async {
    final normalized = normalizePin(pin);
    final session = _sessions[normalized];

    if (session == null || session.isExpired) {
      throw const NetworkException('Session not found or expired', code: 'PIN_EXPIRED');
    }

    session.sdpAnswer = sdpAnswer;
    if (!session.answerCompleter.isCompleted) {
      session.answerCompleter.complete(sdpAnswer);
    }
  }

  /// Host awaits the client's SDP answer
  Future<String> awaitAnswer({
    required String pin,
    Duration timeout = const Duration(minutes: 10),
  }) async {
    final normalized = normalizePin(pin);
    final session = _sessions[normalized];

    if (session == null || session.isExpired) {
      throw const NetworkException('Session not found or expired', code: 'PIN_EXPIRED');
    }

    return await session.answerCompleter.future.timeout(
      timeout,
      onTimeout: () {
        _sessions.remove(normalized);
        throw const NetworkException('Waiting for peer PIN match timed out', code: 'PIN_TIMEOUT');
      },
    );
  }

  /// Record an invalid attempt against a session PIN
  void recordFailedAttempt(String pin) {
    final normalized = normalizePin(pin);
    final session = _sessions[normalized];
    if (session != null) {
      session.failedAttempts++;
      if (session.failedAttempts >= AppConstants.maxPinFailedAttempts) {
        _sessions.remove(normalized);
      }
    }
  }

  void _cleanupExpiredSessions() {
    _sessions.removeWhere((_, s) => s.isExpired);
  }

  void dispose() {
    _cleanupTimer?.cancel();
    _sessions.clear();
  }
}
