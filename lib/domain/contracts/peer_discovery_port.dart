import '../models/discovered_peer.dart';

/// Port for peer discovery drivers (LAN mDNS, UDP Multicast, BLE GATT, Remote Signaling)
abstract class PeerDiscoveryPort {
  /// Stream emitting active discovered peers
  Stream<List<DiscoveredPeer>> get onPeersChanged;

  /// Start discovering and advertising presence
  Future<void> startDiscovery();

  /// Stop discovery to conserve battery and radio resources
  Future<void> stopDiscovery();

  /// Release resources
  Future<void> dispose();
}

