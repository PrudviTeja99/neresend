import 'dart:math';

/// Utility class to generate memorable, friendly LocalSend-style device names
class DeviceNameGenerator {
  static const List<String> adjectives = [
    'Cosmic',
    'Swift',
    'Brave',
    'Emerald',
    'Golden',
    'Radiant',
    'Vibrant',
    'Neon',
    'Clever',
    'Sunny',
    'Silent',
    'Mighty',
    'Lucky',
    'Happy',
    'Noble',
    'Wild',
    'Mystic',
    'Zen',
    'Hyper',
    'Cool',
    'Electric',
    'Lunar',
    'Solar',
    'Crimson',
    'Amber',
    'Velvet',
    'Frosty',
    'Gentle',
    'Quiet',
    'Bright',
  ];

  static const List<String> nouns = [
    'Apple',
    'Mango',
    'Peach',
    'Fox',
    'Falcon',
    'Dolphin',
    'Tiger',
    'Owl',
    'Panda',
    'Otter',
    'Cedar',
    'Comet',
    'Phoenix',
    'Sparrow',
    'Raven',
    'Berry',
    'Cherry',
    'Breeze',
    'River',
    'Summit',
    'Koala',
    'Badger',
    'Dragon',
    'Star',
    'Echo',
    'Wave',
    'Pineapple',
    'Melon',
    'Horizon',
    'Aurora',
  ];

  static final Random _random = Random();

  /// Generates a random, memorable name such as "Cosmic Dolphin" or "Golden Mango"
  static String generateRandomName({Random? random}) {
    final rng = random ?? _random;
    final adj = adjectives[rng.nextInt(adjectives.length)];
    final noun = nouns[rng.nextInt(nouns.length)];
    return '$adj $noun';
  }
}
