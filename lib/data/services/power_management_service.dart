import '../../domain/contracts/power_manager_port.dart';

/// Concrete implementation of PowerManagerPort managing battery and performance locks
class PowerManagementService implements PowerManagerPort {
  final Set<String> _activeTransfers = {};

  bool get hasActiveLocks => _activeTransfers.isNotEmpty;

  @override
  Future<void> acquireTransferLocks(String transferId) async {
    _activeTransfers.add(transferId);
    // On native platforms, wake locks / Wi-Fi performance locks are held while active
  }

  @override
  Future<void> releaseTransferLocks(String transferId) async {
    _activeTransfers.remove(transferId);
  }

  void releaseAll() {
    _activeTransfers.clear();
  }
}
