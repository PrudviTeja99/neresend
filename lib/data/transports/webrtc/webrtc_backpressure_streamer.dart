import 'dart:math' as math;
import 'dart:typed_data';

/// Sub-packetization framing and reassembly for WebRTC DataChannels (64 KB MTU)
class WebRtcBackpressureStreamer {
  static const int maxDataChannelPacketSize = 64 * 1024; // 64 KB MTU
  static const int maxBufferedBytes = 1024 * 1024; // 1 MB Backpressure Low Threshold
  static const int subHeaderSize = 16; // [4B FileIdx] [4B ChunkIdx] [4B SubOffset] [4B TotalLen]

  WebRtcBackpressureStreamer._();

  /// Slices an application-level chunk (1–4 MB) into 64 KB MTU sub-packets
  static List<Uint8List> sliceChunk({
    required int fileIndex,
    required int chunkIndex,
    required Uint8List chunkBytes,
    int mtu = maxDataChannelPacketSize,
  }) {
    final payloadSliceSize = mtu - subHeaderSize;
    final totalLen = chunkBytes.length;
    final packets = <Uint8List>[];

    int offset = 0;
    while (offset < totalLen) {
      final sliceEnd = math.min(offset + payloadSliceSize, totalLen);
      final slice = Uint8List.sublistView(chunkBytes, offset, sliceEnd);

      final packet = Uint8List(subHeaderSize + slice.length);
      final byteData = ByteData.sublistView(packet);

      byteData.setUint32(0, fileIndex, Endian.big);
      byteData.setUint32(4, chunkIndex, Endian.big);
      byteData.setUint32(8, offset, Endian.big);
      byteData.setUint32(12, totalLen, Endian.big);
      packet.setRange(subHeaderSize, packet.length, slice);

      packets.add(packet);
      offset = sliceEnd;
    }

    return packets;
  }
}

/// Reassembles 64 KB sub-packets into full application-level chunk buffers
class WebRtcChunkReassembler {
  final Map<String, Uint8List> _activeBuffers = {};
  final Map<String, int> _receivedBytesMap = {};

  /// Ingest a sub-packet; returns completed chunk tuple when all slices arrive
  ({int fileIndex, int chunkIndex, Uint8List chunkData})? ingestSubPacket(Uint8List packet) {
    if (packet.length < WebRtcBackpressureStreamer.subHeaderSize) {
      throw const FormatException('Sub-packet header too short');
    }

    final byteData = ByteData.sublistView(packet);
    final fileIndex = byteData.getUint32(0, Endian.big);
    final chunkIndex = byteData.getUint32(4, Endian.big);
    final subOffset = byteData.getUint32(8, Endian.big);
    final totalChunkLen = byteData.getUint32(12, Endian.big);

    final slice = Uint8List.sublistView(packet, WebRtcBackpressureStreamer.subHeaderSize);

    final key = '$fileIndex:$chunkIndex';
    final buffer = _activeBuffers.putIfAbsent(key, () => Uint8List(totalChunkLen));

    buffer.setRange(subOffset, subOffset + slice.length, slice);

    final updatedReceived = (_receivedBytesMap[key] ?? 0) + slice.length;
    _receivedBytesMap[key] = updatedReceived;

    if (updatedReceived >= totalChunkLen) {
      _activeBuffers.remove(key);
      _receivedBytesMap.remove(key);
      return (
        fileIndex: fileIndex,
        chunkIndex: chunkIndex,
        chunkData: buffer,
      );
    }

    return null;
  }

  void clear() {
    _activeBuffers.clear();
    _receivedBytesMap.clear();
  }
}
