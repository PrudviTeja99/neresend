import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/power_management_service.dart';
import '../../data/services/storage_service.dart';
import '../../data/services/transfer_orchestrator.dart';
import 'identity_provider.dart';

final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService();
});

final powerManagementServiceProvider = Provider<PowerManagementService>((ref) {
  return PowerManagementService();
});

final transferOrchestratorProvider =
    FutureProvider<TransferOrchestrator>((ref) async {
  final identityService = ref.watch(identityServiceProvider);
  final identity = await identityService.initialize();
  final storageService = ref.watch(storageServiceProvider);
  final powerService = ref.watch(powerManagementServiceProvider);

  final orchestrator = TransferOrchestrator(
    identityService: identityService,
    localIdentity: identity,
    storageService: storageService,
    powerService: powerService,
  );

  await orchestrator.initialize();
  ref.onDispose(() {
    orchestrator.dispose();
  });

  return orchestrator;
});
