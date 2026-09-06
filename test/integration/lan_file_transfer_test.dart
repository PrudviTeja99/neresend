import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:dropflow/data/protocol/dropflow_protocol_engine.dart';
import 'package:dropflow/data/services/identity_service.dart';
import 'package:dropflow/data/transports/local_tls/local_tls_client.dart';
import 'package:dropflow/data/transports/local_tls/local_tls_server.dart';
import 'package:dropflow/domain/contracts/secure_storage_port.dart';
import 'package:dropflow/domain/models/device_identity.dart';
import 'package:dropflow/domain/models/transfer_progress.dart';

class InMemorySecureStorage implements SecureStoragePort {
  final Map<String, String> _storage = {};

  @override
  Future<String?> read(String key) async => _storage[key];

  @override
  Future<void> write(String key, String value) async => _storage[key] = value;

  @override
  Future<void> delete(String key) async => _storage.remove(key);

  @override
  Future<Map<String, String>> readAll() async => Map.unmodifiable(_storage);
}

void main() {
  group('LAN End-to-End File Transfer Over LocalTlsTransport', () {
    late Directory tempSenderDir;
    late Directory tempReceiverDir;

    late IdentityService senderIdentityService;
    late IdentityService receiverIdentityService;
    late DeviceIdentity senderIdentity;
    late DeviceIdentity receiverIdentity;

    setUp(() async {
      tempSenderDir = await Directory.systemTemp.createTemp('lan_sender_test_');
      tempReceiverDir = await Directory.systemTemp.createTemp('lan_receiver_test_');

      senderIdentityService = IdentityService(secureStorage: InMemorySecureStorage());
      receiverIdentityService = IdentityService(secureStorage: InMemorySecureStorage());

      senderIdentity = await senderIdentityService.initialize();
      receiverIdentity = await receiverIdentityService.initialize();
    });

    tearDown(() async {
      if (await tempSenderDir.exists()) {
        await tempSenderDir.delete(recursive: true);
      }
      if (await tempReceiverDir.exists()) {
        await tempReceiverDir.delete(recursive: true);
      }
    });

    test('Full file transfer over LocalTlsServer / LocalTlsClient pipeline', () async {
      // 1. Start TLS server on receiver
      final server = LocalTlsServer(
        identityService: receiverIdentityService,
        localIdentity: receiverIdentity,
      );
      await server.startListening(0);
      final serverPort = server.boundPort!;

      // 2. Prepare Receiver Protocol Engine
      final receiverEngine = DropFlowProtocolEngine(localIdentity: receiverIdentity);
      server.onIncomingTransport.listen((transport) {
        receiverEngine.listenToTransport(transport);
      });

      // 3. Create test file on sender side (1.2 MB)
      final testFile = File('${tempSenderDir.path}/presentation_deck.zip');
      final testBytes = Uint8List.fromList(List.generate(1200000, (i) => (i * 7) % 256));
      await testFile.writeAsBytes(testBytes);
      final expectedSha256 = sha256.convert(testBytes).toString();

      // 4. Connect Sender to Receiver via LocalTlsClient
      final client = LocalTlsClient(
        identityService: senderIdentityService,
        localIdentity: senderIdentity,
      );

      final clientTransport = await client.connectToPeer(
        host: '127.0.0.1',
        port: serverPort,
        expectedFingerprint: receiverIdentity.fingerprint,
      );

      final senderEngine = DropFlowProtocolEngine(localIdentity: senderIdentity);

      // 5. Handle receiver incoming request
      final requestReceived = Completer<void>();
      receiverEngine.onIncomingRequest.listen((request) async {
        await receiverEngine.acceptTransfer(request.transferId, tempReceiverDir.path);
        requestReceived.complete();
      });

      final senderCompleted = Completer<void>();
      senderEngine.onProgress.listen((p) {
        if (p.status == TransferStatus.completed) {
          if (!senderCompleted.isCompleted) {
            senderCompleted.complete();
          }
        }
      });

      // 6. Start sender transfer session
      final sendFuture = senderEngine.startSenderSession(clientTransport, [testFile]);

      await requestReceived.future;
      await Future.wait([sendFuture, senderCompleted.future]);

      // 7. Verify file received intact on disk
      final receivedFile = File('${tempReceiverDir.path}/presentation_deck.zip');
      expect(await receivedFile.exists(), isTrue);
      expect(await receivedFile.length(), equals(1200000));

      final actualSha256 = sha256.convert(await receivedFile.readAsBytes()).toString();
      expect(actualSha256, equals(expectedSha256));

      await clientTransport.close();
      await server.stopListening();
      senderEngine.dispose();
      receiverEngine.dispose();
    });
  });
}
