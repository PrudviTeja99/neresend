import 'package:flutter_test/flutter_test.dart';
import 'package:neresend/core/utils/speed_calculator.dart';

void main() {
  group('SpeedCalculator (3-Second Rolling Window)', () {
    late SpeedCalculator calculator;

    setUp(() {
      calculator = SpeedCalculator(windowDurationMs: 3000);
    });

    test('Initial state returns 0.0 bytes/s and 0 B/s string', () {
      expect(calculator.calculateBytesPerSecond(), equals(0.0));
      expect(calculator.getFormattedSpeed(), equals('0 B/s'));
      expect(calculator.calculateEta(0, 1000000), equals(Duration.zero));
      expect(calculator.getFormattedEta(0, 1000000), equals(''));
    });

    test('Single sample returns 0.0 bytes/s', () {
      calculator.recordSample(1024 * 1024, timestampMs: 1000);
      expect(calculator.calculateBytesPerSecond(nowMs: 1000), equals(0.0));
    });

    test('Calculates constant rate accurately over 3 seconds', () {
      // 5 MB/s transfer: 5 MB at t=0, 10 MB at t=1000, 15 MB at t=2000, 20 MB at t=3000
      const bytesPerSec = 5 * 1024 * 1024; // 5 MB/s

      calculator.recordSample(0, timestampMs: 1000);
      calculator.recordSample(bytesPerSec, timestampMs: 2000);
      calculator.recordSample(bytesPerSec * 2, timestampMs: 3000);
      calculator.recordSample(bytesPerSec * 3, timestampMs: 4000);

      final calculatedSpeed = calculator.calculateBytesPerSecond(nowMs: 4000);
      // Expected speed = (15 MB - 0 MB) / 3s = 5 MB/s
      expect(calculatedSpeed, closeTo(bytesPerSec.toDouble(), 1.0));
      expect(calculator.getFormattedSpeed(nowMs: 4000), equals('5.0 MB/s'));
    });

    test('Sliding window prunes samples older than 3000ms while keeping anchor',
        () {
      const rate = 10 * 1024 * 1024; // 10 MB/s

      // Record samples at t = 0, 1000, 2000, 3000, 4000, 5000
      for (int i = 0; i <= 5; i++) {
        calculator.recordSample(i * rate, timestampMs: i * 1000);
      }

      // At t = 5000, cutoff is 2000. Samples before 2000 are pruned except anchor at 2000.
      final speedAt5s = calculator.calculateBytesPerSecond(nowMs: 5000);
      expect(speedAt5s, closeTo(rate.toDouble(), 1.0));
    });

    test(
        'Decays speed to 0.0 when transfer is stalled/idle past window duration',
        () {
      calculator.recordSample(0, timestampMs: 1000);
      calculator.recordSample(10 * 1024 * 1024, timestampMs: 2000);

      // Querying at t = 2500 (active): speed is 10 MB/s
      expect(calculator.calculateBytesPerSecond(nowMs: 2500),
          closeTo(10 * 1024 * 1024, 1.0));

      // Querying at t = 6000 (4 seconds after last sample): should decay to 0
      expect(calculator.calculateBytesPerSecond(nowMs: 6000), equals(0.0));
      expect(calculator.getFormattedSpeed(nowMs: 6000), equals('0 B/s'));
    });

    test('Calculates ETA accurately based on rolling speed', () {
      const totalBytes = 20 * 1024 * 1024; // 20 MB total

      calculator.recordSample(0, timestampMs: 1000);
      calculator.recordSample(4 * 1024 * 1024,
          timestampMs: 3000); // 4 MB transferred in 2s = 2 MB/s

      // Remaining bytes: 16 MB. At 2 MB/s, ETA = 8 seconds.
      final eta =
          calculator.calculateEta(4 * 1024 * 1024, totalBytes, nowMs: 3000);
      expect(eta.inSeconds, equals(8));
      expect(
          calculator.getFormattedEta(4 * 1024 * 1024, totalBytes, nowMs: 3000),
          equals('ETA: 8s'));
    });

    test('Returns Duration.zero for ETA when transfer is complete', () {
      const totalBytes = 50 * 1024 * 1024;
      calculator.recordSample(totalBytes, timestampMs: 1000);
      calculator.recordSample(totalBytes, timestampMs: 2000);

      expect(calculator.calculateEta(totalBytes, totalBytes, nowMs: 2000),
          equals(Duration.zero));
      expect(calculator.getFormattedEta(totalBytes, totalBytes, nowMs: 2000),
          equals(''));
    });

    test('ETA formatting handles seconds, minutes, and hours', () {
      expect(SpeedCalculator.formatEta(const Duration(seconds: 45)),
          equals('ETA: 45s'));
      expect(SpeedCalculator.formatEta(const Duration(minutes: 3, seconds: 12)),
          equals('ETA: 3m 12s'));
      expect(
          SpeedCalculator.formatEta(
              const Duration(hours: 1, minutes: 25, seconds: 5)),
          equals('ETA: 1h 25m'));
    });

    test('Reset clears all samples', () {
      calculator.recordSample(1024 * 1024, timestampMs: 1000);
      calculator.recordSample(2048 * 1024, timestampMs: 2000);
      expect(calculator.calculateBytesPerSecond(nowMs: 2000), greaterThan(0));

      calculator.reset();
      expect(calculator.calculateBytesPerSecond(nowMs: 2000), equals(0.0));
    });
  });
}
