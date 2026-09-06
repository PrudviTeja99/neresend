import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../core/constants/protocol_constants.dart';
import '../../core/errors/exceptions.dart';
import '../../core/protocol/neresend_frame.dart';
import '../../core/protocol/frame_writer.dart';
import '../../core/utils/speed_calculator.dart';
import '../../domain/contracts/neresend_transport.dart';
import '../../domain/integrity/dynamic_chunk_sizer.dart';
import '../../domain/models/chunk_range.dart';
import '../../domain/models/transfer_manifest.dart';
import '../../domain/models/transfer_progress.dart';

/// Active sender transfer session orchestrating manifest negotiation, dynamic chunk streaming, and error handling
class SenderSession {
  final NeReSendTransport transport;
  final TransferManifest manifest;
  final List<File> files;
  final void Function(TransferProgress progress) onProgressUpdate;

  final SpeedCalculator _speedCalculator = SpeedCalculator();
  StreamSubscription<NeReSendFrame>? _frameSubscription;

  bool _isPaused = false;
  bool _isCancelled = false;
  Completer<void>? _pauseCompleter;
  final Completer<void> _doneCompleter = Completer<void>();

  SenderSession({
    required this.transport,
    required this.manifest,
    required this.files,
    required this.onProgressUpdate,
  });

  bool get isPaused => _isPaused;
  bool get isCancelled => _isCancelled;

  /// Execute the sender session
  Future<void> run() async {
    final acceptCompleter = Completer<Map<int, List<ChunkRange>>>();

    // Listen to control frames from receiver
    _frameSubscription = transport.incomingFrames.listen(
      (frame) async {
        try {
          await _handleIncomingFrame(frame, acceptCompleter);
        } catch (e) {
          if (!acceptCompleter.isCompleted) {
            acceptCompleter.completeError(e);
          }
        }
      },
      onError: (err) {
        if (!acceptCompleter.isCompleted) {
          acceptCompleter.completeError(err);
        }
        if (!_doneCompleter.isCompleted) {
          _doneCompleter.completeError(err);
        }
      },
      onDone: () {
        if (!_doneCompleter.isCompleted) {
          _doneCompleter.complete();
        }
      },
    );

    try {
      // 1. Send Manifest
      _emitProgress(TransferStatus.negotiating, 0);

      if (DynamicChunkSizer.requiresMultiPartSegmentation(
        totalFiles: manifest.totalFiles,
        estimatedManifestBytes: jsonEncode(manifest.toJson()).length,
      )) {
        final parts = FrameWriter.createManifestParts(manifest);
        for (final partFrame in parts) {
          await transport.sendFrame(partFrame);
        }
      } else {
        await transport.sendFrame(FrameWriter.createManifestRequest(manifest));
      }

      // 2. Wait for Accept/Decline response
      final acceptedRanges = await acceptCompleter.future;

      // 3. Stream Chunks
      _emitProgress(TransferStatus.transferring, 0);
      await _streamAllFiles(acceptedRanges);

      if (!_isCancelled) {
        // 4. Send Transfer Complete
        await transport
            .sendFrame(FrameWriter.createTransferComplete(manifest.transferId));
        _emitProgress(TransferStatus.completed, manifest.totalBytes);
      }
    } catch (e) {
      if (!_isCancelled) {
        _emitProgress(TransferStatus.failed, 0, errorMessage: e.toString());
      }
      rethrow;
    } finally {
      await _frameSubscription?.cancel();
    }
  }

  Future<void> _handleIncomingFrame(
    NeReSendFrame frame,
    Completer<Map<int, List<ChunkRange>>> acceptCompleter,
  ) async {
    switch (frame.type) {
      case ProtocolConstants.frameTypeAcceptResponse:
        final json =
            jsonDecode(utf8.decode(frame.payload)) as Map<String, dynamic>;
        final rawRangesMap = json['ranges'] as Map<String, dynamic>? ?? {};
        final parsedMap = <int, List<ChunkRange>>{};
        rawRangesMap.forEach((key, val) {
          final fileIdx = int.parse(key);
          final list = (val as List<dynamic>)
              .map((r) => ChunkRange.fromList(r as List<dynamic>))
              .toList();
          parsedMap[fileIdx] = ChunkRange.merge(list);
        });
        if (!acceptCompleter.isCompleted) {
          acceptCompleter.complete(parsedMap);
        }
        break;

      case ProtocolConstants.frameTypeDeclineResponse:
        final json =
            jsonDecode(utf8.decode(frame.payload)) as Map<String, dynamic>;
        final reason = json['reason'] as String? ?? 'DECLINED';
        if (!acceptCompleter.isCompleted) {
          acceptCompleter.completeError(
            ProtocolException('Transfer declined by peer: $reason',
                code: reason),
          );
        }
        break;

      case ProtocolConstants.frameTypePauseCommand:
        pause();
        break;

      case ProtocolConstants.frameTypeResumeCommand:
        resume();
        break;

      case ProtocolConstants.frameTypeRetryChunk:
        final parsed = FrameWriter.parseRetryChunk(frame.payload);
        await _resendChunk(parsed.fileIndex, parsed.chunkIndex);
        break;

      case ProtocolConstants.frameTypeCancelCommand:
        cancel();
        break;
    }
  }

  Future<void> _streamAllFiles(
      Map<int, List<ChunkRange>> acceptedRanges) async {
    int totalTransferred = 0;

    // Calculate initial transferred bytes from already verified ranges
    for (int i = 0; i < manifest.files.length; i++) {
      final item = manifest.files[i];
      final verified = acceptedRanges[i] ?? [];
      final verifiedChunks = ChunkRange.totalVerifiedChunks(verified);
      totalTransferred += (verifiedChunks * item.chunkSize).clamp(0, item.size);
    }

    _speedCalculator.reset();

    for (int fileIdx = 0; fileIdx < files.length; fileIdx++) {
      if (_isCancelled) break;

      final file = files[fileIdx];
      final item = manifest.files[fileIdx];
      final verifiedRanges = acceptedRanges[fileIdx] ?? [];
      final missingRanges =
          ChunkRange.computeMissingRanges(verifiedRanges, item.totalChunks);

      if (missingRanges.isEmpty) {
        continue; // Entire file already verified on receiver
      }

      final raf = await file.open(mode: FileMode.read);
      try {
        for (final range in missingRanges) {
          for (int chunkIdx = range.start; chunkIdx <= range.end; chunkIdx++) {
            if (_isCancelled) break;

            while (_isPaused) {
              _pauseCompleter ??= Completer<void>();
              await _pauseCompleter!.future;
            }

            final offset = chunkIdx * item.chunkSize;
            final bytesRemaining = item.size - offset;
            final bytesToRead = bytesRemaining.clamp(0, item.chunkSize);

            if (bytesToRead <= 0) break;

            await raf.setPosition(offset);
            final chunkBytes = await raf.read(bytesToRead);

            // Send chunk
            await transport.sendDataChunk(fileIdx, chunkIdx, chunkBytes);

            totalTransferred += chunkBytes.length;
            _speedCalculator.recordSample(totalTransferred);

            _emitProgress(
              TransferStatus.transferring,
              totalTransferred,
              currentFileIndex: fileIdx,
              currentChunkIndex: chunkIdx,
              totalChunks: item.totalChunks,
              verifiedRanges: verifiedRanges,
            );
          }
        }
      } finally {
        await raf.close();
      }
    }
  }

  Future<void> _resendChunk(int fileIdx, int chunkIdx) async {
    if (fileIdx >= files.length) return;
    final file = files[fileIdx];
    final item = manifest.files[fileIdx];
    final offset = chunkIdx * item.chunkSize;
    final bytesRemaining = item.size - offset;
    final bytesToRead = bytesRemaining.clamp(0, item.chunkSize);

    if (bytesToRead <= 0) return;

    final raf = await file.open(mode: FileMode.read);
    try {
      await raf.setPosition(offset);
      final chunkBytes = await raf.read(bytesToRead);
      await transport.sendDataChunk(fileIdx, chunkIdx, chunkBytes);
    } finally {
      await raf.close();
    }
  }

  void pause() {
    if (_isPaused) return;
    _isPaused = true;
    _emitProgress(TransferStatus.paused,
        _speedCalculator.calculateBytesPerSecond().toInt());
  }

  void resume() {
    if (!_isPaused) return;
    _isPaused = false;
    _pauseCompleter?.complete();
    _pauseCompleter = null;
    _emitProgress(TransferStatus.transferring,
        _speedCalculator.calculateBytesPerSecond().toInt());
  }

  void cancel() {
    _isCancelled = true;
    _isPaused = false;
    _pauseCompleter?.complete();
    _emitProgress(TransferStatus.cancelled, 0);
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
    final eta =
        _speedCalculator.calculateEta(transferredBytes, manifest.totalBytes);

    final progress = TransferProgress(
      transferId: manifest.transferId,
      currentFileName: fileName,
      currentFileIndex: currentFileIndex,
      totalFiles: manifest.totalFiles,
      verifiedRanges: verifiedRanges,
      currentChunkIndex: currentChunkIndex,
      totalChunks: totalChunks,
      bytesTransferred: transferredBytes,
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
