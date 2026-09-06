import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:neresend/data/protocol/neresend_protocol_engine.dart';
import 'package:neresend/data/transports/webrtc/sas_generator.dart';
import 'package:neresend/data/transports/webrtc/webrtc_transport.dart';
import 'package:neresend/domain/models/device_identity.dart';
import 'package:neresend/domain/models/transfer_progress.dart';
import '../mocks/mock_rtc_data_channel.dart';

void main() {
  group('Remote WebRTC End-to-End File Transfer Over Dual DataChannels', () {
    late Directory tempSenderDir;
    late Directory tempReceiverDir;

    final senderIdentity = DeviceIdentity(
      deviceId: 'sender-remote-id',
      alias: 'Sender Alpha',
      publicKeyBase64: 'sender-pub-base64',
      fingerprint: 'AA:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF',
      publicKeyBytes: List.filled(32, 5),
    );

    final receiverIdentity = DeviceIdentity(
      deviceId: 'receiver-remote-id',
      alias: 'Receiver Beta',
      publicKeyBase64: 'receiver-pub-base64',
      fingerprint: 'FF:EE:DD:CC:BB:AA:99:88:77:66:55:44:33:22:11:00',
      publicKeyBytes: List.filled(32, 6),
    );

    setUp(() async {
      tempSenderDir =
          await Directory.systemTemp.createTemp('webrtc_sender_test_');
      tempReceiverDir =
          await Directory.systemTemp.createTemp('webrtc_receiver_test_');
    });

    tearDown(() async {
      if (await tempSenderDir.exists()) {
        await tempSenderDir.delete(recursive: true);
      }
      if (await tempReceiverDir.exists()) {
        await tempReceiverDir.delete(recursive: true);
      }
    });

    test(
        'Full WebRTC Dual-Channel transfer with SAS emojis and 64 KB sub-packet reassembly',
        () async {
      // 1. Setup paired mock DataChannels for 'control' (Stream 0) and 'data' (Stream 1)
      final controlPair =
          MockRtcDataChannel.createPair(label: 'control', id: 0);
      final dataPair = MockRtcDataChannel.createPair(label: 'data', id: 1);

      const sessionPin = '824 195';
      final sasString = SasGenerator.formatEmojis(
        localFingerprint: senderIdentity.fingerprint,
        remoteFingerprint: receiverIdentity.fingerprint,
        sessionPin: sessionPin,
      );

      // Verify SAS emoji string has 3 emojis
      expect(sasString.split(' ').length, 3);

      final senderTransport = WebRtcTransport(
        controlChannel: controlPair.channelA,
        dataChannel: dataPair.channelA,
        sasEmojis: sasString,
      );

      final receiverTransport = WebRtcTransport(
        controlChannel: controlPair.channelB,
        dataChannel: dataPair.channelB,
        sasEmojis: sasString,
      );

      // 2. Instantiate Protocol Engines (with isRemote = true for 1-4 MB remote chunks)
      final senderEngine = NeReSendProtocolEngine(
        localIdentity: senderIdentity,
        isRemote: true,
      );

      final receiverEngine = NeReSendProtocolEngine(
        localIdentity: receiverIdentity,
        isRemote: true,
      );

      receiverEngine.listenToTransport(receiverTransport);

      // 3. Create synthetic test file (800 KB, spanning multiple 64 KB sub-packets)
      final testFile = File('${tempSenderDir.path}/dataset_archive.tar.gz');
      final testBytes =
          Uint8List.fromList(List.generate(800000, (i) => (i * 13) % 256));
      await testFile.writeAsBytes(testBytes);
      final expectedSha256 = sha256.convert(testBytes).toString();

      // 4. Handle receiver incoming request and accept
      final requestAccepted = Completer<void>();
      receiverEngine.onIncomingRequest.listen((request) async {
        await receiverEngine.acceptTransfer(
            request.transferId, tempReceiverDir.path);
        requestAccepted.complete();
      });

      final senderCompleted = Completer<void>();
      senderEngine.onProgress.listen((p) {
        if (p.status == TransferStatus.completed) {
          if (!senderCompleted.isCompleted) {
            senderCompleted.complete();
          }
        }
      });

      // 5. Start sender transfer session
      final sendFuture =
          senderEngine.startSenderSession(senderTransport, [testFile]);

      await requestAccepted.future;
      await Future.wait([sendFuture, senderCompleted.future]);

      // 6. Verify received file on receiver disk is identical
      final receivedFile =
          File('${tempReceiverDir.path}/dataset_archive.tar.gz');
      expect(await receivedFile.exists(), isTrue);
      expect(await receivedFile.length(), equals(800000));

      final actualSha256 =
          sha256.convert(await receivedFile.readAsBytes()).toString();
      expect(actualSha256, equals(expectedSha256));

      // Cleanup
      await senderTransport.close();
      await receiverTransport.close();
      senderEngine.dispose();
      receiverEngine.dispose();
    });
  });
}
