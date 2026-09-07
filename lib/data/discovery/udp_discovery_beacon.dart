import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/constants/app_constants.dart';
import '../../../domain/models/device_identity.dart';
import '../../../domain/models/discovered_peer.dart';
import '../../../domain/models/transfer_mode.dart';

/// UDP Multicast and Broadcast beacon for local network peer discovery
class UdpDiscoveryBeacon {
  final DeviceIdentity localIdentity;
  final int listeningPort;
  final int tcpServicePort;

  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  Timer? _pruneTimer;

  final Map<String, ({DiscoveredPeer peer, DateTime lastSeen})> _peers = {};
  final StreamController<List<DiscoveredPeer>> _peersController =
      StreamController<List<DiscoveredPeer>>.broadcast();

  UdpDiscoveryBeacon({
    required this.localIdentity,
    this.listeningPort = AppConstants.udpDiscoveryPort,
    this.tcpServicePort = AppConstants.tcpTlsPort,
  });

  Stream<List<DiscoveredPeer>> get onPeersChanged => _peersController.stream;
  List<DiscoveredPeer> get currentPeers =>
      _peers.values.map((e) => e.peer).toList();
  bool get isRunning => _socket != null;

  /// Start listening and periodic beacon broadcasting
  Future<void> start() async {
    if (_socket != null) return;

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        listeningPort,
        reuseAddress: true,
        reusePort: !Platform.isWindows,
      );

      _socket!.broadcastEnabled = true;
      _socket!.multicastHops = 4;

      // Join standard DropFlow multicast group
      try {
        _socket!
            .joinMulticast(InternetAddress(AppConstants.neReSendUdpMulticast));
      } catch (_) {
        // Multicast join might not be supported on all interfaces; broadcast fallback works
      }

      _socket!.listen(_handleIncomingDatagram);

      // Start periodic beacon transmission every 2.5 seconds
      _broadcastTimer = Timer.periodic(
        const Duration(milliseconds: 2500),
        (_) => broadcastBeacon(),
      );

      // Start periodic pruning for stale peers (> 8 seconds without heartbeat)
      _pruneTimer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _pruneStalePeers(),
      );

      // Initial broadcast
      broadcastBeacon();
    } catch (e) {
      // Handle socket bind failure
    }
  }

  void _handleIncomingDatagram(RawSocketEvent event) {
    if (event != RawSocketEvent.read || _socket == null) return;

    final datagram = _socket!.receive();
    if (datagram == null) return;

    try {
      final jsonStr = utf8.decode(datagram.data);
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;

      if (json['proto'] != 'neresend_udp_v1') return;

      final deviceId = json['id'] as String;
      final fingerprint = json['fingerprint'] as String;

      // Ignore own broadcasts
      if (deviceId == localIdentity.deviceId ||
          fingerprint == localIdentity.fingerprint) {
        return;
      }

      final alias = json['alias'] as String;
      final remotePort = json['port'] as int? ?? tcpServicePort;
      final pubKey = json['pubkey'] as String;
      final osStr = json['os'] as String? ?? 'unknown';

      final peer = DiscoveredPeer(
        id: deviceId,
        alias: alias,
        fingerprint: fingerprint,
        identityPublicKey: pubKey,
        ipAddress: datagram.address.address,
        port: remotePort,
        deviceType: DeviceType.fromString(osStr),
        supportedMode: TransferMode.lan,
        lastSeen: DateTime.now(),
      );

      _peers[fingerprint] = (peer: peer, lastSeen: DateTime.now());
      _notifyPeersChanged();
    } catch (_) {
      // Ignore malformed UDP packet
    }
  }

  /// Broadcast device presence beacon over multicast and subnet broadcast
  void broadcastBeacon() {
    if (_socket == null) return;

    final payload = jsonEncode({
      'proto': 'neresend_udp_v1',
      'id': localIdentity.deviceId,
      'alias': localIdentity.alias,
      'port': tcpServicePort,
      'fingerprint': localIdentity.fingerprint,
      'pubkey': localIdentity.publicKeyBase64,
      'os': Platform.operatingSystem,
    });

    final bytes = utf8.encode(payload);

    // 1. Send to Multicast Group 224.0.0.167
    try {
      _socket!.send(
        bytes,
        InternetAddress(AppConstants.neReSendUdpMulticast),
        listeningPort,
      );
    } catch (_) {}

    // 2. Send to Global Subnet Broadcast 255.255.255.255
    try {
      _socket!.send(
        bytes,
        InternetAddress(AppConstants.neReSendUdpBroadcast),
        listeningPort,
      );
    } catch (_) {}
  }

  void _pruneStalePeers() {
    final now = DateTime.now();
    final initialCount = _peers.length;

    _peers.removeWhere((_, entry) {
      return now.difference(entry.lastSeen).inSeconds > 8;
    });

    if (_peers.length != initialCount) {
      _notifyPeersChanged();
    }
  }

  void _notifyPeersChanged() {
    if (!_peersController.isClosed) {
      _peersController.add(currentPeers);
    }
  }

  /// Stop discovery beacon and release sockets
  Future<void> stop() async {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _pruneTimer?.cancel();
    _pruneTimer = null;

    _socket?.close();
    _socket = null;
    _peers.clear();
    _notifyPeersChanged();
  }

  void dispose() {
    stop();
    _peersController.close();
  }
}
