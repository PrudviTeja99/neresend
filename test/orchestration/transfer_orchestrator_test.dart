import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:neresend/data/services/identity_service.dart';
import 'package:neresend/data/services/power_management_service.dart';
import 'package:neresend/data/services/storage_service.dart';
import 'package:neresend/data/services/transfer_orchestrator.dart';
import 'package:neresend/domain/contracts/secure_storage_port.dart';
import 'package:neresend/domain/models/device_identity.dart';

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
  group('TransferOrchestrator Tests', () {
    late Directory tempDownloadDir;
    late IdentityService identityService;
    late DeviceIdentity localIdentity;
    late StorageService storageService;
    late PowerManagementService powerService;
    late TransferOrchestrator orchestrator;

    setUp(() async {
      tempDownloadDir =
          await Directory.systemTemp.createTemp('orchestrator_test_');

      identityService = IdentityService(secureStorage: InMemorySecureStorage());
      localIdentity = await identityService.initialize();

      storageService = StorageService(customDownloadDir: tempDownloadDir);
      powerService = PowerManagementService();

      orchestrator = TransferOrchestrator(
        identityService: identityService,
        localIdentity: localIdentity,
        storageService: storageService,
        powerService: powerService,
        tlsPort: 0, // dynamic port for testing
      );
    });

    tearDown(() async {
      await orchestrator.dispose();
      if (await tempDownloadDir.exists()) {
        await tempDownloadDir.delete(recursive: true);
      }
    });

    test('Initializes discovery drivers and starts TLS listener', () async {
      await orchestrator.initialize();
      expect(orchestrator.isReady, isTrue);
      expect(orchestrator.currentPeers, isEmpty);
    });

    test('PowerManagementService tracks active locks correctly', () async {
      expect(powerService.hasActiveLocks, isFalse);

      await powerService.acquireTransferLocks('transfer-1');
      expect(powerService.hasActiveLocks, isTrue);

      await powerService.releaseTransferLocks('transfer-1');
      expect(powerService.hasActiveLocks, isFalse);
    });

    test('StorageService resolves collision names safely', () async {
      final file1 = await storageService.resolveDestinationFile(
          tempDownloadDir.path, 'document.pdf');
      await file1.writeAsString('initial content');

      final file2 = await storageService.resolveDestinationFile(
          tempDownloadDir.path, 'document.pdf');
      expect(file2.path.endsWith('document (1).pdf'), isTrue);
    });

    test('StorageService persists and retrieves transfer history entries',
        () async {
      await storageService.init();

      await storageService.addHistoryEntry(
        TransferHistoryEntry(
          id: 'h1',
          transferId: 't1',
          fileName: 'photo.jpg',
          totalBytes: 1024,
          isSender: true,
          peerAlias: 'Pixel 8',
          peerFingerprint: 'AA:BB:CC:DD',
          timestamp: DateTime.now(),
          status: 'completed',
        ),
      );

      expect(storageService.history.length, 1);
      expect(storageService.history.first.fileName, 'photo.jpg');

      await storageService.clearHistory();
      expect(storageService.history, isEmpty);
    });
  });
}
