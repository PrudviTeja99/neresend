import 'package:flutter_test/flutter_test.dart';
import 'package:dropflow/core/constants/protocol_constants.dart';
import 'package:dropflow/domain/integrity/dynamic_chunk_sizer.dart';

void main() {
  group('DynamicChunkSizer Tests', () {
    test('100 MB file selects 1 MB chunks locally', () {
      final size = DynamicChunkSizer.calculateChunkSize(
        totalFileSizeBytes: 100 * 1024 * 1024,
        isRemote: false,
      );
      expect(size, equals(1024 * 1024)); // 1 MB
    });

    test('10 GB file selects 2 MB or 4 MB chunk size to respect manifest budget', () {
      final size = DynamicChunkSizer.calculateChunkSize(
        totalFileSizeBytes: 10 * 1024 * 1024 * 1024, // 10 GB
        isRemote: false,
      );
      expect(size, inInclusiveRange(2 * 1024 * 1024, 4 * 1024 * 1024));
    });

    test('100 GB file selects 8 MB chunk size locally', () {
      final size = DynamicChunkSizer.calculateChunkSize(
        totalFileSizeBytes: 100 * 1024 * 1024 * 1024, // 100 GB
        isRemote: false,
      );
      expect(size, equals(8 * 1024 * 1024)); // 8 MB
    });

    test('Remote transfers cap chunk size at 4 MB max', () {
      final size = DynamicChunkSizer.calculateChunkSize(
        totalFileSizeBytes: 500 * 1024 * 1024 * 1024, // 500 GB
        isRemote: true,
      );
      expect(size, equals(4 * 1024 * 1024)); // 4 MB
    });

    test('Multi-part segmentation flag is raised when exceeding manifest budget or 50 files', () {
      expect(
        DynamicChunkSizer.requiresMultiPartSegmentation(
          totalFiles: 10,
          estimatedManifestBytes: 100 * 1024,
        ),
        isFalse,
      );

      expect(
        DynamicChunkSizer.requiresMultiPartSegmentation(
          totalFiles: 1000,
          estimatedManifestBytes: 100 * 1024,
        ),
        isTrue,
      );

      expect(
        DynamicChunkSizer.requiresMultiPartSegmentation(
          totalFiles: 5,
          estimatedManifestBytes: ProtocolConstants.maxManifestBytes + 1,
        ),
        isTrue,
      );
    });
  });
}
