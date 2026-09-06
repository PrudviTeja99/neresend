import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Generates a deterministic 3-emoji Short Authentication String (SAS) from DTLS public keys and session PIN
class SasGenerator {
  SasGenerator._();

  static const List<String> emojiTable = [
    '🌟', '🚀', '🎸', '🍕', '🐱', '🔥', '💎', '🌈',
    '🎨', '⚡', '🍉', '🎈', '🛸', '🦁', '🍀', '🏆',
    '🍎', '🎯', '🚲', '🌊', '🍩', '🐼', '🔑', '🌺',
    '🍒', '🎲', '✈️', '☀️', '🍦', '🦊', '🔔', '🌴',
    '🍇', '🎳', '⛵', '🌙', '🍔', '🐯', '💡', '🌻',
    '🍓', '🎮', '🚗', '⭐', '🍰', '🐶', '🎵', '🌵',
    '🍊', '🎪', '🪐', '🍫', '🐵', '🎧', '🍁', '🥑',
    '🍋', '🎭', '🚁', '🌌', '🍿', '🐰', '🎺', '🍂',
  ];

  /// Generate 3 visual emojis that match on both peer screens for out-of-band visual verification
  static List<String> generate({
    required String localFingerprint,
    required String remoteFingerprint,
    required String sessionPin,
  }) {
    // Sort fingerprints canonically to ensure symmetry
    final sorted = [localFingerprint.toUpperCase(), remoteFingerprint.toUpperCase()]..sort();
    final combined = '${sorted[0]}|${sorted[1]}|$sessionPin';
    final digest = sha256.convert(utf8.encode(combined)).bytes;

    final idx1 = digest[0] % emojiTable.length;
    final idx2 = digest[1] % emojiTable.length;
    final idx3 = digest[2] % emojiTable.length;

    return [emojiTable[idx1], emojiTable[idx2], emojiTable[idx3]];
  }

  /// Formatted emoji string e.g. "🌟 🚀 🎸"
  static String formatEmojis({
    required String localFingerprint,
    required String remoteFingerprint,
    required String sessionPin,
  }) {
    final emojis = generate(
      localFingerprint: localFingerprint,
      remoteFingerprint: remoteFingerprint,
      sessionPin: sessionPin,
    );
    return emojis.join(' ');
  }
}
