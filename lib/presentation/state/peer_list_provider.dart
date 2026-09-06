import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/discovered_peer.dart';
import 'orchestrator_provider.dart';

final peerListProvider = StreamProvider<List<DiscoveredPeer>>((ref) async* {
  final orchestratorAsync = ref.watch(transferOrchestratorProvider);
  final orchestrator = orchestratorAsync.asData?.value;

  if (orchestrator != null) {
    yield orchestrator.currentPeers;
    yield* orchestrator.onPeersChanged;
  } else {
    yield const [];
  }
});
