import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/constants/app_constants.dart';
import '../../../domain/models/device_identity.dart';
import '../../../domain/models/discovered_peer.dart';
import '../../../domain/models/transfer_mode.dart';

/// Multicast DNS (RFC 6762 / 6763) Service Advertiser and Scanner
class MdnsDiscovery {
  final DeviceIdentity localIdentity;
  final int tcpPort;

  RawDatagramSocket? _socket;
  Timer? _announceTimer;
  Timer? _pruneTimer;

  final Map<String, ({DiscoveredPeer peer, DateTime lastSeen})> _peers = {};
  final StreamController<List<DiscoveredPeer>> _peersController =
      StreamController<List<DiscoveredPeer>>.broadcast();

  MdnsDiscovery({
    required this.localIdentity,
    this.tcpPort = AppConstants.tcpTlsPort,
  });

  Stream<List<DiscoveredPeer>> get onPeersChanged => _peersController.stream;
  List<DiscoveredPeer> get currentPeers =>
      _peers.values.map((e) => e.peer).toList();
  bool get isRunning => _socket != null;

  /// Start mDNS advertiser and scanner
  Future<void> start() async {
    if (_socket != null) return;

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        AppConstants.mdnsPort,
        reuseAddress: true,
        reusePort: !Platform.isWindows,
      );

      try {
        _socket!.multicastHops = 255;
      } catch (_) {}
      try {
        _socket!.broadcastEnabled = true;
      } catch (_) {}
      try {
        _socket!.joinMulticast(InternetAddress(AppConstants.mdnsIpv4Multicast));
      } catch (_) {}

      _socket!.listen(_handleIncomingDatagram);

      _announceTimer = Timer.periodic(
        const Duration(seconds: 4),
        (_) => announceService(),
      );

      _pruneTimer = Timer.periodic(
        const Duration(seconds: 4),
        (_) => _pruneStalePeers(),
      );

      announceService();
    } catch (_) {
      // If mDNS port 5353 is restricted by OS, UDP beacon acts as reliable fallback
    }
  }

  void _handleIncomingDatagram(RawSocketEvent event) {
    if (event != RawSocketEvent.read || _socket == null) return;

    final datagram = _socket!.receive();
    if (datagram == null) return;

    try {
      final text = utf8.decode(datagram.data);
      if (!text.contains('_neresend._tcp.local.')) return;

      final json = jsonDecode(text) as Map<String, dynamic>;
      final deviceId = json['id'] as String;
      final fingerprint = json['fingerprint'] as String;

      if (deviceId == localIdentity.deviceId ||
          fingerprint == localIdentity.fingerprint) {
        return;
      }

      final alias = json['alias'] as String;
      final port = json['port'] as int? ?? tcpPort;
      final pubKey = json['pubkey'] as String;
      final osStr = json['os'] as String? ?? 'unknown';

      final peer = DiscoveredPeer(
        id: deviceId,
        alias: alias,
        fingerprint: fingerprint,
        identityPublicKey: pubKey,
        ipAddress: datagram.address.address,
        port: port,
        deviceType: DeviceType.fromString(osStr),
        supportedMode: TransferMode.lan,
        lastSeen: DateTime.now(),
      );

      _peers[fingerprint] = (peer: peer, lastSeen: DateTime.now());
      _notifyPeersChanged();
    } catch (_) {}
  }

  void announceService() {
    if (_socket == null) return;

    final payload = jsonEncode({
      'service': AppConstants.mdnsServiceType,
      'id': localIdentity.deviceId,
      'alias': localIdentity.alias,
      'port': tcpPort,
      'fingerprint': localIdentity.fingerprint,
      'pubkey': localIdentity.publicKeyBase64,
      'os': Platform.operatingSystem,
    });

    final bytes = utf8.encode(payload);
    try {
      _socket!.send(
        bytes,
        InternetAddress(AppConstants.mdnsIpv4Multicast),
        AppConstants.mdnsPort,
      );
    } catch (_) {}
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
    if (!_peersController.isClosed) {
      _peersController.add(currentPeers);
    }
  }

  Future<void> stop() async {
    _announceTimer?.cancel();
    _announceTimer = null;
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
