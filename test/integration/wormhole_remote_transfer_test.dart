import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:neresend/data/protocol/neresend_protocol_engine.dart';
import 'package:neresend/data/transports/wormhole/wormhole_connection_manager.dart';
import 'package:neresend/domain/models/device_identity.dart';
import 'package:neresend/domain/models/transfer_progress.dart';

import '../data/wormhole_transit_transport_test.dart';

void main() {
  group('Wormhole Remote End-to-End File Transfer Over Transit Relay', () {
    late Directory tempSenderDir;
    late Directory tempReceiverDir;
    late FakeTransitRelayServer fakeRelay;
    late int relayPort;

    final senderIdentity = DeviceIdentity(
      deviceId: 'sender-wormhole-id',
      alias: 'Linux Desktop',
      publicKeyBase64: 'sender-pub-base64',
      fingerprint: 'AA:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF',
      publicKeyBytes: List.filled(32, 5),
    );

    final receiverIdentity = DeviceIdentity(
      deviceId: 'receiver-wormhole-id',
      alias: 'Android Phone',
      publicKeyBase64: 'receiver-pub-base64',
      fingerprint: 'FF:EE:DD:CC:BB:AA:99:88:77:66:55:44:33:22:11:00',
      publicKeyBytes: List.filled(32, 6),
    );

    setUp(() async {
      tempSenderDir =
          await Directory.systemTemp.createTemp('wormhole_sender_test_');
      tempReceiverDir =
          await Directory.systemTemp.createTemp('wormhole_receiver_test_');
      fakeRelay = FakeTransitRelayServer();
      relayPort = await fakeRelay.start();
    });

    tearDown(() async {
      await fakeRelay.stop();
      if (await tempSenderDir.exists()) {
        await tempSenderDir.delete(recursive: true);
      }
      if (await tempReceiverDir.exists()) {
        await tempReceiverDir.delete(recursive: true);
      }
    });

    test(
        'Full file transfer over Wormhole transit relay with SHA-256 verification',
        () async {
      const pin = '492 810';

      final hostManager = WormholeConnectionManager(
        transitHost: '127.0.0.1',
        transitPort: relayPort,
      );
      final clientManager = WormholeConnectionManager(
        transitHost: '127.0.0.1',
        transitPort: relayPort,
      );

      // 1. Host and client connect to the transit relay
      final hostFuture = hostManager.connectAndRendezvous(
        pin: pin,
        localFingerprint: receiverIdentity.fingerprint,
        remoteFingerprint: senderIdentity.fingerprint,
        isHost: true,
        timeout: const Duration(seconds: 5),
      );

      final clientFuture = clientManager.connectAndRendezvous(
        pin: pin,
        localFingerprint: senderIdentity.fingerprint,
        remoteFingerprint: receiverIdentity.fingerprint,
        isHost: false,
        timeout: const Duration(seconds: 5),
      );

      final transports = await Future.wait([hostFuture, clientFuture]);
      final receiverTransport = transports[0];
      final senderTransport = transports[1];

      expect(receiverTransport.isConnected, isTrue);
      expect(senderTransport.isConnected, isTrue);
      expect(receiverTransport.sasEmojis, equals(senderTransport.sasEmojis));

      // 2. Instantiate Protocol Engines
      final senderEngine = NeReSendProtocolEngine(
        localIdentity: senderIdentity,
        isRemote: true,
      );

      final receiverEngine = NeReSendProtocolEngine(
        localIdentity: receiverIdentity,
        isRemote: true,
      );

      receiverEngine.listenToTransport(receiverTransport);

      // 3. Create test file (250 KB)
      final testFile = File('${tempSenderDir.path}/holiday_photo.jpg');
      final testBytes =
          Uint8List.fromList(List.generate(250000, (i) => (i * 17 + 42) % 256));
      await testFile.writeAsBytes(testBytes);
      final expectedSha256 = sha256.convert(testBytes).toString();

      // 4. Auto-accept incoming request on receiver
      final receiverDoneCompleter = Completer<void>();
      receiverEngine.onIncomingRequest.listen((request) async {
        await receiverEngine.acceptTransfer(
            request.transferId, tempReceiverDir.path);
      });

      receiverEngine.onProgress.listen((progress) {
        if (progress.status == TransferStatus.completed) {
          if (!receiverDoneCompleter.isCompleted) {
            receiverDoneCompleter.complete();
          }
        }
      });

      // 5. Sender starts session
      final sendFuture =
          senderEngine.startSenderSession(senderTransport, [testFile]);

      // 6. Await completion
      await Future.wait([sendFuture, receiverDoneCompleter.future]);

      final savedFile = File('${tempReceiverDir.path}/holiday_photo.jpg');
      expect(await savedFile.exists(), isTrue);

      final savedBytes = await savedFile.readAsBytes();
      expect(savedBytes.length, equals(testBytes.length));

      final actualSha256 = sha256.convert(savedBytes).toString();
      expect(actualSha256, equals(expectedSha256));

      await receiverTransport.close();
      await senderTransport.close();
    });
  });
}
