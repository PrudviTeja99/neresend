import 'package:flutter_test/flutter_test.dart';
import 'package:neresend/data/services/identity_service.dart';
import 'package:neresend/data/services/storage_service.dart';
import 'package:neresend/data/services/transfer_orchestrator.dart';
import 'package:neresend/domain/contracts/secure_storage_port.dart';
import 'package:neresend/domain/models/device_identity.dart';

class FakeSecureStorage implements SecureStoragePort {
  final Map<String, String> _data = {};

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<Map<String, String>> readAll() async => Map.from(_data);

  @override
  Future<void> write(String key, String value) async => _data[key] = value;
}

void main() {
  group('Identity Update & Propagation Tests', () {
    late IdentityService identityService;
    late StorageService storageService;
    late DeviceIdentity initialIdentity;
    late TransferOrchestrator orchestrator;

    setUp(() async {
      final storage = FakeSecureStorage();
      identityService = IdentityService(secureStorage: storage);
      initialIdentity = await identityService.initialize();
      storageService = StorageService();

      orchestrator = TransferOrchestrator(
        identityService: identityService,
        localIdentity: initialIdentity,
        storageService: storageService,
      );
    });

    tearDown(() async {
      await orchestrator.dispose();
    });

    test('updateLocalIdentity updates all discovery drivers and engines', () {
      expect(orchestrator.localIdentity.alias, initialIdentity.alias);
      expect(
          orchestrator.lanDiscovery.localIdentity.alias, initialIdentity.alias);
      expect(
          orchestrator.bleDiscovery.localIdentity.alias, initialIdentity.alias);
      expect(orchestrator.remoteDiscovery.localIdentity.alias,
          initialIdentity.alias);
      expect(orchestrator.localTlsServer.localIdentity.alias,
          initialIdentity.alias);
      expect(orchestrator.localTlsClient.localIdentity.alias,
          initialIdentity.alias);
      expect(orchestrator.protocolEngine.localIdentity.alias,
          initialIdentity.alias);

      final updatedIdentity =
          initialIdentity.copyWith(alias: 'Super Fast Phone');
      orchestrator.updateLocalIdentity(updatedIdentity);

      expect(orchestrator.localIdentity.alias, 'Super Fast Phone');
      expect(orchestrator.lanDiscovery.localIdentity.alias, 'Super Fast Phone');
      expect(orchestrator.bleDiscovery.localIdentity.alias, 'Super Fast Phone');
      expect(
          orchestrator.remoteDiscovery.localIdentity.alias, 'Super Fast Phone');
      expect(
          orchestrator.localTlsServer.localIdentity.alias, 'Super Fast Phone');
      expect(
          orchestrator.localTlsClient.localIdentity.alias, 'Super Fast Phone');
      expect(
          orchestrator.protocolEngine.localIdentity.alias, 'Super Fast Phone');
    });
  });
}
