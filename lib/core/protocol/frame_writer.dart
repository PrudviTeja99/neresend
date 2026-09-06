import 'dart:convert';
import 'dart:typed_data';
import '../constants/protocol_constants.dart';
import '../../domain/models/auth_handshake.dart';
import '../../domain/models/chunk_range.dart';
import '../../domain/models/transfer_manifest.dart';
import 'dropflow_frame.dart';

/// Helper utility for creating and serializing protocol messages into DropFlowFrame instances
class FrameWriter {
  FrameWriter._();

  /// Create a generic frame
  static DropFlowFrame createFrame(int type, Uint8List payload) {
    return DropFlowFrame(type: type, payload: payload);
  }

  /// Create AUTH_HANDSHAKE frame (0x00)
  static DropFlowFrame createAuthHandshake(AuthHandshake handshake) {
    return DropFlowFrame(
      type: ProtocolConstants.frameTypeAuthHandshake,
      payload: handshake.toBytes(),
    );
  }

  /// Create MANIFEST_REQUEST frame (0x01)
  static DropFlowFrame createManifestRequest(TransferManifest manifest) {
    final jsonStr = jsonEncode(manifest.toJson());
    final payload = Uint8List.fromList(utf8.encode(jsonStr));
    return DropFlowFrame(
      type: ProtocolConstants.frameTypeManifestRequest,
      payload: payload,
    );
  }

  /// Segment a large multi-file manifest into MANIFEST_PART frames (0x04) and MANIFEST_END (0x05)
  static List<DropFlowFrame> createManifestParts(
    TransferManifest manifest, {
    int maxPartItems = 50,
  }) {
    final frames = <DropFlowFrame>[];
    final allFiles = manifest.files;
    final totalParts = (allFiles.length / maxPartItems).ceil().clamp(1, 65535);

    for (int partIdx = 0; partIdx < totalParts; partIdx++) {
      final startIndex = partIdx * maxPartItems;
      final endIndex = (startIndex + maxPartItems).clamp(0, allFiles.length);
      final subList = allFiles.sublist(startIndex, endIndex);

      final partPayload = jsonEncode({
        'transferId': manifest.transferId,
        'senderAlias': manifest.senderAlias,
        'senderFingerprint': manifest.senderFingerprint,
        'partIndex': partIdx,
        'totalParts': totalParts,
        'totalBytes': manifest.totalBytes,
        'totalFiles': manifest.totalFiles,
        'createdAt': manifest.createdAt.toIso8601String(),
        'files': subList.map((f) => f.toJson()).toList(),
      });

      frames.add(
        DropFlowFrame(
          type: ProtocolConstants.frameTypeManifestPart,
          payload: Uint8List.fromList(utf8.encode(partPayload)),
        ),
      );
    }

    frames.add(
      DropFlowFrame(
        type: ProtocolConstants.frameTypeManifestEnd,
        payload: Uint8List.fromList(
          utf8.encode(jsonEncode({'transferId': manifest.transferId})),
        ),
      ),
    );

    return frames;
  }

  /// Create ACCEPT_RESPONSE frame (0x02) with sparse chunk ranges
  static DropFlowFrame createAcceptResponse({
    required String transferId,
    required Map<int, List<ChunkRange>> acceptedRanges,
  }) {
    final rangesMap = <String, List<List<int>>>{};
    acceptedRanges.forEach((fileIdx, ranges) {
      rangesMap[fileIdx.toString()] = ranges.map((r) => r.toList()).toList();
    });

    final payloadStr = jsonEncode({
      'transferId': transferId,
      'ranges': rangesMap,
    });

    return DropFlowFrame(
      type: ProtocolConstants.frameTypeAcceptResponse,
      payload: Uint8List.fromList(utf8.encode(payloadStr)),
    );
  }

  /// Create DECLINE_RESPONSE frame (0x03)
  static DropFlowFrame createDeclineResponse({
    required String transferId,
    required String reason,
  }) {
    final payloadStr = jsonEncode({
      'transferId': transferId,
      'reason': reason,
    });
    return DropFlowFrame(
      type: ProtocolConstants.frameTypeDeclineResponse,
      payload: Uint8List.fromList(utf8.encode(payloadStr)),
    );
  }

  /// Create FILE_DATA_CHUNK frame (0x10): [4B fileIdx] [4B chunkIdx] [raw chunk bytes]
  static DropFlowFrame createFileDataChunk({
    required int fileIndex,
    required int chunkIndex,
    required Uint8List chunkData,
  }) {
    final payload = Uint8List(8 + chunkData.length);
    final byteData = ByteData.sublistView(payload);

    byteData.setUint32(0, fileIndex, Endian.big);
    byteData.setUint32(4, chunkIndex, Endian.big);
    payload.setRange(8, payload.length, chunkData);

    return DropFlowFrame(
      type: ProtocolConstants.frameTypeFileDataChunk,
      payload: payload,
    );
  }

  /// Parse FILE_DATA_CHUNK payload into (fileIndex, chunkIndex, chunkData)
  static ({int fileIndex, int chunkIndex, Uint8List chunkData}) parseFileDataChunk(
    Uint8List payload,
  ) {
    if (payload.length < 8) {
      throw const FormatException('FILE_DATA_CHUNK payload must be at least 8 bytes');
    }
    final byteData = ByteData.sublistView(payload);
    final fileIndex = byteData.getUint32(0, Endian.big);
    final chunkIndex = byteData.getUint32(4, Endian.big);
    final chunkData = Uint8List.sublistView(payload, 8);

    return (
      fileIndex: fileIndex,
      chunkIndex: chunkIndex,
      chunkData: chunkData,
    );
  }

  /// Create PAUSE_COMMAND frame (0x20)
  static DropFlowFrame createPauseCommand(String transferId) {
    return DropFlowFrame(
      type: ProtocolConstants.frameTypePauseCommand,
      payload: Uint8List.fromList(utf8.encode(jsonEncode({'transferId': transferId}))),
    );
  }

  /// Create RESUME_COMMAND frame (0x21)
  static DropFlowFrame createResumeCommand(String transferId) {
    return DropFlowFrame(
      type: ProtocolConstants.frameTypeResumeCommand,
      payload: Uint8List.fromList(utf8.encode(jsonEncode({'transferId': transferId}))),
    );
  }

  /// Create RETRY_CHUNK frame (0x22): [4B fileIdx] [4B chunkIdx]
  static DropFlowFrame createRetryChunk({
    required int fileIndex,
    required int chunkIndex,
  }) {
    final payload = Uint8List(8);
    final byteData = ByteData.sublistView(payload);
    byteData.setUint32(0, fileIndex, Endian.big);
    byteData.setUint32(4, chunkIndex, Endian.big);

    return DropFlowFrame(
      type: ProtocolConstants.frameTypeRetryChunk,
      payload: payload,
    );
  }

  /// Parse RETRY_CHUNK payload into (fileIndex, chunkIndex)
  static ({int fileIndex, int chunkIndex}) parseRetryChunk(Uint8List payload) {
    if (payload.length < 8) {
      throw const FormatException('RETRY_CHUNK payload must be at least 8 bytes');
    }
    final byteData = ByteData.sublistView(payload);
    final fileIndex = byteData.getUint32(0, Endian.big);
    final chunkIndex = byteData.getUint32(4, Endian.big);

    return (fileIndex: fileIndex, chunkIndex: chunkIndex);
  }

  /// Create CANCEL_COMMAND frame (0x30)
  static DropFlowFrame createCancelCommand(String transferId) {
    return DropFlowFrame(
      type: ProtocolConstants.frameTypeCancelCommand,
      payload: Uint8List.fromList(utf8.encode(jsonEncode({'transferId': transferId}))),
    );
  }

  /// Create TRANSFER_COMPLETE frame (0xFF)
  static DropFlowFrame createTransferComplete(String transferId) {
    return DropFlowFrame(
      type: ProtocolConstants.frameTypeTransferComplete,
      payload: Uint8List.fromList(utf8.encode(jsonEncode({'transferId': transferId}))),
    );
  }
}
