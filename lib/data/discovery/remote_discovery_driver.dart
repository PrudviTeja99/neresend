import 'dart:async';

import '../../../domain/contracts/peer_discovery_port.dart';
import '../../../domain/models/device_identity.dart';
import '../../../domain/models/discovered_peer.dart';
import '../../../domain/models/remote_session_info.dart';

/// Remote Internet peer discovery driver coordinating ephemeral session state
class RemoteDiscoveryDriver implements PeerDiscoveryPort {
  DeviceIdentity _localIdentity;

  final Map<String, DiscoveredPeer> _peers = {};
  final StreamController<List<DiscoveredPeer>> _peerController =
      StreamController<List<DiscoveredPeer>>.broadcast();

  RemoteSessionInfo? _activeHostSession;
  bool _isDiscovering = false;

  RemoteDiscoveryDriver({
    required DeviceIdentity localIdentity,
  }) : _localIdentity = localIdentity;

  DeviceIdentity get localIdentity => _localIdentity;

  void updateIdentity(DeviceIdentity newIdentity) {
    _localIdentity = newIdentity;
  }

  @override
  Stream<List<DiscoveredPeer>> get onPeersChanged => _peerController.stream;

  List<DiscoveredPeer> get currentPeers => _peers.values.toList();
  bool get isDiscovering => _isDiscovering;
  RemoteSessionInfo? get activeHostSession => _activeHostSession;
  String? get activeHostPin => _activeHostSession?.pin;

  @override
  Future<void> startDiscovery() async {
    _isDiscovering = true;
  }

  /// Explicitly set the active host session (e.g. for Wormhole transit)
  void setActiveHostSession(RemoteSessionInfo session) {
    _activeHostSession = session;
    _isDiscovering = true;
  }

  /// Clear active host session
  void clearActiveHostSession() {
    _activeHostSession = null;
  }

  /// Register a discovered or connected remote peer
  void registerPeer(DiscoveredPeer peer) {
    _peers[peer.fingerprint] = peer;
    if (!_peerController.isClosed) {
      _peerController.add(currentPeers);
    }
  }

  /// Remove a peer when connection drops
  void removePeer(String fingerprint) {
    if (_peers.remove(fingerprint) != null) {
      if (!_peerController.isClosed) {
        _peerController.add(currentPeers);
      }
    }
  }

  @override
  Future<void> stopDiscovery() async {
    _isDiscovering = false;
    _activeHostSession = null;
    _peers.clear();
    if (!_peerController.isClosed) {
      _peerController.add(const []);
    }
  }

  @override
  Future<void> dispose() async {
    await stopDiscovery();
    await _peerController.close();
  }
}
