import 'dart:async';
import 'dart:typed_data';

import '../../../domain/contracts/peer_discovery_port.dart';
import '../../../domain/models/device_identity.dart';
import '../../../domain/models/discovered_peer.dart';
import '../transports/direct_link/ble_signaler.dart';

/// PeerDiscoveryPort implementation using Bluetooth Low Energy (BLE) GATT
class BleDiscoveryDriver implements PeerDiscoveryPort {
  final DeviceIdentity localIdentity;
  final int tcpPort;

  final Map<String, ({DiscoveredPeer peer, DateTime lastSeen})> _peers = {};
  final StreamController<List<DiscoveredPeer>> _peerController =
      StreamController<List<DiscoveredPeer>>.broadcast();

  bool _isDiscovering = false;
  Timer? _pruneTimer;

  BleDiscoveryDriver({
    required this.localIdentity,
    this.tcpPort = 53318,
  });

  @override
  Stream<List<DiscoveredPeer>> get onPeersChanged => _peerController.stream;

  List<DiscoveredPeer> get currentPeers => _peers.values.map((e) => e.peer).toList();
  bool get isDiscovering => _isDiscovering;

  @override
  Future<void> startDiscovery() async {
    if (_isDiscovering) return;
    _isDiscovering = true;

    _pruneTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _pruneStalePeers(),
    );
  }

  /// Ingest raw BLE advertisement payload received from native BLE central scanner
  void handleRawAdvertisement(Uint8List advBytes) {
    final peer = BleSignaler.parseAdvertisementData(advBytes);
    if (peer == null) return;

    // Ignore self
    if (peer.id == localIdentity.deviceId || peer.fingerprint == localIdentity.fingerprint) {
      return;
    }

    _peers[peer.fingerprint] = (peer: peer, lastSeen: DateTime.now());
    _notifyPeersChanged();
  }

  void _pruneStalePeers() {
    final now = DateTime.now();
    final initialCount = _peers.length;

    _peers.removeWhere((_, entry) {
      return now.difference(entry.lastSeen).inSeconds > 10;
    });

    if (_peers.length != initialCount) {
      _notifyPeersChanged();
    }
  }

  void _notifyPeersChanged() {
    if (!_peerController.isClosed) {
      _peerController.add(currentPeers);
    }
  }

  @override
  Future<void> stopDiscovery() async {
    if (!_isDiscovering) return;
    _isDiscovering = false;
    _pruneTimer?.cancel();
    _pruneTimer = null;
    _peers.clear();
    _notifyPeersChanged();
  }

  @override
  Future<void> dispose() async {
    await stopDiscovery();
    await _peerController.close();
  }
}
