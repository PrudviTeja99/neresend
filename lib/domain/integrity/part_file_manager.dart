import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import '../../core/errors/exceptions.dart';
import '../models/chunk_range.dart';
import '../models/transfer_item.dart';
import 'chunk_hasher.dart';

/// Manages sparse .neresend.part and .neresend.meta sidecar files on disk with RandomAccessFile writes
class PartFileManager {
  static const String partExtension = '.neresend.part';
  static const String metaExtension = '.neresend.meta';

  /// Strips path traversal tokens, null bytes, and OS-reserved characters
  static String sanitizeFilename(String filename) {
    var clean = filename.replaceAll(RegExp(r'[\x00/\\:\*\?"<>\|]'), '_');
    clean = clean.replaceAll(RegExp(r'\.+'), '.');
    clean = clean.replaceAll(RegExp(r'^[\._]+'), '');
    clean = clean.trim();
    if (clean.isEmpty) {
      clean = 'download_${DateTime.now().millisecondsSinceEpoch}';
    }
    return clean;
  }

  static String getPartPath(String downloadDir, String sanitizedFilename) {
    return p.join(downloadDir, '$sanitizedFilename$partExtension');
  }

  static String getMetaPath(String downloadDir, String sanitizedFilename) {
    return p.join(downloadDir, '$sanitizedFilename$metaExtension');
  }

  static String getFinalPath(String downloadDir, String sanitizedFilename) {
    return p.join(downloadDir, sanitizedFilename);
  }

  /// Loads already verified chunk ranges from existing .neresend.meta sidecar file if hash matches
  static Future<List<ChunkRange>> loadVerifiedRanges({
    required String downloadDir,
    required TransferItem item,
  }) async {
    final cleanName = sanitizeFilename(item.fileName);
    final partFile = File(getPartPath(downloadDir, cleanName));
    final metaFile = File(getMetaPath(downloadDir, cleanName));

    if (!await partFile.exists() || !await metaFile.exists()) {
      return [];
    }

    try {
      final metaContent = await metaFile.readAsString();
      final metaJson = jsonDecode(metaContent) as Map<String, dynamic>;

      // Ensure sidecar corresponds to the exact same file version
      if (metaJson['wholeFileSha256'] != item.wholeFileSha256 ||
          metaJson['size'] != item.size ||
          metaJson['chunkSize'] != item.chunkSize) {
        // Mismatched file version; delete stale partials
        await deletePartials(downloadDir, cleanName);
        return [];
      }

      final rawRanges = metaJson['verifiedRanges'] as List<dynamic>? ?? [];
      final ranges = rawRanges.map((r) => ChunkRange.fromList(r as List<dynamic>)).toList();
      return ChunkRange.merge(ranges);
    } catch (_) {
      return [];
    }
  }

  /// Initialize or prepare a sparse .neresend.part file on disk
  static Future<void> initializePartFile({
    required String downloadDir,
    required TransferItem item,
  }) async {
    final cleanName = sanitizeFilename(item.fileName);
    final targetDir = Directory(downloadDir);
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final partFile = File(getPartPath(downloadDir, cleanName));
    if (!await partFile.exists()) {
      await partFile.create();
    }

    final metaFile = File(getMetaPath(downloadDir, cleanName));
    if (!await metaFile.exists()) {
      final metaJson = {
        'fileName': cleanName,
        'size': item.size,
        'chunkSize': item.chunkSize,
        'totalChunks': item.totalChunks,
        'wholeFileSha256': item.wholeFileSha256,
        'verifiedRanges': <List<int>>[],
      };
      await metaFile.writeAsString(jsonEncode(metaJson));
    }
  }

  /// Sparse write of a verified chunk directly at the offset calculated from [chunkIndex]
  static Future<List<ChunkRange>> writeVerifiedChunk({
    required String downloadDir,
    required TransferItem item,
    required int chunkIndex,
    required Uint8List chunkBytes,
    required List<ChunkRange> currentVerifiedRanges,
  }) async {
    final cleanName = sanitizeFilename(item.fileName);
    final partFile = File(getPartPath(downloadDir, cleanName));

    if (!await partFile.exists()) {
      await initializePartFile(downloadDir: downloadDir, item: item);
    }

    // Sparse random-access write at chunk offset
    final offset = chunkIndex * item.chunkSize;
    final raf = await partFile.open(mode: FileMode.append);
    try {
      await raf.setPosition(offset);
      await raf.writeFrom(chunkBytes);
      await raf.flush();
    } finally {
      await raf.close();
    }

    // Merge new chunk range
    final updatedRanges = ChunkRange.merge([
      ...currentVerifiedRanges,
      ChunkRange(chunkIndex, chunkIndex),
    ]);

    // Persist updated metadata sidecar
    final metaFile = File(getMetaPath(downloadDir, cleanName));
    final metaJson = {
      'fileName': cleanName,
      'size': item.size,
      'chunkSize': item.chunkSize,
      'totalChunks': item.totalChunks,
      'wholeFileSha256': item.wholeFileSha256,
      'verifiedRanges': updatedRanges.map((r) => r.toList()).toList(),
    };
    await metaFile.writeAsString(jsonEncode(metaJson));

    return updatedRanges;
  }

  /// Validates whole-file SHA-256 and atomically renames the part file to its final filename
  static Future<File> finalizeFile({
    required String downloadDir,
    required TransferItem item,
  }) async {
    final cleanName = sanitizeFilename(item.fileName);
    final partFile = File(getPartPath(downloadDir, cleanName));
    final metaFile = File(getMetaPath(downloadDir, cleanName));

    if (!await partFile.exists()) {
      throw StorageException('Part file does not exist for $cleanName');
    }

    // Full file cryptographic integrity verification
    final isValid = await ChunkHasher.verifyFile(
      file: partFile,
      expectedSha256: item.wholeFileSha256,
    );

    if (!isValid) {
      throw StorageException(
        'Whole-file SHA-256 integrity verification failed for $cleanName',
        code: 'INTEGRITY_MISMATCH',
      );
    }

    // Determine target destination (resolving collisions if necessary)
    var finalPath = getFinalPath(downloadDir, cleanName);
    var finalFile = File(finalPath);
    if (await finalFile.exists()) {
      final nameWithoutExt = p.basenameWithoutExtension(cleanName);
      final ext = p.extension(cleanName);
      int counter = 1;
      while (await finalFile.exists()) {
        finalPath = p.join(downloadDir, '$nameWithoutExt ($counter)$ext');
        finalFile = File(finalPath);
        counter++;
      }
    }

    // Atomic rename with fallback for Windows locked file handles
    try {
      await partFile.rename(finalPath);
    } catch (_) {
      await partFile.copy(finalPath);
      try {
        await partFile.delete();
      } catch (_) {}
    }

    // Delete sidecar meta file
    if (await metaFile.exists()) {
      try {
        await metaFile.delete();
      } catch (_) {}
    }

    return finalFile;
  }

  /// Deletes .neresend.part and .neresend.meta sidecars
  static Future<void> deletePartials(String downloadDir, String sanitizedFilename) async {
    final partFile = File(getPartPath(downloadDir, sanitizedFilename));
    if (await partFile.exists()) {
      await partFile.delete();
    }
    final metaFile = File(getMetaPath(downloadDir, sanitizedFilename));
    if (await metaFile.exists()) {
      await metaFile.delete();
    }
  }
}
