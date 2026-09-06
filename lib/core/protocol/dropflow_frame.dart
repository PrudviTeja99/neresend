import 'dart:typed_data';
import '../constants/protocol_constants.dart';

/// Represents a framed protocol message on the wire
class DropFlowFrame {
  /// 1-byte frame type
  final int type;

  /// Raw frame payload bytes
  final Uint8List payload;

  const DropFlowFrame({
    required this.type,
    required this.payload,
  });

  int get payloadLength => payload.length;

  /// Encodes this frame into a 5-byte header + payload byte array
  Uint8List toWireBytes() {
    final length = payload.length;
    final buffer = Uint8List(ProtocolConstants.frameHeaderSize + length);
    final byteData = ByteData.sublistView(buffer);

    buffer[0] = type;
    byteData.setUint32(1, length, Endian.big);
    buffer.setRange(ProtocolConstants.frameHeaderSize, buffer.length, payload);

    return buffer;
  }
}

