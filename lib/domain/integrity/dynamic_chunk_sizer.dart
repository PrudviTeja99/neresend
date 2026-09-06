import '../../core/constants/app_constants.dart';
import '../../core/constants/protocol_constants.dart';

/// Invariant dynamic chunk sizing calculator that preserves the MAX_MANIFEST_SIZE budget
class DynamicChunkSizer {
  DynamicChunkSizer._();

  static const int minChunkSize = AppConstants.chunkSize1MB; // 1 MB
  static const int maxLocalChunkSize = AppConstants.chunkSize8MB; // 8 MB
  static const int maxRemoteChunkSize = AppConstants.chunkSize4MB; // 4 MB

  /// Calculates optimal chunk size for a single file or batch of files
  static int calculateChunkSize({
    required int totalFileSizeBytes,
    int metadataSizeBytes = 2048,
    required bool isRemote,
  }) {
    final candidateSizes = isRemote
        ? [AppConstants.chunkSize1MB, AppConstants.chunkSize2MB, AppConstants.chunkSize4MB]
        : [AppConstants.chunkSize1MB, AppConstants.chunkSize2MB, AppConstants.chunkSize4MB, AppConstants.chunkSize8MB];

    // Each chunk hash in JSON takes ~64 hex chars + quotes/commas ≈ 68 bytes
    const int estimatedBytesPerChunkJson = 68;

    for (final size in candidateSizes) {
      if (size <= 0) continue;
      final chunkCount = (totalFileSizeBytes / size).ceil();
      final estimatedHashBytes = chunkCount * estimatedBytesPerChunkJson;
      final totalEstimatedManifest = metadataSizeBytes + estimatedHashBytes;

      if (totalEstimatedManifest <= ProtocolConstants.maxManifestBytes) {
        return size;
      }
    }

    // Return largest supported chunk size if manifest budget is exceeded
    // (Multi-part manifest segmentation will be triggered if required)
    return candidateSizes.last;
  }

  /// Determines whether a manifest requires multi-part frame segmentation
  static bool requiresMultiPartSegmentation({
    required int totalFiles,
    required int estimatedManifestBytes,
  }) {
    return estimatedManifestBytes > ProtocolConstants.maxManifestBytes || totalFiles > 50;
  }
}
