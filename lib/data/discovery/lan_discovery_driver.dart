import 'dart:async';

import '../../../domain/contracts/peer_discovery_port.dart';
import '../../../domain/models/device_identity.dart';
import '../../../domain/models/discovered_peer.dart';
import 'mdns_discovery.dart';
import 'udp_discovery_beacon.dart';

/// Aggregates mDNS and UDP Multicast Discovery into a unified PeerDiscoveryPort
class LanDiscoveryDriver implements PeerDiscoveryPort {
  final DeviceIdentity localIdentity;
  final int tcpPort;

  late final UdpDiscoveryBeacon _udpBeacon;
  late final MdnsDiscovery _mdnsDiscovery;

  StreamSubscription<List<DiscoveredPeer>>? _udpSub;
  StreamSubscription<List<DiscoveredPeer>>? _mdnsSub;

  final Map<String, DiscoveredPeer> _aggregatedPeers = {};
  final StreamController<List<DiscoveredPeer>> _peerController =
      StreamController<List<DiscoveredPeer>>.broadcast();

  bool _isDiscovering = false;

  LanDiscoveryDriver({
    required this.localIdentity,
    this.tcpPort = 53318,
  }) {
    _udpBeacon = UdpDiscoveryBeacon(
      localIdentity: localIdentity,
      tcpServicePort: tcpPort,
    );
    _mdnsDiscovery = MdnsDiscovery(
      localIdentity: localIdentity,
      tcpPort: tcpPort,
    );
  }

  @override
  Stream<List<DiscoveredPeer>> get onPeersChanged => _peerController.stream;

  bool get isDiscovering => _isDiscovering;

  @override
  Future<void> startDiscovery() async {
    if (_isDiscovering) return;
    _isDiscovering = true;

    await _udpBeacon.start();
    await _mdnsDiscovery.start();

    _udpSub = _udpBeacon.onPeersChanged.listen((peers) {
      _updateFromSource('udp', peers);
    });

    _mdnsSub = _mdnsDiscovery.onPeersChanged.listen((peers) {
      _updateFromSource('mdns', peers);
    });
  }

  void _updateFromSource(String source, List<DiscoveredPeer> peers) {
    // Rebuild aggregated map
    final combined = <String, DiscoveredPeer>{};

    for (final peer in _udpBeacon.currentPeers) {
      combined[peer.fingerprint] = peer;
    }
    for (final peer in _mdnsDiscovery.currentPeers) {
      combined[peer.fingerprint] = peer;
    }

    _aggregatedPeers.clear();
    _aggregatedPeers.addAll(combined);

    if (!_peerController.isClosed) {
      _peerController.add(_aggregatedPeers.values.toList());
    }
  }

  @override
  Future<void> stopDiscovery() async {
    if (!_isDiscovering) return;
    _isDiscovering = false;

    await _udpSub?.cancel();
    _udpSub = null;
    await _mdnsSub?.cancel();
    _mdnsSub = null;

    await _udpBeacon.stop();
    await _mdnsDiscovery.stop();

    _aggregatedPeers.clear();
    if (!_peerController.isClosed) {
      _peerController.add(const []);
    }
  }

  @override
  Future<void> dispose() async {
    await stopDiscovery();
    _udpBeacon.dispose();
    _mdnsDiscovery.dispose();
    await _peerController.close();
  }
}
