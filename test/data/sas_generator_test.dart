import 'package:flutter_test/flutter_test.dart';
import 'package:neresend/data/transports/webrtc/sas_generator.dart';

void main() {
  group('SasGenerator Tests', () {
    const localFp = 'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99';
    const remoteFp = '11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00';
    const pin = '749312';

    test('Generates identical 3-emoji string regardless of peer perspective',
        () {
      final hostEmojis = SasGenerator.formatEmojis(
        localFingerprint: localFp,
        remoteFingerprint: remoteFp,
        sessionPin: pin,
      );

      final clientEmojis = SasGenerator.formatEmojis(
        localFingerprint: remoteFp,
        remoteFingerprint: localFp,
        sessionPin: pin,
      );

      expect(hostEmojis, isNotEmpty);
      expect(hostEmojis, equals(clientEmojis));
      expect(hostEmojis.split(' ').length, 3);
    });

    test('Generates distinct emojis for different session PINs', () {
      final emojis1 = SasGenerator.formatEmojis(
        localFingerprint: localFp,
        remoteFingerprint: remoteFp,
        sessionPin: '111111',
      );

      final emojis2 = SasGenerator.formatEmojis(
        localFingerprint: localFp,
        remoteFingerprint: remoteFp,
        sessionPin: '222222',
      );

      expect(emojis1, isNot(equals(emojis2)));
    });

    test('Case insensitivity in fingerprints produces identical SAS', () {
      final emojisUpper = SasGenerator.formatEmojis(
        localFingerprint: localFp.toUpperCase(),
        remoteFingerprint: remoteFp.toUpperCase(),
        sessionPin: pin,
      );

      final emojisLower = SasGenerator.formatEmojis(
        localFingerprint: localFp.toLowerCase(),
        remoteFingerprint: remoteFp.toLowerCase(),
        sessionPin: pin,
      );

      expect(emojisUpper, equals(emojisLower));
    });
  });
}
