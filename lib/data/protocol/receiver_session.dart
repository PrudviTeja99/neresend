import 'dart:async';
import 'dart:io';
import '../../core/constants/protocol_constants.dart';
import '../../core/errors/exceptions.dart';
import '../../core/protocol/dropflow_frame.dart';
import '../../core/protocol/frame_writer.dart';
import '../../core/utils/speed_calculator.dart';
import '../../domain/contracts/dropflow_transport.dart';
import '../../domain/integrity/chunk_hasher.dart';
import '../../domain/integrity/part_file_manager.dart';
import '../../domain/models/chunk_range.dart';
import '../../domain/models/transfer_manifest.dart';
import '../../domain/models/transfer_progress.dart';

/// Active receiver transfer session handling sparse verification, RAM hash checks, and atomic file finalization
class ReceiverSession {
  final DropFlowTransport transport;
  final TransferManifest manifest;
  final String destinationDirectory;
  final void Function(TransferProgress progress) onProgressUpdate;

  final SpeedCalculator _speedCalculator = SpeedCalculator();
  StreamSubscription<DropFlowFrame>? _frameSubscription;

  final Map<int, List<ChunkRange>> _verifiedRangesMap = {};
  int _totalTransferredBytes = 0;
  bool _isCancelled = false;
  final Completer<void> _completionCompleter = Completer<void>();

  ReceiverSession({
    required this.transport,
    required this.manifest,
    required this.destinationDirectory,
    required this.onProgressUpdate,
  });

  bool get isCancelled => _isCancelled;

  /// Execute the receiver session
  Future<void> run() async {
    try {
      // 1. Check existing partial files for resumption ranges
      for (int i = 0; i < manifest.files.length; i++) {
        final item = manifest.files[i];
        final existingRanges = await PartFileManager.loadVerifiedRanges(
          downloadDir: destinationDirectory,
          item: item,
        );
        _verifiedRangesMap[i] = existingRanges;
        final verifiedChunks = ChunkRange.totalVerifiedChunks(existingRanges);
        _totalTransferredBytes += (verifiedChunks * item.chunkSize).clamp(0, item.size);

        await PartFileManager.initializePartFile(
          downloadDir: destinationDirectory,
          item: item,
        );
      }

      // 2. Send Accept Response with verified sparse chunk ranges
      final acceptFrame = FrameWriter.createAcceptResponse(
        transferId: manifest.transferId,
        acceptedRanges: _verifiedRangesMap,
      );
      await transport.sendFrame(acceptFrame);

      _speedCalculator.reset();
      _emitProgress(TransferStatus.transferring, _totalTransferredBytes);

      // 3. Listen for incoming data chunks and control commands
      _frameSubscription = transport.incomingFrames.listen(
        (frame) async {
          try {
            await _handleIncomingFrame(frame);
          } catch (e) {
            if (!_completionCompleter.isCompleted) {
              _completionCompleter.completeError(e);
            }
          }
        },
        onError: (err) {
          if (!_completionCompleter.isCompleted) {
            _completionCompleter.completeError(err);
          }
        },
        onDone: () {
          if (!_completionCompleter.isCompleted && !_isCancelled) {
            _completionCompleter.complete();
          }
        },
      );

      await _completionCompleter.future;
    } catch (e) {
      if (!_isCancelled) {
        _emitProgress(TransferStatus.failed, _totalTransferredBytes, errorMessage: e.toString());
      }
      rethrow;
    } finally {
      await _frameSubscription?.cancel();
    }
  }

  Future<void> _handleIncomingFrame(DropFlowFrame frame) async {
    switch (frame.type) {
      case ProtocolConstants.frameTypeFileDataChunk:
        final parsed = FrameWriter.parseFileDataChunk(frame.payload);
        final fileIdx = parsed.fileIndex;
        final chunkIdx = parsed.chunkIndex;
        final chunkData = parsed.chunkData;

        if (fileIdx >= manifest.files.length) {
          throw ProtocolException('Invalid fileIndex $fileIdx in incoming chunk');
        }

        final item = manifest.files[fileIdx];
        if (chunkIdx >= item.chunkHashes.length) {
          throw ProtocolException('Invalid chunkIndex $chunkIdx for file ${item.fileName}');
        }

        final expectedHash = item.chunkHashes[chunkIdx];

        // 1. Verify in-memory SHA-256 hash
        final isHashValid = ChunkHasher.verifyChunk(chunkData, expectedHash);
        if (!isHashValid) {
          // Corrupted in transit; send RETRY_CHUNK immediately
          final retryFrame = FrameWriter.createRetryChunk(fileIndex: fileIdx, chunkIndex: chunkIdx);
          await transport.sendFrame(retryFrame);
          return;
        }

        // 2. Write verified chunk to sparse part file
        final currentRanges = _verifiedRangesMap[fileIdx] ?? [];
        final updatedRanges = await PartFileManager.writeVerifiedChunk(
          downloadDir: destinationDirectory,
          item: item,
          chunkIndex: chunkIdx,
          chunkBytes: chunkData,
          currentVerifiedRanges: currentRanges,
        );
        _verifiedRangesMap[fileIdx] = updatedRanges;

        _totalTransferredBytes += chunkData.length;
        _speedCalculator.recordSample(_totalTransferredBytes);

        _emitProgress(
          TransferStatus.transferring,
          _totalTransferredBytes,
          currentFileIndex: fileIdx,
          currentChunkIndex: chunkIdx,
          totalChunks: item.totalChunks,
          verifiedRanges: updatedRanges,
        );
        break;

      case ProtocolConstants.frameTypeTransferComplete:
        // Sender finished sending all chunks; finalize and verify all files on disk
        _emitProgress(TransferStatus.verifying, manifest.totalBytes);

        for (int i = 0; i < manifest.files.length; i++) {
          final item = manifest.files[i];
          await PartFileManager.finalizeFile(
            downloadDir: destinationDirectory,
            item: item,
          );
        }

        _emitProgress(TransferStatus.completed, manifest.totalBytes);
        if (!_completionCompleter.isCompleted) {
          _completionCompleter.complete();
        }
        break;

      case ProtocolConstants.frameTypePauseCommand:
        _emitProgress(TransferStatus.paused, _totalTransferredBytes);
        break;

      case ProtocolConstants.frameTypeResumeCommand:
        _emitProgress(TransferStatus.transferring, _totalTransferredBytes);
        break;

      case ProtocolConstants.frameTypeCancelCommand:
        _isCancelled = true;
        _emitProgress(TransferStatus.cancelled, _totalTransferredBytes);
        if (!_completionCompleter.isCompleted) {
          _completionCompleter.complete();
        }
        break;
    }
  }

  void cancel() {
    _isCancelled = true;
    _emitProgress(TransferStatus.cancelled, _totalTransferredBytes);
    if (!_completionCompleter.isCompleted) {
      _completionCompleter.complete();
    }
  }

  void _emitProgress(
    TransferStatus status,
    int transferredBytes, {
    int currentFileIndex = 0,
    int currentChunkIndex = 0,
    int totalChunks = 1,
    List<ChunkRange> verifiedRanges = const [],
    String? errorMessage,
  }) {
    final fileName = currentFileIndex < manifest.files.length
        ? manifest.files[currentFileIndex].fileName
        : '';
    final eta = _speedCalculator.calculateEta(transferredBytes, manifest.totalBytes);

    final progress = TransferProgress(
      transferId: manifest.transferId,
      currentFileName: fileName,
      currentFileIndex: currentFileIndex,
      totalFiles: manifest.totalFiles,
      verifiedRanges: verifiedRanges,
      currentChunkIndex: currentChunkIndex,
      totalChunks: totalChunks,
      bytesTransferred: transferredBytes.clamp(0, manifest.totalBytes),
      totalBytes: manifest.totalBytes,
      speedBytesPerSecond: status == TransferStatus.transferring
          ? _speedCalculator.calculateBytesPerSecond()
          : 0.0,
      estimatedTimeRemaining: eta,
      status: status,
      errorMessage: errorMessage,
    );
    onProgressUpdate(progress);
  }
}
