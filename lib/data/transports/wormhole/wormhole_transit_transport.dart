import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../../core/protocol/frame_reader.dart';
import '../../../core/protocol/frame_writer.dart';
import '../../../core/protocol/neresend_frame.dart';
import '../../../domain/contracts/neresend_transport.dart';

/// Full-duplex transport wrapping a connected Magic Wormhole transit relay socket
class WormholeTransitTransport implements NeReSendTransport {
  final Socket _socket;
  final Stream<List<int>> _byteStream;
  final String sideId;
  final String pin;
  final String remoteFingerprint;
  final String localFingerprint;
  final String sasEmojis;

  final StreamController<NeReSendFrame> _frameController =
      StreamController<NeReSendFrame>.broadcast();
  StreamSubscription<NeReSendFrame>? _frameSubscription;
  bool _closed = false;

  WormholeTransitTransport({
    required Socket socket,
    required Stream<List<int>> byteStream,
    required this.sideId,
    required this.pin,
    required this.remoteFingerprint,
    required this.localFingerprint,
    required this.sasEmojis,
  })  : _socket = socket,
        _byteStream = byteStream {
    _frameSubscription = _byteStream.transform(const FrameReader()).listen(
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
    if (_closed) throw StateError('WormholeTransitTransport is closed');
    _socket.add(frame.toWireBytes());
    await _socket.flush();
  }

  @override
  Future<void> sendDataChunk(
      int fileIdx, int chunkIdx, Uint8List chunkBytes) async {
    if (_closed) throw StateError('WormholeTransitTransport is closed');
    final frame = FrameWriter.createFileDataChunk(
      fileIndex: fileIdx,
      chunkIndex: chunkIdx,
      chunkData: chunkBytes,
    );
    _socket.add(frame.toWireBytes());
    await _socket.flush();
  }

  @override
  Future<void> flush() async {
    if (_closed) return;
    try {
      await _socket.flush();
    } catch (_) {}
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _frameSubscription?.cancel();
    try {
      await _socket.close();
    } catch (_) {}
    _socket.destroy();
    if (!_frameController.isClosed) {
      await _frameController.close();
    }
  }
}
