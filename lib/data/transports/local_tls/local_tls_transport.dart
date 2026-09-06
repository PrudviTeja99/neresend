import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../../core/protocol/neresend_frame.dart';
import '../../../core/protocol/frame_reader.dart';
import '../../../core/protocol/frame_writer.dart';
import '../../../domain/contracts/neresend_transport.dart';
import 'auth_handshake_handler.dart';

/// Concrete NeReSendTransport implementation wrapping an authenticated TLS 1.3 SecureSocket
class LocalTlsTransport implements NeReSendTransport {
  final SecureSocket _socket;
  AuthResult? authResult;
  final StreamController<NeReSendFrame> _frameController = StreamController<NeReSendFrame>.broadcast();
  StreamSubscription<NeReSendFrame>? _rawSubscription;
  bool _closed = false;

  LocalTlsTransport({
    required SecureSocket socket,
    this.authResult,
  }) : _socket = socket {
    _rawSubscription = _socket.cast<List<int>>().transform(const FrameReader()).listen(
      _frameController.add,
      onError: _frameController.addError,
      onDone: () {
        _closed = true;
        _frameController.close();
      },
      cancelOnError: false,
    );
  }

  @override
  Stream<NeReSendFrame> get incomingFrames => _frameController.stream;

  @override
  bool get isConnected => !_closed;

  @override
  Future<void> sendFrame(NeReSendFrame frame) async {
    if (_closed) throw StateError('LocalTlsTransport is closed');
    _socket.add(frame.toWireBytes());
    await _socket.flush();
  }

  @override
  Future<void> sendDataChunk(int fileIdx, int chunkIdx, Uint8List chunkBytes) async {
    if (_closed) throw StateError('LocalTlsTransport is closed');
    final frame = FrameWriter.createFileDataChunk(
      fileIndex: fileIdx,
      chunkIndex: chunkIdx,
      chunkData: chunkBytes,
    );
    _socket.add(frame.toWireBytes());
    await _socket.flush();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _rawSubscription?.cancel();
    await _socket.close();
    _socket.destroy();
    if (!_frameController.isClosed) {
      await _frameController.close();
    }
  }
}
