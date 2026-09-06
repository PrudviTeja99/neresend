import 'package:flutter_test/flutter_test.dart';
import 'package:neresend/domain/models/transfer_mode.dart';
import 'package:neresend/domain/models/discovered_peer.dart';
import 'package:neresend/domain/models/chunk_range.dart';
import 'package:neresend/domain/models/transfer_item.dart';
import 'package:neresend/domain/models/transfer_manifest.dart';
import 'package:neresend/domain/models/transfer_progress.dart';

void main() {
  group('Domain Models Tests', () {
    test('ChunkRange interval merging and containment', () {
      const r1 = ChunkRange(0, 100);
      const r2 = ChunkRange(101, 200);
      const r3 = ChunkRange(300, 400);

      expect(r1.count, 101);
      expect(r1.contains(50), isTrue);
      expect(r1.contains(101), isFalse);

      // Merge contiguous [0..100] and [101..200]
      final merged = ChunkRange.merge([r2, r1, r3]);
      expect(merged.length, 2);
      expect(merged[0], const ChunkRange(0, 200));
      expect(merged[1], const ChunkRange(300, 400));
      expect(ChunkRange.totalVerifiedChunks(merged), 302);
      expect(ChunkRange.isComplete(merged, 401), isFalse);

      // Complete range check
      final fullRange = [const ChunkRange(0, 99)];
      expect(ChunkRange.isComplete(fullRange, 100), isTrue);
    });

    test('DiscoveredPeer JSON serialization & equality', () {
      final peer = DiscoveredPeer(
        id: 'peer-123',
        alias: 'Test Phone',
        deviceType: DeviceType.android,
        ipAddress: '192.168.1.50',
        port: 53318,
        supportedMode: TransferMode.lan,
        identityPublicKey: 'pubkey123',
        fingerprint: 'A1:B2:C3:D4',
        isTrusted: true,
        lastSeen: DateTime(2026, 1, 1),
      );

      final json = peer.toJson();
      final restored = DiscoveredPeer.fromJson(json);

      expect(restored.id, 'peer-123');
      expect(restored.alias, 'Test Phone');
      expect(restored.deviceType, DeviceType.android);
      expect(restored.supportedMode, TransferMode.lan);
      expect(restored.isTrusted, isTrue);
      expect(restored, equals(peer));
    });

    test('TransferManifest JSON serialization with TransferItems', () {
      const item = TransferItem(
        id: 'file-1',
        fileName: 'report.pdf',
        size: 2048576,
        mimeType: 'application/pdf',
        wholeFileSha256: 'abc123sha256',
        chunkSize: 1048576,
        totalChunks: 2,
        chunkHashes: ['hash1', 'hash2'],
      );

      final manifest = TransferManifest(
        transferId: 'transfer-xyz',
        senderAlias: 'Laptop',
        senderFingerprint: 'FF:EE:DD:CC',
        files: [item],
        totalBytes: 2048576,
        totalFiles: 1,
        createdAt: DateTime(2026, 1, 1),
      );

      final json = manifest.toJson();
      final restored = TransferManifest.fromJson(json);

      expect(restored.transferId, 'transfer-xyz');
      expect(restored.files.length, 1);
      expect(restored.files.first.fileName, 'report.pdf');
      expect(restored.files.first.chunkHashes, ['hash1', 'hash2']);
      expect(restored, equals(manifest));
    });

    test('TransferProgress fraction and state predicates', () {
      const progress = TransferProgress(
        transferId: 't-1',
        currentFileName: 'video.mp4',
        currentFileIndex: 0,
        totalFiles: 1,
        verifiedRanges: [ChunkRange(0, 50)],
        currentChunkIndex: 50,
        totalChunks: 100,
        bytesTransferred: 50000000,
        totalBytes: 100000000,
        speedBytesPerSecond: 10485760.0,
        estimatedTimeRemaining: Duration(seconds: 5),
        status: TransferStatus.transferring,
      );

      expect(progress.progressFraction, 0.5);
      expect(progress.progressPercent, 50);
      expect(progress.isActive, isTrue);
      expect(progress.isCompleted, isFalse);
    });
  });
}
