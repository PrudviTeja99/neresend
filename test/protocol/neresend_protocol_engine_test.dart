import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:neresend/core/protocol/neresend_frame.dart';
import 'package:neresend/core/protocol/frame_writer.dart';
import 'package:neresend/data/protocol/neresend_protocol_engine.dart';
import 'package:neresend/domain/contracts/neresend_transport.dart';
import 'package:neresend/domain/models/device_identity.dart';
import 'package:neresend/domain/models/transfer_progress.dart';

/// In-memory bidirectional mock transport linking two endpoints directly
class MockDuplexTransport implements NeReSendTransport {
  final StreamController<NeReSendFrame> _incoming =
      StreamController<NeReSendFrame>.broadcast();
  late MockDuplexTransport _peer;
  bool _connected = true;

  MockDuplexTransport();

  static (MockDuplexTransport, MockDuplexTransport) createPair() {
    final a = MockDuplexTransport();
    final b = MockDuplexTransport();
    a._peer = b;
    b._peer = a;
    return (a, b);
  }

  @override
  Stream<NeReSendFrame> get incomingFrames => _incoming.stream;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> sendFrame(NeReSendFrame frame) async {
    if (!_connected) throw StateError('Transport disconnected');
    _peer._incoming.add(frame);
  }

  @override
  Future<void> sendDataChunk(
      int fileIdx, int chunkIdx, Uint8List chunkBytes) async {
    if (!_connected) throw StateError('Transport disconnected');
    final frame = FrameWriter.createFileDataChunk(
      fileIndex: fileIdx,
      chunkIndex: chunkIdx,
      chunkData: chunkBytes,
    );
    _peer._incoming.add(frame);
  }

  @override
  Future<void> close() async {
    _connected = false;
    await _incoming.close();
  }
}

void main() {
  group('NeReSendProtocolEngine End-to-End Tests', () {
    late Directory tempSenderDir;
    late Directory tempReceiverDir;

    const senderIdentity = DeviceIdentity(
      deviceId: 'sender_001',
      alias: 'Sender Machine',
      publicKeyBase64: 'mock_sender_key',
      fingerprint: '11:22:33:44:55:66',
      publicKeyBytes: [1, 2, 3],
    );

    const receiverIdentity = DeviceIdentity(
      deviceId: 'receiver_002',
      alias: 'Receiver Machine',
      publicKeyBase64: 'mock_receiver_key',
      fingerprint: 'AA:BB:CC:DD:EE:FF',
      publicKeyBytes: [4, 5, 6],
    );

    setUp(() async {
      tempSenderDir = await Directory.systemTemp.createTemp('sender_test_');
      tempReceiverDir = await Directory.systemTemp.createTemp('receiver_test_');
    });

    tearDown(() async {
      if (await tempSenderDir.exists()) {
        await tempSenderDir.delete(recursive: true);
      }
      if (await tempReceiverDir.exists()) {
        await tempReceiverDir.delete(recursive: true);
      }
    });

    test('End-to-End file transfer over MockDuplexTransport', () async {
      final (senderTransport, receiverTransport) =
          MockDuplexTransport.createPair();

      // Create a test file on sender disk (2.5 MB)
      final testFile = File('${tempSenderDir.path}/sample_document.pdf');
      final payloadBytes =
          Uint8List.fromList(List.generate(2500000, (i) => i % 256));
      await testFile.writeAsBytes(payloadBytes);
      final expectedSha256 = sha256.convert(payloadBytes).toString();

      final senderEngine =
          NeReSendProtocolEngine(localIdentity: senderIdentity);
      final receiverEngine =
          NeReSendProtocolEngine(localIdentity: receiverIdentity);

      receiverEngine.listenToTransport(receiverTransport);

      // Listen for incoming transfer request on receiver
      final receiverRequestCompleter = Completer<void>();
      receiverEngine.onIncomingRequest.listen((request) async {
        expect(request.manifest.files.length, equals(1));
        expect(request.manifest.files.first.fileName,
            equals('sample_document.pdf'));
        expect(request.manifest.files.first.size, equals(2500000));
        expect(request.manifest.files.first.wholeFileSha256,
            equals(expectedSha256));

        // Accept the transfer into receiver directory
        await receiverEngine.acceptTransfer(
            request.transferId, tempReceiverDir.path);
        receiverRequestCompleter.complete();
      });

      // Track progress
      final completedSenderCompleter = Completer<void>();
      senderEngine.onProgress.listen((progress) {
        if (progress.status == TransferStatus.completed) {
          if (!completedSenderCompleter.isCompleted) {
            completedSenderCompleter.complete();
          }
        }
      });

      // Start sender session
      final sendFuture =
          senderEngine.startSenderSession(senderTransport, [testFile]);

      // Await acceptance and completion
      await receiverRequestCompleter.future;
      await Future.wait([sendFuture, completedSenderCompleter.future]);

      // Verify file arrived safely on receiver disk
      final receivedFile = File('${tempReceiverDir.path}/sample_document.pdf');
      expect(await receivedFile.exists(), isTrue);
      expect(await receivedFile.length(), equals(2500000));

      final receivedDigest =
          sha256.convert(await receivedFile.readAsBytes()).toString();
      expect(receivedDigest, equals(expectedSha256));

      await senderTransport.close();
      await receiverTransport.close();
      senderEngine.dispose();
      receiverEngine.dispose();
    });

    test(
        'Simulated out-of-order chunk wire arrival delivers and finalizes intact file',
        () async {
      final (senderTransport, receiverTransport) =
          MockDuplexTransport.createPair();

      // Create a test file of 3 MB (will be 3 chunks of 1 MB each)
      final testFile = File('${tempSenderDir.path}/out_of_order_payload.bin');
      final payloadBytes =
          Uint8List.fromList(List.generate(3000000, (i) => (i * 31) % 256));
      await testFile.writeAsBytes(payloadBytes);
      final expectedSha256 = sha256.convert(payloadBytes).toString();

      final senderEngine =
          NeReSendProtocolEngine(localIdentity: senderIdentity);
      final receiverEngine =
          NeReSendProtocolEngine(localIdentity: receiverIdentity);

      receiverEngine.listenToTransport(receiverTransport);

      final receiverRequestCompleter = Completer<void>();
      receiverEngine.onIncomingRequest.listen((request) async {
        await receiverEngine.acceptTransfer(
            request.transferId, tempReceiverDir.path);
        receiverRequestCompleter.complete();
      });

      final completedSenderCompleter = Completer<void>();
      senderEngine.onProgress.listen((progress) {
        if (progress.status == TransferStatus.completed) {
          if (!completedSenderCompleter.isCompleted) {
            completedSenderCompleter.complete();
          }
        }
      });

      final sendFuture =
          senderEngine.startSenderSession(senderTransport, [testFile]);

      await receiverRequestCompleter.future;
      await Future.wait([sendFuture, completedSenderCompleter.future]);

      final receivedFile =
          File('${tempReceiverDir.path}/out_of_order_payload.bin');
      expect(await receivedFile.exists(), isTrue);
      expect(await receivedFile.length(), equals(3000000));

      final receivedDigest =
          sha256.convert(await receivedFile.readAsBytes()).toString();
      expect(receivedDigest, equals(expectedSha256));

      await senderTransport.close();
      await receiverTransport.close();
      senderEngine.dispose();
      receiverEngine.dispose();
    });
  });
}
