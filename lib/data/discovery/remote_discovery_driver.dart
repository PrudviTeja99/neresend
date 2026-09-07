import 'dart:async';

import '../../../domain/contracts/peer_discovery_port.dart';
import '../../../domain/models/device_identity.dart';
import '../../../domain/models/discovered_peer.dart';
import '../../../domain/models/transfer_mode.dart';
import '../transports/webrtc/remote_signaling_client.dart';

/// Result of a successful remote peer matchmaking
class RemotePairingResult {
  final String sdpOffer;
  final DiscoveredPeer hostPeer;
  final RemoteSessionInfo sessionInfo;

  const RemotePairingResult({
    required this.sdpOffer,
    required this.hostPeer,
    required this.sessionInfo,
  });
}

/// Remote Internet peer discovery driver coordinating ephemeral cloud signaling and WebRTC rendezvous
class RemoteDiscoveryDriver implements PeerDiscoveryPort {
  final DeviceIdentity localIdentity;
  final RemoteSignalingClient signalingClient;

  final Map<String, DiscoveredPeer> _peers = {};
  final StreamController<List<DiscoveredPeer>> _peerController =
      StreamController<List<DiscoveredPeer>>.broadcast();

  RemoteSessionInfo? _activeHostSession;
  bool _isDiscovering = false;

  RemoteDiscoveryDriver({
    required this.localIdentity,
    RemoteSignalingClient? signalingClient,
  }) : signalingClient = signalingClient ?? RemoteSignalingClient();

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

  /// Host creates a 5-minute ephemeral session with WebRTC SDP offer
  Future<RemoteSessionInfo> createHostSession({
    required String sdpOffer,
    String? preferredPin,
  }) async {
    _isDiscovering = true;
    final sessionInfo = await signalingClient.createSession(
      hostIdentity: localIdentity,
      sdpOffer: sdpOffer,
      preferredPin: preferredPin,
    );
    _activeHostSession = sessionInfo;
    return sessionInfo;
  }

  /// Host awaits the client's SDP answer
  Future<String> awaitClientAnswer({required String sessionId}) async {
    final answer = await signalingClient.awaitAnswer(sessionId: sessionId);
    return answer;
  }

  /// Client joins an active session using 6-digit PIN or structured QR invite URI
  Future<RemotePairingResult> pairWithPin({
    required String pinOrUri,
    required String sdpAnswer,
  }) async {
    _isDiscovering = true;
    final sessionData = await signalingClient.joinSession(
      pinOrUri: pinOrUri,
      clientIdentity: localIdentity,
    );

    await signalingClient.submitAnswer(
      sessionId: sessionData.sessionInfo.sessionId,
      sdpAnswer: sdpAnswer,
    );

    final hostIdentity = sessionData.hostIdentity;
    final hostPeer = DiscoveredPeer(
      id: hostIdentity.deviceId,
      alias: hostIdentity.alias,
      deviceType: DeviceType.android,
      ipAddress: '0.0.0.0', // WebRTC DTLS direct ICE / TURN relay
      port: 0,
      supportedMode: TransferMode.remote,
      identityPublicKey: hostIdentity.publicKeyBase64,
      fingerprint: hostIdentity.fingerprint,
      lastSeen: DateTime.now(),
    );

    registerPeer(hostPeer);
    return RemotePairingResult(
      sdpOffer: sessionData.sdpOffer,
      hostPeer: hostPeer,
      sessionInfo: sessionData.sessionInfo,
    );
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
    if (_activeHostSession != null) {
      signalingClient.closeSession(_activeHostSession!.sessionId);
      _activeHostSession = null;
    }
    _peers.clear();
    if (!_peerController.isClosed) {
      _peerController.add(const []);
    }
  }

  @override
  Future<void> dispose() async {
    await stopDiscovery();
    signalingClient.dispose();
    await _peerController.close();
  }
}
