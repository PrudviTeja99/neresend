import 'dart:math' as math;

/// Utility for converting raw byte counts into human-readable strings
class SizeFormatter {
  SizeFormatter._();

  static const List<String> _suffixes = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];

  static String format(int bytes) {
    if (bytes <= 0) return '0 B';
    final i = (math.log(bytes) / math.log(1024)).floor();
    final unitIndex = math.min(i, _suffixes.length - 1);
    final value = bytes / math.pow(1024, unitIndex);
    return '${value.toStringAsFixed(unitIndex == 0 ? 0 : 1)} ${_suffixes[unitIndex]}';
  }
}

