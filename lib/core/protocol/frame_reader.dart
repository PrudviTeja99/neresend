import 'dart:async';
import 'dart:typed_data';
import '../constants/protocol_constants.dart';
import '../errors/exceptions.dart';
import 'dropflow_frame.dart';

/// StreamTransformer that decodes a continuous raw byte stream into DropFlowFrame instances.
///
/// Handles TCP/WebRTC packet fragmentation, multi-frame bursts in a single buffer,
/// and enforces the ProtocolConstants.maxFramePayloadSize safety invariant.
class FrameReader extends StreamTransformerBase<List<int>, DropFlowFrame> {
  final int maxPayloadSize;

  const FrameReader({
    this.maxPayloadSize = ProtocolConstants.maxFramePayloadSize,
  });

  @override
  Stream<DropFlowFrame> bind(Stream<List<int>> stream) {
    return Stream<DropFlowFrame>.eventTransformed(
      stream,
      (sink) => _FrameReaderSink(sink, maxPayloadSize),
    );
  }
}

class _FrameReaderSink implements EventSink<List<int>> {
  final EventSink<DropFlowFrame> _outputSink;
  final int _maxPayloadSize;
  final BytesBuilder _buffer = BytesBuilder(copy: false);

  _FrameReaderSink(this._outputSink, this._maxPayloadSize);

  @override
  void add(List<int> data) {
    if (data.isEmpty) return;
    _buffer.add(data);

    // Process all complete frames currently available in buffer
    while (true) {
      final currentBytes = _buffer.toBytes();
      if (currentBytes.length < ProtocolConstants.frameHeaderSize) {
        // Re-buffer the unconsumed bytes and wait for more data
        _buffer.clear();
        _buffer.add(currentBytes);
        break;
      }

      final byteData = ByteData.sublistView(currentBytes);
      final frameType = currentBytes[0];
      final payloadLength = byteData.getUint32(1, Endian.big);

      // Invariant Check: Memory exhaustion guard
      if (payloadLength < 0 || payloadLength > _maxPayloadSize) {
        _buffer.clear();
        _outputSink.addError(
          ProtocolException(
            'Frame payload length $payloadLength exceeds maximum allowed limit $_maxPayloadSize (Opcode: 0x${frameType.toRadixString(16).padLeft(2, '0')})',
          ),
        );
        return;
      }

      final totalFrameSize = ProtocolConstants.frameHeaderSize + payloadLength;
      if (currentBytes.length < totalFrameSize) {
        // Need more bytes to complete payload
        _buffer.clear();
        _buffer.add(currentBytes);
        break;
      }

      // Extract complete frame payload
      final payload = Uint8List.sublistView(
        currentBytes,
        ProtocolConstants.frameHeaderSize,
        totalFrameSize,
      );

      _outputSink.add(DropFlowFrame(type: frameType, payload: payload));

      // Retain remainder
      final remainder = Uint8List.sublistView(currentBytes, totalFrameSize);
      _buffer.clear();
      if (remainder.isNotEmpty) {
        _buffer.add(remainder);
      } else {
        break;
      }
    }
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _outputSink.addError(error, stackTrace);
  }

  @override
  void close() {
    _buffer.clear();
    _outputSink.close();
  }
}
