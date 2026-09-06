import 'dart:async';

import '../../../domain/contracts/peer_discovery_port.dart';
import '../../../domain/models/device_identity.dart';
import '../../../domain/models/discovered_peer.dart';
import '../../../domain/models/transfer_mode.dart';
import '../transports/webrtc/signaling_client.dart';

/// Remote Internet peer discovery driver coordinating 10-minute session PINs and SDP exchange
class RemoteDiscoveryDriver implements PeerDiscoveryPort {
  final DeviceIdentity localIdentity;
  final SignalingClient signalingClient;

  final Map<String, DiscoveredPeer> _peers = {};
  final StreamController<List<DiscoveredPeer>> _peerController =
      StreamController<List<DiscoveredPeer>>.broadcast();

  String? _activeHostPin;
  bool _isDiscovering = false;

  RemoteDiscoveryDriver({
    required this.localIdentity,
    SignalingClient? signalingClient,
  }) : signalingClient = signalingClient ?? SignalingClient();

  @override
  Stream<List<DiscoveredPeer>> get onPeersChanged => _peerController.stream;

  List<DiscoveredPeer> get currentPeers => _peers.values.toList();
  bool get isDiscovering => _isDiscovering;
  String? get activeHostPin => _activeHostPin;

  @override
  Future<void> startDiscovery() async {
    _isDiscovering = true;
  }

  /// Host creates a 10-minute session PIN carrying local SDP offer
  Future<String> createHostSession({required String sdpOffer}) async {
    _isDiscovering = true;
    final pin = await signalingClient.createSession(
      hostIdentity: localIdentity,
      sdpOffer: sdpOffer,
    );
    _activeHostPin = pin;
    return pin;
  }

  /// Host waits for a client to join with the PIN, returning the client SDP answer
  Future<String> awaitClientAnswer({required String pin}) async {
    final answer = await signalingClient.awaitAnswer(pin: pin);
    return answer;
  }

  /// Client joins an active session using the 6-digit PIN and submits its SDP answer
  Future<({String sdpOffer, DiscoveredPeer hostPeer})> pairWithPin({
    required String pin,
    required String sdpAnswer,
  }) async {
    _isDiscovering = true;
    final sessionData = await signalingClient.joinSession(
      pin: pin,
      clientIdentity: localIdentity,
    );

    await signalingClient.submitAnswer(
      pin: pin,
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
    return (sdpOffer: sessionData.sdpOffer, hostPeer: hostPeer);
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
    _activeHostPin = null;
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
