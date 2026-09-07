import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

/// Single-pass streaming chunk and whole-file SHA-256 integrity hash calculator
class ChunkHasher {
  ChunkHasher._();

  /// Calculate SHA-256 hex digest for a single in-memory byte buffer
  static String hashChunk(List<int> chunkBytes) {
    return sha256.convert(chunkBytes).toString();
  }

  /// Verify that in-memory chunk bytes match expected SHA-256 hex digest
  static bool verifyChunk(List<int> chunkBytes, String expectedSha256) {
    final actual = hashChunk(chunkBytes);
    return actual.toLowerCase() == expectedSha256.toLowerCase();
  }

  /// Stream a file from disk in chunks of [chunkSize], computing both chunk hashes and whole-file hash in a single pass
  static Future<({
    String wholeFileSha256,
    List<String> chunkHashes,
    int totalChunks,
    int totalBytes,
  })> hashFile({
    required File file,
    required int chunkSize,
  }) async {
    if (!await file.exists()) {
      throw FileSystemException('File not found', file.path);
    }

    final fileSize = await file.length();
    if (fileSize == 0) {
      final emptyDigest = sha256.convert(const []).toString();
      return (
        wholeFileSha256: emptyDigest,
        chunkHashes: <String>[emptyDigest],
        totalChunks: 1,
        totalBytes: 0,
      );
    }

    final chunkHashes = <String>[];
    Digest? wholeFileDigest;
    final wholeFileInput = sha256.startChunkedConversion(
      ChunkedConversionSink<Digest>.withCallback((digests) {
        if (digests.isNotEmpty) {
          wholeFileDigest = digests.single;
        }
      }),
    );

    final raf = await file.open(mode: FileMode.read);
    try {
      int bytesReadTotal = 0;
      while (bytesReadTotal < fileSize) {
        final bytesToRead = (fileSize - bytesReadTotal).clamp(0, chunkSize);
        final chunkBuffer = await raf.read(bytesToRead);

        if (chunkBuffer.isEmpty) break;

        // Feed whole-file hasher
        wholeFileInput.add(chunkBuffer);

        // Compute individual chunk hash
        final chunkHash = sha256.convert(chunkBuffer).toString();
        chunkHashes.add(chunkHash);

        bytesReadTotal += chunkBuffer.length;
      }
      wholeFileInput.close();

      return (
        wholeFileSha256: wholeFileDigest?.toString() ?? sha256.convert(const []).toString(),
        chunkHashes: chunkHashes,
        totalChunks: chunkHashes.length,
        totalBytes: bytesReadTotal,
      );
    } finally {
      await raf.close();
    }
  }

  /// Verify complete file on disk against expected whole-file SHA-256 hash
  static Future<bool> verifyFile({
    required File file,
    required String expectedSha256,
  }) async {
    if (!await file.exists()) return false;
    final fileData = await hashFile(file: file, chunkSize: 1024 * 1024);
    return fileData.wholeFileSha256.toLowerCase() == expectedSha256.toLowerCase();
  }
}
