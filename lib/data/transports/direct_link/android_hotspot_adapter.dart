import 'dart:io';
import 'dart:math';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/exceptions.dart';
import '../../../domain/contracts/direct_link_adapter.dart';

/// Android Wi-Fi Direct / LocalOnlyHotspot adapter
class AndroidHotspotAdapter implements DirectLinkAdapter {
  bool _isHosting = false;
  bool _isConnected = false;
  DirectLinkCredentials? _activeCredentials;

  @override
  Future<DirectLinkCapabilities> checkCapabilities() async {
    if (!Platform.isAndroid) {
      return const DirectLinkCapabilities(
        canHost: false,
        canConnect: false,
        status: DirectLinkStatus.hardwareUnsupported,
        unsupportedReason: 'AndroidHotspotAdapter only runs on Android',
      );
    }

    return const DirectLinkCapabilities(
      canHost: true,
      canConnect: true,
      status: DirectLinkStatus.ready,
    );
  }

  @override
  Future<DirectLinkCredentials> startHosting() async {
    final random = Random.secure();
    final ssidSuffix = random.nextInt(9000) + 1000;
    final ssid = 'DropFlow-$ssidSuffix';
    final psk = _generateRandomPsk(12);

    // Resolve local IPv4 assigned to interface or fallback to standard Android LocalOnlyHotspot IP
    final hostIp = await _resolveLocalIp() ?? '192.168.49.1';

    _activeCredentials = DirectLinkCredentials(
      ssid: ssid,
      psk: psk,
      hostIp: hostIp,
      port: AppConstants.tcpTlsPort,
    );

    _isHosting = true;
    return _activeCredentials!;
  }

  @override
  Future<void> connectToHost(DirectLinkCredentials credentials) async {
    _isConnected = true;
    _activeCredentials = credentials;
  }

  @override
  Future<void> stop() async {
    _isHosting = false;
    _isConnected = false;
    _activeCredentials = null;
  }

  Future<String?> _resolveLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      for (final iface in interfaces) {
        if (iface.name.contains('wlan') || iface.name.contains('ap') || iface.name.contains('p2p')) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
              return addr.address;
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  String _generateRandomPsk(int length) {
    const chars = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random.secure();
    return List.generate(length, (_) => chars[rand.nextInt(chars.length)]).join();
  }
}
