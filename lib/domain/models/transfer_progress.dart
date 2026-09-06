import 'chunk_range.dart';

enum TransferStatus {
  idle,
  connecting,
  negotiating,
  transferring,
  verifying,
  paused,
  completed,
  cancelled,
  failed,
}

/// Real-time progress snapshot of an active transfer session
class TransferProgress {
  final String transferId;
  final String currentFileName;
  final int currentFileIndex;
  final int totalFiles;
  final List<ChunkRange> verifiedRanges;
  final int currentChunkIndex;
  final int totalChunks;
  final int bytesTransferred;
  final int totalBytes;
  final double speedBytesPerSecond;
  final Duration estimatedTimeRemaining;
  final TransferStatus status;
  final String? errorMessage;

  const TransferProgress({
    required this.transferId,
    required this.currentFileName,
    required this.currentFileIndex,
    required this.totalFiles,
    required this.verifiedRanges,
    required this.currentChunkIndex,
    required this.totalChunks,
    required this.bytesTransferred,
    required this.totalBytes,
    required this.speedBytesPerSecond,
    required this.estimatedTimeRemaining,
    required this.status,
    this.errorMessage,
  });

  double get progressFraction {
    if (totalBytes <= 0) return 0.0;
    return (bytesTransferred / totalBytes).clamp(0.0, 1.0);
  }

  int get progressPercent => (progressFraction * 100).toInt();

  bool get isActive =>
      status == TransferStatus.transferring ||
      status == TransferStatus.verifying ||
      status == TransferStatus.connecting;

  bool get isPaused => status == TransferStatus.paused;
  bool get isCompleted => status == TransferStatus.completed;
  bool get isTerminated =>
      status == TransferStatus.completed ||
      status == TransferStatus.cancelled ||
      status == TransferStatus.failed;
}

