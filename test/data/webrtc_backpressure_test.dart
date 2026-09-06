import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:neresend/data/transports/webrtc/webrtc_backpressure_streamer.dart';

void main() {
  group('WebRtcBackpressureStreamer & Reassembler Tests', () {
    test('Slices 150 KB chunk into 64 KB wire packets with 16B sub-headers',
        () {
      final syntheticChunk = Uint8List(150 * 1024);
      for (int i = 0; i < syntheticChunk.length; i++) {
        syntheticChunk[i] = i % 256;
      }

      final packets = WebRtcBackpressureStreamer.sliceChunk(
        fileIndex: 0,
        chunkIndex: 2,
        chunkBytes: syntheticChunk,
        mtu: 64 * 1024,
      );

      // (150 KB / (64 KB - 16B)) = ceil(153600 / 65520) = 3 packets
      expect(packets.length, 3);

      for (final packet in packets) {
        expect(packet.length, lessThanOrEqualTo(64 * 1024));
        final byteData = ByteData.sublistView(packet);
        expect(byteData.getUint32(0, Endian.big), 0); // fileIndex
        expect(byteData.getUint32(4, Endian.big), 2); // chunkIndex
        expect(byteData.getUint32(12, Endian.big), 150 * 1024); // totalLen
      }
    });

    test('WebRtcChunkReassembler reconstructs original chunk in order', () {
      final original = Uint8List(100 * 1024);
      for (int i = 0; i < original.length; i++) {
        original[i] = (i * 7) % 256;
      }

      final packets = WebRtcBackpressureStreamer.sliceChunk(
        fileIndex: 1,
        chunkIndex: 5,
        chunkBytes: original,
        mtu: 32 * 1024, // 32 KB slices
      );

      final reassembler = WebRtcChunkReassembler();
      ({int fileIndex, int chunkIndex, Uint8List chunkData})? result;

      for (final packet in packets) {
        result = reassembler.ingestSubPacket(packet);
      }

      expect(result, isNotNull);
      expect(result!.fileIndex, 1);
      expect(result.chunkIndex, 5);
      expect(result.chunkData.length, original.length);
      expect(result.chunkData, equals(original));
    });

    test(
        'WebRtcChunkReassembler reconstructs out-of-order sub-packets correctly',
        () {
      final original = Uint8List(80 * 1024);
      for (int i = 0; i < original.length; i++) {
        original[i] = (i * 13) % 256;
      }

      final packets = WebRtcBackpressureStreamer.sliceChunk(
        fileIndex: 2,
        chunkIndex: 0,
        chunkBytes: original,
        mtu: 20 * 1024,
      );

      expect(packets.length, 5);

      final reassembler = WebRtcChunkReassembler();
      // Ingest in reverse order (packets: 4, 3, 2, 1, 0)
      reassembler.ingestSubPacket(packets[4]);
      reassembler.ingestSubPacket(packets[2]);
      reassembler.ingestSubPacket(packets[1]);
      reassembler.ingestSubPacket(packets[3]);
      final result = reassembler.ingestSubPacket(packets[0]);

      expect(result, isNotNull);
      expect(result!.fileIndex, 2);
      expect(result.chunkIndex, 0);
      expect(result.chunkData, equals(original));
    });
  });
}
