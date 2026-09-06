import 'package:flutter_test/flutter_test.dart';
import 'package:neresend/domain/models/transfer_progress.dart';
import 'package:neresend/presentation/state/active_transfer_provider.dart';

void main() {
  group('ActiveTransferProvider & Notifier Tests', () {
    test('StateNotifier updates progress and calculates state correctly', () {
      final notifier = ActiveTransferNotifier(null);
      expect(notifier.state, isNull);

      const progress = TransferProgress(
        transferId: 't-123',
        currentFileName: 'archive.zip',
        currentFileIndex: 0,
        totalFiles: 1,
        verifiedRanges: [],
        currentChunkIndex: 5,
        totalChunks: 10,
        bytesTransferred: 500000,
        totalBytes: 1000000,
        speedBytesPerSecond: 25000000.0,
        estimatedTimeRemaining: Duration(seconds: 5),
        status: TransferStatus.transferring,
      );

      notifier.updateProgress(progress);
      expect(notifier.state, isNotNull);
      expect(notifier.state!.transferId, 't-123');
      expect(notifier.state!.progressFraction, 0.5);
      expect(notifier.state!.isTerminated, isFalse);

      notifier.dispose();
    });
  });
}
