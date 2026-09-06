import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/transfer_progress.dart';
import 'orchestrator_provider.dart';

final activeTransferProvider =
    StateNotifierProvider<ActiveTransferNotifier, TransferProgress?>((ref) {
  final orchestratorAsync = ref.watch(transferOrchestratorProvider);
  final orchestrator = orchestratorAsync.asData?.value;
  return ActiveTransferNotifier(orchestrator);
});

class ActiveTransferNotifier extends StateNotifier<TransferProgress?> {
  final dynamic _orchestrator;
  StreamSubscription<TransferProgress>? _sub;

  ActiveTransferNotifier(this._orchestrator) : super(null) {
    if (_orchestrator != null) {
      _sub = _orchestrator.onProgress.listen((progress) {
        state = progress;
        if (progress.isTerminated) {
          // Auto-clear after brief delay if terminated
          Future.delayed(const Duration(seconds: 4), () {
            if (state?.transferId == progress.transferId &&
                state?.isTerminated == true) {
              state = null;
            }
          });
        }
      });
    }
  }

  void updateProgress(TransferProgress progress) {
    state = progress;
  }

  Future<void> pause() async {
    if (state != null && _orchestrator != null) {
      await _orchestrator.pauseTransfer(state!.transferId);
    }
  }

  Future<void> resume() async {
    if (state != null && _orchestrator != null) {
      await _orchestrator.resumeTransfer(state!.transferId);
    }
  }

  Future<void> cancel() async {
    if (state != null && _orchestrator != null) {
      await _orchestrator.cancelTransfer(state!.transferId);
      state = null;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
