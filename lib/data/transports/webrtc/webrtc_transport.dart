import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../core/constants/protocol_constants.dart';
import '../../../core/protocol/neresend_frame.dart';
import '../../../core/protocol/frame_writer.dart';
import '../../../domain/contracts/neresend_transport.dart';
import 'webrtc_backpressure_streamer.dart';

/// NeReSendTransport implementation over RFC 8831 Dual WebRTC DataChannels ('control' and 'data')
class WebRtcTransport implements NeReSendTransport {
  final RTCDataChannel controlChannel;
  final RTCDataChannel dataChannel;
  final RTCPeerConnection? peerConnection;
  final String sasEmojis;

  final StreamController<NeReSendFrame> _incomingFramesController =
      StreamController<NeReSendFrame>.broadcast();
  final WebRtcChunkReassembler _chunkReassembler = WebRtcChunkReassembler();

  bool _closed = false;

  WebRtcTransport({
    required this.controlChannel,
    required this.dataChannel,
    this.peerConnection,
    this.sasEmojis = '',
  }) {
    _initChannels();
  }

  void _initChannels() {
    // Control channel handles priority frames (Manifest, Accept, Pause, Resume, Cancel)
    controlChannel.onMessage = (RTCDataChannelMessage msg) {
      if (msg.isBinary && msg.binary.isNotEmpty) {
        try {
          final bytes = msg.binary;
          if (bytes.length < ProtocolConstants.frameHeaderSize) return;

          final byteData = ByteData.sublistView(bytes);
          final type = bytes[0];
          final length = byteData.getUint32(1, Endian.big);

          if (bytes.length >= ProtocolConstants.frameHeaderSize + length) {
            final payload = Uint8List.sublistView(
              bytes,
              ProtocolConstants.frameHeaderSize,
              ProtocolConstants.frameHeaderSize + length,
            );
            _incomingFramesController
                .add(NeReSendFrame(type: type, payload: payload));
          }
        } catch (e) {
          _incomingFramesController.addError(e);
        }
      }
    };

    // Data channel handles sub-packetized binary chunks (64 KB MTU)
    dataChannel.onMessage = (RTCDataChannelMessage msg) {
      if (msg.isBinary && msg.binary.isNotEmpty) {
        try {
          final completeChunk = _chunkReassembler.ingestSubPacket(msg.binary);
          if (completeChunk != null) {
            final frame = FrameWriter.createFileDataChunk(
              fileIndex: completeChunk.fileIndex,
              chunkIndex: completeChunk.chunkIndex,
              chunkData: completeChunk.chunkData,
            );
            _incomingFramesController.add(frame);
          }
        } catch (e) {
          _incomingFramesController.addError(e);
        }
      }
    };

    controlChannel.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelClosed) {
        close();
      }
    };

    dataChannel.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelClosed) {
        close();
      }
    };
  }

  @override
  Stream<NeReSendFrame> get incomingFrames => _incomingFramesController.stream;

  @override
  bool get isConnected => !_closed;

  @override
  Future<void> sendFrame(NeReSendFrame frame) async {
    if (_closed) throw StateError('WebRtcTransport is closed');

    if (frame.type == ProtocolConstants.frameTypeFileDataChunk) {
      final parsed = FrameWriter.parseFileDataChunk(frame.payload);
      await sendDataChunk(
          parsed.fileIndex, parsed.chunkIndex, parsed.chunkData);
    } else {
      // Send over priority control channel (SCTP Stream 0)
      controlChannel
          .send(RTCDataChannelMessage.fromBinary(frame.toWireBytes()));
    }
  }

  @override
  Future<void> sendDataChunk(
      int fileIdx, int chunkIdx, Uint8List chunkBytes) async {
    if (_closed) throw StateError('WebRtcTransport is closed');

    final packets = WebRtcBackpressureStreamer.sliceChunk(
      fileIndex: fileIdx,
      chunkIndex: chunkIdx,
      chunkBytes: chunkBytes,
    );

    for (final packet in packets) {
      // Non-blocking backpressure flow control check
      final buffered = dataChannel.bufferedAmount ?? 0;
      if (buffered > WebRtcBackpressureStreamer.maxBufferedBytes) {
        final completer = Completer<void>();
        void Function(int current)? prevCallback;
        prevCallback = dataChannel.onBufferedAmountLow;

        dataChannel.onBufferedAmountLow = (current) {
          if (!completer.isCompleted) {
            completer.complete();
          }
          if (prevCallback != null) prevCallback(current);
        };

        // Fallback safety timeout if low threshold event isn't fired
        await completer.future.timeout(
          const Duration(milliseconds: 500),
          onTimeout: () {},
        );
      }

      dataChannel.send(RTCDataChannelMessage.fromBinary(packet));
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;

    _chunkReassembler.clear();

    try {
      await controlChannel.close();
    } catch (_) {}

    try {
      await dataChannel.close();
    } catch (_) {}

    try {
      await peerConnection?.close();
      await peerConnection?.dispose();
    } catch (_) {}

    if (!_incomingFramesController.isClosed) {
      await _incomingFramesController.close();
    }
  }
}
