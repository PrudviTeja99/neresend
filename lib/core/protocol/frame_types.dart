import '../constants/protocol_constants.dart';

/// Strongly-typed frame identifiers mapped to protocol byte opcodes
enum FrameType {
  authHandshake(ProtocolConstants.frameTypeAuthHandshake),
  manifestRequest(ProtocolConstants.frameTypeManifestRequest),
  acceptResponse(ProtocolConstants.frameTypeAcceptResponse),
  declineResponse(ProtocolConstants.frameTypeDeclineResponse),
  manifestPart(ProtocolConstants.frameTypeManifestPart),
  manifestEnd(ProtocolConstants.frameTypeManifestEnd),
  fileDataChunk(ProtocolConstants.frameTypeFileDataChunk),
  pauseCommand(ProtocolConstants.frameTypePauseCommand),
  resumeCommand(ProtocolConstants.frameTypeResumeCommand),
  retryChunk(ProtocolConstants.frameTypeRetryChunk),
  cancelCommand(ProtocolConstants.frameTypeCancelCommand),
  transferComplete(ProtocolConstants.frameTypeTransferComplete);

  final int opcode;
  const FrameType(this.opcode);

  static FrameType? fromOpcode(int opcode) {
    for (final type in FrameType.values) {
      if (type.opcode == opcode) return type;
    }
    return null;
  }
}
