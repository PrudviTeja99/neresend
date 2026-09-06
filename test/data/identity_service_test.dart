import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:dropflow/data/services/identity_service.dart';
import 'package:dropflow/domain/contracts/secure_storage_port.dart';

class InMemorySecureStorage implements SecureStoragePort {
  final Map<String, String> _storage = {};

  @override
  Future<String?> read(String key) async => _storage[key];

  @override
  Future<void> write(String key, String value) async {
    _storage[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _storage.remove(key);
  }

  @override
  Future<Map<String, String>> readAll() async => Map.from(_storage);
}

void main() {
  group('IdentityService Tests', () {
    late InMemorySecureStorage storage;
    late IdentityService service;

    setUp(() {
      storage = InMemorySecureStorage();
      service = IdentityService(secureStorage: storage);
    });

    test('Generates new Ed25519 keypair and persistent fingerprint on cold start', () async {
      final identity = await service.initialize();

      expect(identity.deviceId.length, 16);
      expect(identity.publicKeyBase64.isNotEmpty, isTrue);
      expect(identity.fingerprint, contains(':'));
      expect(identity.publicKeyBytes.length, 32);

      // Verify stored in secure storage
      expect(await storage.read('dropflow_identity_priv_key'), isNotNull);
      expect(await storage.read('dropflow_identity_pub_key'), isNotNull);
      expect(await storage.read('dropflow_device_alias'), isNotNull);
    });

    test('Reloads exact same identity on second initialize() call', () async {
      final firstIdentity = await service.initialize();

      // Create new service instance with same storage
      final secondService = IdentityService(secureStorage: storage);
      final secondIdentity = await secondService.initialize();

      expect(secondIdentity.deviceId, firstIdentity.deviceId);
      expect(secondIdentity.publicKeyBase64, firstIdentity.publicKeyBase64);
      expect(secondIdentity.fingerprint, firstIdentity.fingerprint);
      expect(secondIdentity.publicKeyBytes, firstIdentity.publicKeyBytes);
    });

    test('Cryptographic signing and verification with Ed25519', () async {
      final identity = await service.initialize();
      final testMessage = utf8.encode('DropFlow Ephemeral TLS Binding Challenge Nonce 12345');

      final signature = await service.sign(testMessage);
      expect(signature.length, 64);

      // Verify signature is valid
      final isValid = await service.verify(
        message: testMessage,
        signatureBytes: signature,
        publicKeyBytes: identity.publicKeyBytes,
      );
      expect(isValid, isTrue);

      // Tampered message must fail verification
      final tamperedMessage = utf8.encode('Tampered message');
      final isTamperedValid = await service.verify(
        message: tamperedMessage,
        signatureBytes: signature,
        publicKeyBytes: identity.publicKeyBytes,
      );
      expect(isTamperedValid, isFalse);
    });

    test('Trusted device fingerprint pinning', () async {
      await service.initialize();
      const peerFingerprint = 'A1:B2:C3:D4:E5:F6:00:11:22:33:44:55:66:77:88:99';

      expect(await service.isPeerTrusted(peerFingerprint), isFalse);

      await service.trustPeer(peerFingerprint);
      expect(await service.isPeerTrusted(peerFingerprint), isTrue);

      await service.untrustPeer(peerFingerprint);
      expect(await service.isPeerTrusted(peerFingerprint), isFalse);
    });

    test('Alias updating with length boundary limits', () async {
      await service.initialize();

      await service.updateAlias('Alice Mobile');
      expect(service.currentIdentity?.alias, 'Alice Mobile');
      expect(await storage.read('dropflow_device_alias'), 'Alice Mobile');

      // Test > 32 character truncation
      await service.updateAlias('This Is An Extremely Long Device Name That Exceeds 32 Characters');
      expect(service.currentIdentity?.alias.length, 32);
    });
  });
}

