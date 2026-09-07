import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:neresend/domain/integrity/part_file_manager.dart';
import 'package:neresend/domain/models/chunk_range.dart';
import 'package:neresend/domain/models/transfer_item.dart';

void main() {
  group('PartFileManager & Sidecar Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('neresend_part_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('sanitizeFilename removes path traversal and reserved characters', () {
      expect(
        PartFileManager.sanitizeFilename('../../../etc/shadow'),
        equals('etc_shadow'),
      );
      expect(
        PartFileManager.sanitizeFilename('report:2026*final?.pdf'),
        equals('report_2026_final_.pdf'),
      );
      expect(
        PartFileManager.sanitizeFilename('..'),
        startsWith('download_'),
      );
      expect(
        PartFileManager.sanitizeFilename('normal_file.txt'),
        equals('normal_file.txt'),
      );
    });

    test(
        'Sparse chunk writes, sidecar metadata updates, and atomic finalization',
        () async {
      // Create test data: 3 chunks of 10 bytes = 30 bytes
      final chunk0 = Uint8List.fromList(List.generate(10, (i) => i));
      final chunk1 = Uint8List.fromList(List.generate(10, (i) => i + 10));
      final chunk2 = Uint8List.fromList(List.generate(10, (i) => i + 20));

      final allBytes = Uint8List.fromList([...chunk0, ...chunk1, ...chunk2]);
      final wholeFileHash = sha256.convert(allBytes).toString();
      final chunk0Hash = sha256.convert(chunk0).toString();
      final chunk1Hash = sha256.convert(chunk1).toString();
      final chunk2Hash = sha256.convert(chunk2).toString();

      final item = TransferItem(
        id: 'item_1',
        fileName: 'test_sparse.bin',
        size: 30,
        mimeType: 'application/octet-stream',
        wholeFileSha256: wholeFileHash,
        chunkSize: 10,
        totalChunks: 3,
        chunkHashes: [chunk0Hash, chunk1Hash, chunk2Hash],
      );

      // 1. Write chunk 0
      var ranges = await PartFileManager.writeVerifiedChunk(
        downloadDir: tempDir.path,
        item: item,
        chunkIndex: 0,
        chunkBytes: chunk0,
        currentVerifiedRanges: const [],
      );
      expect(ranges, equals([const ChunkRange(0, 0)]));

      // 2. Write chunk 2 (leaving hole at chunk 1)
      ranges = await PartFileManager.writeVerifiedChunk(
        downloadDir: tempDir.path,
        item: item,
        chunkIndex: 2,
        chunkBytes: chunk2,
        currentVerifiedRanges: ranges,
      );
      expect(ranges, equals([const ChunkRange(0, 0), const ChunkRange(2, 2)]));

      // 3. Verify sidecar persistence and reloading
      final reloadedRanges = await PartFileManager.loadVerifiedRanges(
        downloadDir: tempDir.path,
        item: item,
      );
      expect(reloadedRanges,
          equals([const ChunkRange(0, 0), const ChunkRange(2, 2)]));

      // 4. Fill hole: write chunk 1
      ranges = await PartFileManager.writeVerifiedChunk(
        downloadDir: tempDir.path,
        item: item,
        chunkIndex: 1,
        chunkBytes: chunk1,
        currentVerifiedRanges: reloadedRanges,
      );
      expect(ranges, equals([const ChunkRange(0, 2)]));

      // 5. Finalize file
      final finalFile = await PartFileManager.finalizeFile(
        downloadDir: tempDir.path,
        item: item,
      );

      expect(await finalFile.exists(), isTrue);
      expect(await finalFile.length(), equals(30));
      expect(await finalFile.readAsBytes(), equals(allBytes));

      // 6. Verify sidecar cleanup
      final partFile =
          File(PartFileManager.getPartPath(tempDir.path, 'test_sparse.bin'));
      final metaFile =
          File(PartFileManager.getMetaPath(tempDir.path, 'test_sparse.bin'));
      expect(await partFile.exists(), isFalse);
      expect(await metaFile.exists(), isFalse);
    });

    test(
        'Completely shuffled out-of-order chunk writes correctly assemble and verify whole file',
        () async {
      // 5 chunks of 20,000 bytes = 100,000 bytes total (100 KB)
      const chunkSize = 20000;
      const totalChunks = 5;
      const totalSize = chunkSize * totalChunks;

      final chunks = List.generate(totalChunks, (chunkIdx) {
        return Uint8List.fromList(
            List.generate(chunkSize, (i) => (chunkIdx * 37 + i) % 256));
      });

      final allBytesBuilder = BytesBuilder();
      for (final c in chunks) {
        allBytesBuilder.add(c);
      }
      final allBytes = allBytesBuilder.toBytes();
      final wholeFileHash = sha256.convert(allBytes).toString();
      final chunkHashes =
          chunks.map((c) => sha256.convert(c).toString()).toList();

      final item = TransferItem(
        id: 'item_shuffled_1',
        fileName: 'shuffled_test.dat',
        size: totalSize,
        mimeType: 'application/octet-stream',
        wholeFileSha256: wholeFileHash,
        chunkSize: chunkSize,
        totalChunks: totalChunks,
        chunkHashes: chunkHashes,
      );

      // Shuffled arrival order: 4 -> 1 -> 3 -> 0 -> 2
      final arrivalOrder = [4, 1, 3, 0, 2];
      var currentRanges = <ChunkRange>[];

      for (final chunkIdx in arrivalOrder) {
        currentRanges = await PartFileManager.writeVerifiedChunk(
          downloadDir: tempDir.path,
          item: item,
          chunkIndex: chunkIdx,
          chunkBytes: chunks[chunkIdx],
          currentVerifiedRanges: currentRanges,
        );
      }

      // Verify all chunks are merged to a contiguous range [0, 4]
      expect(currentRanges, equals([const ChunkRange(0, 4)]));

      // Finalize and verify cryptographic SHA-256 integrity
      final finalFile = await PartFileManager.finalizeFile(
        downloadDir: tempDir.path,
        item: item,
      );

      expect(await finalFile.exists(), isTrue);
      expect(await finalFile.length(), equals(totalSize));
      expect(await finalFile.readAsBytes(), equals(allBytes));
    });
  });
}
