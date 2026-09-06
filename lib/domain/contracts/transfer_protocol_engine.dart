import 'dart:io';
import '../models/transfer_manifest.dart';
import '../models/transfer_progress.dart';
import 'neresend_transport.dart';

/// Incoming transfer request requiring receiver confirmation
class IncomingTransferRequest {
  final String transferId;
  final TransferManifest manifest;
  final NeReSendTransport transport;

  const IncomingTransferRequest({
    required this.transferId,
    required this.manifest,
    required this.transport,
  });
}

/// Network-agnostic transfer protocol state machine
abstract class TransferProtocolEngine {
  /// Live stream of file transfer progress
  Stream<TransferProgress> get onProgress;

  /// Stream of incoming transfer requests requiring user approval
  Stream<IncomingTransferRequest> get onIncomingRequest;

  /// Start a sender session over an authenticated transport
  Future<void> startSenderSession(NeReSendTransport transport, List<File> files);

  /// Accept an incoming transfer request and begin receiving files into destinationDirectory
  Future<void> acceptTransfer(String transferId, String destinationDirectory);

  /// Decline an incoming transfer request
  Future<void> declineTransfer(String transferId, {String reason});

  /// Pause an active transfer
  Future<void> pauseTransfer(String transferId);

  /// Resume a paused transfer
  Future<void> resumeTransfer(String transferId);

  /// Cancel an ongoing transfer
  Future<void> cancelTransfer(String transferId);
}

