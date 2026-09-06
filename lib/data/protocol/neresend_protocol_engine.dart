import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../core/constants/protocol_constants.dart';
import '../../core/errors/exceptions.dart';
import '../../core/protocol/neresend_frame.dart';
import '../../core/protocol/frame_writer.dart';
import '../../domain/contracts/neresend_transport.dart';
import '../../domain/contracts/transfer_protocol_engine.dart';
import '../../domain/integrity/chunk_hasher.dart';
import '../../domain/integrity/dynamic_chunk_sizer.dart';
import '../../domain/models/device_identity.dart';
import '../../domain/models/transfer_item.dart';
import '../../domain/models/transfer_manifest.dart';
import '../../domain/models/transfer_progress.dart';
import 'receiver_session.dart';
import 'sender_session.dart';

/// Concrete implementation of TransferProtocolEngine coordinating send and receive sessions
class NeReSendProtocolEngine implements TransferProtocolEngine {
  final DeviceIdentity localIdentity;
  final bool isRemote;

  final StreamController<TransferProgress> _progressController =
      StreamController<TransferProgress>.broadcast();
  final StreamController<IncomingTransferRequest> _incomingRequestController =
      StreamController<IncomingTransferRequest>.broadcast();

  final Map<String, SenderSession> _activeSenderSessions = {};
  final Map<String, ReceiverSession> _activeReceiverSessions = {};
  final Map<String, ({IncomingTransferRequest request, Completer<bool> responseCompleter})> _pendingRequests = {};

  NeReSendProtocolEngine({
    required this.localIdentity,
    this.isRemote = false,
  });

  @override
  Stream<TransferProgress> get onProgress => _progressController.stream;

  @override
  Stream<IncomingTransferRequest> get onIncomingRequest => _incomingRequestController.stream;

  /// Register an active transport to listen for incoming transfer requests
  void listenToTransport(NeReSendTransport transport) {
    StreamSubscription<NeReSendFrame>? sub;
    final multiPartAccumulator = <String, List<TransferItem>>{};
    TransferManifest? partialManifestHeader;

    sub = transport.incomingFrames.listen(
      (frame) async {
        if (frame.type == ProtocolConstants.frameTypeManifestRequest) {
          final json = jsonDecode(utf8.decode(frame.payload)) as Map<String, dynamic>;
          final manifest = TransferManifest.fromJson(json);
          await _handleManifestReceived(manifest, transport);
        } else if (frame.type == ProtocolConstants.frameTypeManifestPart) {
          final json = jsonDecode(utf8.decode(frame.payload)) as Map<String, dynamic>;
          final transferId = json['transferId'] as String;
          final filesList = (json['files'] as List<dynamic>)
              .map((f) => TransferItem.fromJson(f as Map<String, dynamic>))
              .toList();

          multiPartAccumulator.putIfAbsent(transferId, () => []).addAll(filesList);

          if (partialManifestHeader == null) {
            partialManifestHeader = TransferManifest(
              transferId: transferId,
              senderAlias: json['senderAlias'] as String,
              senderFingerprint: json['senderFingerprint'] as String,
              files: const [],
              totalBytes: json['totalBytes'] as int,
              totalFiles: json['totalFiles'] as int,
              createdAt: DateTime.parse(json['createdAt'] as String),
            );
          }
        } else if (frame.type == ProtocolConstants.frameTypeManifestEnd) {
          final json = jsonDecode(utf8.decode(frame.payload)) as Map<String, dynamic>;
          final transferId = json['transferId'] as String;
          final accumulatedFiles = multiPartAccumulator.remove(transferId) ?? [];

          if (partialManifestHeader != null) {
            final completeManifest = TransferManifest(
              transferId: transferId,
              senderAlias: partialManifestHeader!.senderAlias,
              senderFingerprint: partialManifestHeader!.senderFingerprint,
              files: accumulatedFiles,
              totalBytes: partialManifestHeader!.totalBytes,
              totalFiles: partialManifestHeader!.totalFiles,
              createdAt: partialManifestHeader!.createdAt,
            );
            partialManifestHeader = null;
            await _handleManifestReceived(completeManifest, transport);
          }
        }
      },
      onDone: () => sub?.cancel(),
      onError: (_) => sub?.cancel(),
    );
  }

  Future<void> _handleManifestReceived(
    TransferManifest manifest,
    NeReSendTransport transport,
  ) async {
    final responseCompleter = Completer<bool>();
    final request = IncomingTransferRequest(
      transferId: manifest.transferId,
      manifest: manifest,
      transport: transport,
    );

    _pendingRequests[manifest.transferId] = (
      request: request,
      responseCompleter: responseCompleter,
    );

    _incomingRequestController.add(request);
  }

  @override
  Future<void> startSenderSession(NeReSendTransport transport, List<File> files) async {
    if (files.isEmpty) {
      throw const StorageException('Cannot start transfer with empty file list');
    }

    final transferId = const Uuid().v4();
    final transferItems = <TransferItem>[];
    int totalBytes = 0;

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final fileSize = await file.length();
      totalBytes += fileSize;

      final chunkSize = DynamicChunkSizer.calculateChunkSize(
        totalFileSizeBytes: fileSize,
        isRemote: isRemote,
      );

      final hashResult = await ChunkHasher.hashFile(
        file: file,
        chunkSize: chunkSize,
      );

      final fileName = p.basename(file.path);
      transferItems.add(
        TransferItem(
          id: const Uuid().v4(),
          fileName: fileName,
          size: fileSize,
          mimeType: 'application/octet-stream',
          wholeFileSha256: hashResult.wholeFileSha256,
          chunkSize: chunkSize,
          totalChunks: hashResult.totalChunks,
          chunkHashes: hashResult.chunkHashes,
        ),
      );
    }

    final manifest = TransferManifest(
      transferId: transferId,
      senderAlias: localIdentity.alias,
      senderFingerprint: localIdentity.fingerprint,
      files: transferItems,
      totalBytes: totalBytes,
      totalFiles: transferItems.length,
      createdAt: DateTime.now().toUtc(),
    );

    final session = SenderSession(
      transport: transport,
      manifest: manifest,
      files: files,
      onProgressUpdate: (progress) => _progressController.add(progress),
    );

    _activeSenderSessions[transferId] = session;
    try {
      await session.run();
    } finally {
      _activeSenderSessions.remove(transferId);
    }
  }

  @override
  Future<void> acceptTransfer(String transferId, String destinationDirectory) async {
    final pending = _pendingRequests.remove(transferId);
    if (pending == null) {
      throw StorageException('No pending transfer request found for $transferId');
    }

    final request = pending.request;
    final session = ReceiverSession(
      transport: request.transport,
      manifest: request.manifest,
      destinationDirectory: destinationDirectory,
      onProgressUpdate: (progress) => _progressController.add(progress),
    );

    _activeReceiverSessions[transferId] = session;
    try {
      await session.run();
    } finally {
      _activeReceiverSessions.remove(transferId);
    }
  }

  @override
  Future<void> declineTransfer(
    String transferId, {
    String reason = ProtocolConstants.declineUserRejected,
  }) async {
    final pending = _pendingRequests.remove(transferId);
    if (pending != null) {
      final frame = FrameWriter.createDeclineResponse(
        transferId: transferId,
        reason: reason,
      );
      await pending.request.transport.sendFrame(frame);
    }
  }

  @override
  Future<void> pauseTransfer(String transferId) async {
    if (_activeSenderSessions.containsKey(transferId)) {
      _activeSenderSessions[transferId]!.pause();
      await _activeSenderSessions[transferId]!.transport.sendFrame(
        FrameWriter.createPauseCommand(transferId),
      );
    }
  }

  @override
  Future<void> resumeTransfer(String transferId) async {
    if (_activeSenderSessions.containsKey(transferId)) {
      _activeSenderSessions[transferId]!.resume();
      await _activeSenderSessions[transferId]!.transport.sendFrame(
        FrameWriter.createResumeCommand(transferId),
      );
    }
  }

  @override
  Future<void> cancelTransfer(String transferId) async {
    if (_activeSenderSessions.containsKey(transferId)) {
      _activeSenderSessions[transferId]!.cancel();
      await _activeSenderSessions[transferId]!.transport.sendFrame(
        FrameWriter.createCancelCommand(transferId),
      );
    } else if (_activeReceiverSessions.containsKey(transferId)) {
      _activeReceiverSessions[transferId]!.cancel();
      await _activeReceiverSessions[transferId]!.transport.sendFrame(
        FrameWriter.createCancelCommand(transferId),
      );
    }
  }

  void dispose() {
    _progressController.close();
    _incomingRequestController.close();
  }
}
