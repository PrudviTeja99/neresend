import 'size_formatter.dart';

/// Rolling window speed and ETA calculator for active transfers
class SpeedCalculator {
  final int windowDurationMs;
  final List<_DataSample> _samples = [];

  SpeedCalculator({this.windowDurationMs = 2000});

  void recordSample(int totalBytesTransferred) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _samples.add(_DataSample(now, totalBytesTransferred));
    _prune(now);
  }

  void _prune(int now) {
    _samples.removeWhere((s) => now - s.timestampMs > windowDurationMs);
  }

  /// Current transfer speed in bytes per second
  double calculateBytesPerSecond() {
    if (_samples.length < 2) return 0.0;
    final oldest = _samples.first;
    final newest = _samples.last;
    final timeDeltaSec = (newest.timestampMs - oldest.timestampMs) / 1000.0;
    if (timeDeltaSec <= 0) return 0.0;
    final bytesDelta = newest.bytes - oldest.bytes;
    return (bytesDelta / timeDeltaSec).clamp(0.0, double.infinity);
  }

  /// Formatted speed string e.g. "48.2 MB/s"
  String getFormattedSpeed() {
    final bytesPerSec = calculateBytesPerSecond();
    return formatSpeed(bytesPerSec);
  }

  static String formatSpeed(double bytesPerSecond) {
    return '${SizeFormatter.format(bytesPerSecond.toInt())}/s';
  }

  /// Estimated time remaining given total expected bytes
  Duration calculateEta(int currentBytes, int totalBytes) {
    final bytesPerSec = calculateBytesPerSecond();
    if (bytesPerSec <= 0 || currentBytes >= totalBytes) {
      return Duration.zero;
    }
    final remainingBytes = totalBytes - currentBytes;
    final remainingSeconds = (remainingBytes / bytesPerSec).ceil();
    return Duration(seconds: remainingSeconds);
  }

  /// Formatted ETA string e.g. "ETA: 14s" or "ETA: 2m 10s"
  String getFormattedEta(int currentBytes, int totalBytes) {
    final eta = calculateEta(currentBytes, totalBytes);
    return formatEta(eta);
  }

  static String formatEta(Duration eta) {
    if (eta == Duration.zero) return '';
    if (eta.inHours > 0) {
      return 'ETA: ${eta.inHours}h ${eta.inMinutes.remainder(60)}m';
    }
    if (eta.inMinutes > 0) {
      return 'ETA: ${eta.inMinutes}m ${eta.inSeconds.remainder(60)}s';
    }
    return 'ETA: ${eta.inSeconds}s';
  }

  void reset() {
    _samples.clear();
  }
}

class _DataSample {
  final int timestampMs;
  final int bytes;
  _DataSample(this.timestampMs, this.bytes);
}
