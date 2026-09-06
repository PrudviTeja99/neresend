/// Protocol Invariants, Magic Bytes, Frame Types, and Limits for DropFlow
class ProtocolConstants {
  ProtocolConstants._();

  // Invariant Budgets
  static const int maxManifestBytes = 512 * 1024; // 524,288 Bytes (512 KB)
  static const int maxFramePayloadSize = 9 * 1024 * 1024 + 32 * 1024; // ~9.03 MB (Max 8MB Chunk + Framing)
  static const int webRtcDataChannelMtu = 64 * 1024; // 64 KB Wire Packet MTU for libwebrtc
  static const int webRtcBackpressureThreshold = 1024 * 1024; // 1 MB Backpressure Low Threshold

  // Frame Header Byte Size: [Type: 1B] [Size: 4B]
  static const int frameHeaderSize = 5;

  // Frame Type Identifiers
  static const int frameTypeAuthHandshake = 0x00;
  static const int frameTypeManifestRequest = 0x01;
  static const int frameTypeAcceptResponse = 0x02;
  static const int frameTypeDeclineResponse = 0x03;
  static const int frameTypeManifestPart = 0x04;
  static const int frameTypeManifestEnd = 0x05;
  static const int frameTypeFileDataChunk = 0x10;
  static const int frameTypePauseCommand = 0x20;
  static const int frameTypeResumeCommand = 0x21;
  static const int frameTypeRetryChunk = 0x22;
  static const int frameTypeCancelCommand = 0x30;
  static const int frameTypeTransferComplete = 0xFF;

  // Decline Reason Codes
  static const String declineUserRejected = 'USER_DECLINED';
  static const String declineInsufficientStorage = 'INSUFFICIENT_STORAGE';
  static const String declineProtocolMismatch = 'PROTOCOL_MISMATCH';
  static const String declineSecurityFailed = 'SECURITY_AUTH_FAILED';
}

