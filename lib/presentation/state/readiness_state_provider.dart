import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'orchestrator_provider.dart';

enum ReadinessState {
  ready,
  scanning,
  offline;

  String get label {
    switch (this) {
      case ReadinessState.ready:
        return 'Ready to receive';
      case ReadinessState.scanning:
        return 'Searching nearby...';
      case ReadinessState.offline:
        return 'Wi-Fi Disabled / Offline';
    }
  }
}

final readinessStateProvider = Provider<ReadinessState>((ref) {
  final orchestratorAsync = ref.watch(transferOrchestratorProvider);
  final orchestrator = orchestratorAsync.asData?.value;

  if (orchestrator == null) {
    return ReadinessState.scanning;
  }

  if (orchestrator.isReady) {
    return ReadinessState.ready;
  }

  return ReadinessState.offline;
});
