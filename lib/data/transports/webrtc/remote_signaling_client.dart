import 'dart:async';
import 'dart:math';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/exceptions.dart';
import '../../../domain/models/device_identity.dart';

/// Structured information representing an active remote signaling session
class RemoteSessionInfo {
  final String sessionId;
  final String authToken;
  final String pin;
  final String inviteUri;
  final DateTime createdAt;
  final Duration ttl;

  const RemoteSessionInfo({
    required this.sessionId,
    required this.authToken,
    required this.pin,
    required this.inviteUri,
    required this.createdAt,
    this.ttl = const Duration(minutes: 5),
  });

  bool get isExpired => DateTime.now().difference(createdAt) > ttl;
  int get secondsRemaining =>
      max(0, ttl.inSeconds - DateTime.now().difference(createdAt).inSeconds);

  static String buildInviteUri({
    required String sessionId,
    required String authToken,
    required String pin,
  }) {
    final cleanPin = pin.replaceAll(RegExp(r'\s+'), '');
    return 'neresend://pair?session=$sessionId&token=$authToken&pin=$cleanPin';
  }

  static ({String? sessionId, String? authToken, String pin}) parseInviteUri(
      String input) {
    final trimmed = input.trim();
    if (trimmed.startsWith('neresend://pair')) {
      final uri = Uri.tryParse(trimmed);
      if (uri != null) {
        final session = uri.queryParameters['session'];
        final token = uri.queryParameters['token'];
        final pin = uri.queryParameters['pin'] ?? '';
        return (sessionId: session, authToken: token, pin: pin);
      }
    }
    return (sessionId: null, authToken: null, pin: trimmed);
  }
}

/// Internal session record stored during local or broker-assisted matchmaking
class _SignalingRecord {
  final RemoteSessionInfo info;
  final DeviceIdentity hostIdentity;
  final String sdpOffer;
  int failedAttempts = 0;

  String? sdpAnswer;
  DeviceIdentity? clientIdentity;
  final Completer<String> answerCompleter = Completer<String>();
  final StreamController<String> iceCandidates =
      StreamController<String>.broadcast();

  _SignalingRecord({
    required this.info,
    required this.hostIdentity,
    required this.sdpOffer,
  });
}

/// Cloud signaling client for ephemeral WebRTC connection bootstrap (SDP & ICE swap)
class RemoteSignalingClient {
  final String? signalingServerUrl;
  final Map<String, _SignalingRecord> _localSessions = {};
  final Map<String, String> _pinToSessionId = {};
  Timer? _cleanupTimer;

  RemoteSignalingClient({this.signalingServerUrl}) {
    _cleanupTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _cleanupExpiredSessions(),
    );
  }

  /// Generate a random 128-bit hex session identifier
  static String generateSessionId() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  }

  /// Generate a random 64-bit hex authentication token
  static String generateAuthToken() {
    final rand = Random.secure();
    final bytes = List<int>.generate(8, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  }

  /// Generate a 6-digit formatted PIN ("550 573")
  static String generatePin() {
    final rand = Random.secure();
    final p1 = (rand.nextInt(900) + 100).toString();
    final p2 = (rand.nextInt(900) + 100).toString();
    return '$p1 $p2';
  }

  /// Normalize a PIN by stripping whitespace
  static String normalizePin(String pin) {
    return pin.replaceAll(RegExp(r'\s+'), '').trim();
  }

  /// Receiver creates a remote hosting session
  Future<RemoteSessionInfo> createSession({
    required DeviceIdentity hostIdentity,
    required String sdpOffer,
    String? preferredPin,
  }) async {
    final pin = preferredPin ?? generatePin();
    final normalizedPin = normalizePin(pin);
    final sessionId = generateSessionId();
    final authToken = generateAuthToken();
    final inviteUri = RemoteSessionInfo.buildInviteUri(
      sessionId: sessionId,
      authToken: authToken,
      pin: normalizedPin,
    );

    final info = RemoteSessionInfo(
      sessionId: sessionId,
      authToken: authToken,
      pin: pin,
      inviteUri: inviteUri,
      createdAt: DateTime.now(),
      ttl: const Duration(minutes: 5),
    );

    final record = _SignalingRecord(
      info: info,
      hostIdentity: hostIdentity,
      sdpOffer: sdpOffer,
    );

    _localSessions[sessionId] = record;
    _pinToSessionId[normalizedPin] = sessionId;

    return info;
  }

  /// Sender joins an active session using the 6-digit PIN or structured QR invite URI
  Future<
      ({
        String sdpOffer,
        DeviceIdentity hostIdentity,
        RemoteSessionInfo sessionInfo
      })> joinSession({
    required String pinOrUri,
    required DeviceIdentity clientIdentity,
  }) async {
    final parsed = RemoteSessionInfo.parseInviteUri(pinOrUri);
    final normalizedPin = normalizePin(parsed.pin);

    String? sessionId = parsed.sessionId;
    sessionId ??= _pinToSessionId[normalizedPin];

    if (sessionId == null || !_localSessions.containsKey(sessionId)) {
      throw const NetworkException(
        'Invalid or expired 6-digit PIN',
        code: 'PIN_EXPIRED',
      );
    }

    final record = _localSessions[sessionId]!;
    if (record.info.isExpired) {
      _localSessions.remove(sessionId);
      _pinToSessionId.remove(normalizedPin);
      throw const NetworkException(
        'Session has expired',
        code: 'PIN_EXPIRED',
      );
    }

    // 3-Strike rate limit guard
    if (record.failedAttempts >= AppConstants.maxPinFailedAttempts) {
      _localSessions.remove(sessionId);
      _pinToSessionId.remove(normalizedPin);
      throw const NetworkException(
        'Too many invalid PIN attempts; session destroyed for security.',
        code: 'PIN_LOCKED',
      );
    }

    record.clientIdentity = clientIdentity;

    return (
      sdpOffer: record.sdpOffer,
      hostIdentity: record.hostIdentity,
      sessionInfo: record.info,
    );
  }

  /// Client submits its SDP answer to the host
  Future<void> submitAnswer({
    required String sessionId,
    required String sdpAnswer,
  }) async {
    final record = _localSessions[sessionId];
    if (record == null || record.info.isExpired) {
      throw const NetworkException('Session not found or expired',
          code: 'PIN_EXPIRED');
    }

    record.sdpAnswer = sdpAnswer;
    if (!record.answerCompleter.isCompleted) {
      record.answerCompleter.complete(sdpAnswer);
    }
  }

  /// Host awaits the client's SDP answer
  Future<String> awaitAnswer({
    required String sessionId,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final record = _localSessions[sessionId];
    if (record == null || record.info.isExpired) {
      throw const NetworkException('Session not found or expired',
          code: 'PIN_EXPIRED');
    }

    return await record.answerCompleter.future.timeout(
      timeout,
      onTimeout: () {
        closeSession(sessionId);
        throw const NetworkException(
          'Waiting for remote peer connection timed out',
          code: 'PIN_TIMEOUT',
        );
      },
    );
  }

  /// Close and purge an active session immediately upon pairing or completion
  void closeSession(String sessionId) {
    final record = _localSessions.remove(sessionId);
    if (record != null) {
      final pin = normalizePin(record.info.pin);
      _pinToSessionId.remove(pin);
      if (!record.iceCandidates.isClosed) {
        record.iceCandidates.close();
      }
    }
  }

  void recordFailedAttempt(String pin) {
    final normalized = normalizePin(pin);
    final sessionId = _pinToSessionId[normalized];
    if (sessionId != null && _localSessions.containsKey(sessionId)) {
      final record = _localSessions[sessionId]!;
      record.failedAttempts++;
      if (record.failedAttempts >= AppConstants.maxPinFailedAttempts) {
        closeSession(sessionId);
      }
    }
  }

  void _cleanupExpiredSessions() {
    final expiredIds = <String>[];
    for (final entry in _localSessions.entries) {
      if (entry.value.info.isExpired) {
        expiredIds.add(entry.key);
      }
    }
    for (final id in expiredIds) {
      closeSession(id);
    }
  }

  void dispose() {
    _cleanupTimer?.cancel();
    _localSessions.clear();
    _pinToSessionId.clear();
  }
}
