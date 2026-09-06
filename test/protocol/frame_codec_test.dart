import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:neresend/core/constants/protocol_constants.dart';
import 'package:neresend/core/errors/exceptions.dart';
import 'package:neresend/core/protocol/neresend_frame.dart';
import 'package:neresend/core/protocol/frame_reader.dart';
import 'package:neresend/core/protocol/frame_writer.dart';

void main() {
  group('DropFlow Frame & Codec Tests', () {
    test('NeReSendFrame correctly encodes 5-byte header into wire bytes', () {
      final payload = Uint8List.fromList([1, 2, 3, 4, 5]);
      final frame = NeReSendFrame(type: ProtocolConstants.frameTypeManifestRequest, payload: payload);
      final wireBytes = frame.toWireBytes();

      expect(wireBytes.length, equals(5 + 5));
      expect(wireBytes[0], equals(ProtocolConstants.frameTypeManifestRequest));
      
      final byteData = ByteData.sublistView(wireBytes);
      expect(byteData.getUint32(1, Endian.big), equals(5));
      expect(wireBytes.sublist(5), equals([1, 2, 3, 4, 5]));
    });

    test('FrameReader parses single intact frame', () async {
      const frameReader = FrameReader();
      final source = StreamController<List<int>>();
      final stream = source.stream.transform(frameReader);

      final payload = Uint8List.fromList([10, 20, 30, 40]);
      final wireBytes = NeReSendFrame(type: 0x10, payload: payload).toWireBytes();

      final framesFuture = stream.first;
      source.add(wireBytes);
      await source.close();

      final frame = await framesFuture;
      expect(frame.type, equals(0x10));
      expect(frame.payload, equals(payload));
    });

    test('FrameReader handles highly fragmented byte streams (1 byte per packet)', () async {
      const frameReader = FrameReader();
      final source = StreamController<List<int>>();
      final stream = source.stream.transform(frameReader);

      final payload = Uint8List.fromList(List.generate(100, (i) => i % 256));
      final wireBytes = NeReSendFrame(type: 0x01, payload: payload).toWireBytes();

      final completer = Completer<NeReSendFrame>();
      stream.listen(completer.complete);

      // Feed byte-by-byte
      for (final byte in wireBytes) {
        source.add([byte]);
        await Future.delayed(Duration.zero);
      }
      await source.close();

      final frame = await completer.future;
      expect(frame.type, equals(0x01));
      expect(frame.payload, equals(payload));
    });

    test('FrameReader handles multiple concatenated frames in one buffer', () async {
      const frameReader = FrameReader();
      final source = StreamController<List<int>>();
      final stream = source.stream.transform(frameReader);

      final f1 = NeReSendFrame(type: 0x01, payload: Uint8List.fromList([1, 2]));
      final f2 = NeReSendFrame(type: 0x02, payload: Uint8List.fromList([3, 4, 5]));
      final f3 = NeReSendFrame(type: 0x03, payload: Uint8List.fromList([6]));

      final concatenated = Uint8List.fromList([
        ...f1.toWireBytes(),
        ...f2.toWireBytes(),
        ...f3.toWireBytes(),
      ]);

      final frames = <NeReSendFrame>[];
      stream.listen(frames.add);

      source.add(concatenated);
      await source.close();

      expect(frames.length, equals(3));
      expect(frames[0].type, equals(0x01));
      expect(frames[0].payload, equals([1, 2]));
      expect(frames[1].type, equals(0x02));
      expect(frames[1].payload, equals([3, 4, 5]));
      expect(frames[2].type, equals(0x03));
      expect(frames[2].payload, equals([6]));
    });

    test('FrameReader rejects oversized frame exceeding maxPayloadSize', () async {
      const smallMax = 100;
      const frameReader = FrameReader(maxPayloadSize: smallMax);
      final source = StreamController<List<int>>();
      final stream = source.stream.transform(frameReader);

      // Frame with length 200 (violating 100 byte limit)
      final oversizedBytes = Uint8List(5);
      oversizedBytes[0] = 0x10;
      ByteData.sublistView(oversizedBytes).setUint32(1, 200, Endian.big);

      Object? capturedError;
      stream.listen(
        (_) {},
        onError: (e) => capturedError = e,
      );

      source.add(oversizedBytes);
      await source.close();

      expect(capturedError, isA<ProtocolException>());
    });

    test('FrameWriter encodes and parses FILE_DATA_CHUNK round-trip', () {
      final chunkBytes = Uint8List.fromList([100, 101, 102, 103, 104]);
      final frame = FrameWriter.createFileDataChunk(
        fileIndex: 42,
        chunkIndex: 1005,
        chunkData: chunkBytes,
      );

      expect(frame.type, equals(ProtocolConstants.frameTypeFileDataChunk));
      final parsed = FrameWriter.parseFileDataChunk(frame.payload);

      expect(parsed.fileIndex, equals(42));
      expect(parsed.chunkIndex, equals(1005));
      expect(parsed.chunkData, equals(chunkBytes));
    });

    test('FrameWriter encodes and parses RETRY_CHUNK round-trip', () {
      final frame = FrameWriter.createRetryChunk(fileIndex: 7, chunkIndex: 88);
      expect(frame.type, equals(ProtocolConstants.frameTypeRetryChunk));

      final parsed = FrameWriter.parseRetryChunk(frame.payload);
      expect(parsed.fileIndex, equals(7));
      expect(parsed.chunkIndex, equals(88));
    });
  });
}
