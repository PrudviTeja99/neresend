import 'dart:typed_data';
import '../../core/protocol/dropflow_frame.dart';

/// Represents an authenticated, full-duplex communication channel
abstract class DropFlowTransport {
  /// Stream of incoming binary frames parsed from the wire
  Stream<DropFlowFrame> get incomingFrames;

  /// Send a control frame (Auth, Manifest, Accept, Decline, Pause, Resume, Cancel)
  Future<void> sendFrame(DropFlowFrame frame);

  /// Send a bulk binary chunk with backpressure flow control
  Future<void> sendDataChunk(int fileIdx, int chunkIdx, Uint8List chunkBytes);

  /// Gracefully close the transport connection
  Future<void> close();

  /// True if the transport is open and active
  bool get isConnected;
}

