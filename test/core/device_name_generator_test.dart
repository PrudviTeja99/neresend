import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:neresend/core/utils/device_name_generator.dart';

void main() {
  group('DeviceNameGenerator Tests', () {
    test('generateRandomName returns a non-empty two-word string', () {
      final name = DeviceNameGenerator.generateRandomName();
      expect(name.isNotEmpty, isTrue);
      final parts = name.split(' ');
      expect(parts.length, 2);
      expect(DeviceNameGenerator.adjectives.contains(parts[0]), isTrue);
      expect(DeviceNameGenerator.nouns.contains(parts[1]), isTrue);
    });

    test('generateRandomName produces deterministic output with seeded Random',
        () {
      final rng1 = Random(42);
      final rng2 = Random(42);

      final name1 = DeviceNameGenerator.generateRandomName(random: rng1);
      final name2 = DeviceNameGenerator.generateRandomName(random: rng2);

      expect(name1, equals(name2));
    });

    test('adjectives and nouns lists have sufficient variety', () {
      expect(DeviceNameGenerator.adjectives.length, greaterThanOrEqualTo(20));
      expect(DeviceNameGenerator.nouns.length, greaterThanOrEqualTo(20));
    });
  });
}
