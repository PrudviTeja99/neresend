import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:dropflow/core/errors/exceptions.dart';
import 'package:dropflow/core/protocol/dropflow_frame.dart';
import 'package:dropflow/data/services/identity_service.dart';
import 'package:dropflow/data/transports/local_tls/local_tls_client.dart';
import 'package:dropflow/data/transports/local_tls/local_tls_server.dart';
import 'package:dropflow/domain/contracts/dropflow_transport.dart';
import 'package:dropflow/domain/contracts/secure_storage_port.dart';
import 'package:dropflow/domain/models/device_identity.dart';

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
  group('LocalTls Transport & Ed25519 Session Authentication Tests', () {
    late IdentityService serverIdentityService;
    late IdentityService clientIdentityService;
    late DeviceIdentity serverIdentity;
    late DeviceIdentity clientIdentity;

    setUp(() async {
      serverIdentityService = IdentityService(secureStorage: InMemorySecureStorage());
      clientIdentityService = IdentityService(secureStorage: InMemorySecureStorage());

      serverIdentity = await serverIdentityService.initialize();
      clientIdentity = await clientIdentityService.initialize();
    });

    test('LocalTlsServer and LocalTlsClient connect and mutually authenticate over TLS', () async {
      final server = LocalTlsServer(
        identityService: serverIdentityService,
        localIdentity: serverIdentity,
      );

      // Start on dynamic port (0)
      await server.startListening(0);
      final boundPort = server.boundPort!;
      expect(boundPort, isPositive);

      final client = LocalTlsClient(
        identityService: clientIdentityService,
        localIdentity: clientIdentity,
      );

      final serverTransportCompleter = Completer<DropFlowTransport>();
      server.onIncomingTransport.listen((t) {
        serverTransportCompleter.complete(t);
      });

      // Connect client
      final clientTransport = await client.connectToPeer(
        host: '127.0.0.1',
        port: boundPort,
        expectedFingerprint: serverIdentity.fingerprint,
      );

      final serverTransport = await serverTransportCompleter.future;

      expect(clientTransport.isConnected, isTrue);
      expect(serverTransport.isConnected, isTrue);

      // Send frame from client to server
      final testFrame = DropFlowFrame(
        type: 0x01,
        payload: Uint8List.fromList([1, 2, 3, 4, 5]),
      );

      final serverReceivedCompleter = Completer<DropFlowFrame>();
      serverTransport.incomingFrames.listen(serverReceivedCompleter.complete);

      await clientTransport.sendFrame(testFrame);
      final receivedFrame = await serverReceivedCompleter.future;

      expect(receivedFrame.type, equals(0x01));
      expect(receivedFrame.payload, equals([1, 2, 3, 4, 5]));

      await clientTransport.close();
      await serverTransport.close();
      await server.stopListening();
    });

    test('Connection fails if peer presents unexpected fingerprint', () async {
      final server = LocalTlsServer(
        identityService: serverIdentityService,
        localIdentity: serverIdentity,
      );

      await server.startListening(0);
      final boundPort = server.boundPort!;

      final client = LocalTlsClient(
        identityService: clientIdentityService,
        localIdentity: clientIdentity,
      );

      // Expect a completely bogus fingerprint
      await expectLater(
        client.connectToPeer(
          host: '127.0.0.1',
          port: boundPort,
          expectedFingerprint: 'FF:FF:FF:FF:FF:FF:FF:FF',
        ),
        throwsA(isA<CryptoException>()),
      );

      await server.stopListening();
    });
  });
}
