/// Port for acquiring background execution and Wi-Fi performance locks
abstract class PowerManagerPort {
  /// Acquire wake lock and Wi-Fi high-performance lock during active transfer
  Future<void> acquireTransferLocks(String transferId);

  /// Release wake lock and restore normal battery mode
  Future<void> releaseTransferLocks(String transferId);
}

