import 'size_formatter.dart';

/// Rolling 3-second window speed and ETA calculator for active transfers.
///
/// Tracks timestamped byte progress over a sliding time window (default 3,000 ms)
/// to provide smooth, stable, and accurate real-time throughput metrics (MB/s)
/// without distorting speed during connection startup or brief latency spikes.
class SpeedCalculator {
  /// Duration of the sliding measurement window in milliseconds (default: 3000ms / 3 seconds).
  final int windowDurationMs;

  final List<_DataSample> _samples = [];

  SpeedCalculator({this.windowDurationMs = 3000});

  /// Record a byte progress snapshot at the current time (or an explicit [timestampMs]).
  void recordSample(int totalBytesTransferred, {int? timestampMs}) {
    final now = timestampMs ?? DateTime.now().millisecondsSinceEpoch;
    _samples.add(_DataSample(now, totalBytesTransferred));
    _prune(now);
  }

  /// Prune samples outside the sliding window while retaining the closest predecessor anchor.
  void _prune(int now) {
    if (_samples.length <= 2) return;
    final cutoff = now - windowDurationMs;

    // Find the last index where timestamp is <= cutoff
    int removeCount = 0;
    for (int i = 0; i < _samples.length - 1; i++) {
      if (_samples[i + 1].timestampMs <= cutoff) {
        removeCount++;
      } else {
        break;
      }
    }

    if (removeCount > 0) {
      _samples.removeRange(0, removeCount);
    }
  }

  /// Current transfer speed in bytes per second over the sliding window.
  double calculateBytesPerSecond({int? nowMs}) {
    if (_samples.length < 2) return 0.0;

    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final newest = _samples.last;

    // If no new samples received for more than the window duration, speed has dropped to 0
    if (now - newest.timestampMs > windowDurationMs) {
      return 0.0;
    }

    final oldest = _samples.first;
    final timeDeltaSec = (newest.timestampMs - oldest.timestampMs) / 1000.0;

    // Guard against microsecond intervals to prevent division-by-near-zero spikes
    if (timeDeltaSec < 0.05) return 0.0;

    final bytesDelta = newest.bytes - oldest.bytes;
    if (bytesDelta < 0) return 0.0;

    return (bytesDelta / timeDeltaSec).clamp(0.0, double.infinity);
  }

  /// Formatted speed string e.g. "48.2 MB/s"
  String getFormattedSpeed({int? nowMs}) {
    final bytesPerSec = calculateBytesPerSecond(nowMs: nowMs);
    return formatSpeed(bytesPerSec);
  }

  /// Format raw bytes per second into human-readable rate string (e.g. "24.5 MB/s")
  static String formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond <= 0) return '0 B/s';
    return '${SizeFormatter.format(bytesPerSecond.toInt())}/s';
  }

  /// Estimated time remaining given current progress and total expected bytes.
  Duration calculateEta(int currentBytes, int totalBytes, {int? nowMs}) {
    if (currentBytes >= totalBytes || totalBytes <= 0) {
      return Duration.zero;
    }

    final bytesPerSec = calculateBytesPerSecond(nowMs: nowMs);
    if (bytesPerSec <= 0) {
      return Duration.zero;
    }

    final remainingBytes = totalBytes - currentBytes;
    final remainingSeconds = (remainingBytes / bytesPerSec).ceil();

    // Cap ETA to 99 hours to avoid absurd numbers from tiny initial sample rates
    if (remainingSeconds > 356400) {
      return const Duration(hours: 99);
    }

    return Duration(seconds: remainingSeconds);
  }

  /// Formatted ETA string e.g. "ETA: 14s" or "ETA: 2m 10s"
  String getFormattedEta(int currentBytes, int totalBytes, {int? nowMs}) {
    final eta = calculateEta(currentBytes, totalBytes, nowMs: nowMs);
    return formatEta(eta);
  }

  /// Format Duration into concise ETA string
  static String formatEta(Duration eta) {
    if (eta == Duration.zero) return '';
    if (eta.inHours > 0) {
      final hours = eta.inHours;
      final minutes = eta.inMinutes.remainder(60);
      return 'ETA: ${hours}h ${minutes.toString().padLeft(2, '0')}m';
    }
    if (eta.inMinutes > 0) {
      final minutes = eta.inMinutes;
      final seconds = eta.inSeconds.remainder(60);
      return 'ETA: ${minutes}m ${seconds.toString().padLeft(2, '0')}s';
    }
    return 'ETA: ${eta.inSeconds}s';
  }

  /// Clear all stored samples and reset calculations
  void reset() {
    _samples.clear();
  }
}

class _DataSample {
  final int timestampMs;
  final int bytes;
  const _DataSample(this.timestampMs, this.bytes);
}
