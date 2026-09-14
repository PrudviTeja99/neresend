import 'dart:math';

/// Structured information representing an active 5-minute remote session
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

  /// Generates a random human-friendly 6-digit PIN string formatted as "XXX XXX"
  static String generatePin() {
    final rand = Random.secure();
    final part1 = rand.nextInt(900) + 100;
    final part2 = rand.nextInt(900) + 100;
    return '$part1 $part2';
  }

  /// Normalizes a PIN string by stripping whitespace
  static String normalizePin(String pin) {
    return pin.replaceAll(RegExp(r'\s+'), '').trim();
  }

  /// Generates a 128-bit hex session ID
  static String generateSessionId() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Generates a 128-bit hex auth token
  static String generateAuthToken() {
    return generateSessionId();
  }

  static String buildInviteUri({
    required String sessionId,
    required String authToken,
    required String pin,
  }) {
    final cleanPin = normalizePin(pin);
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

