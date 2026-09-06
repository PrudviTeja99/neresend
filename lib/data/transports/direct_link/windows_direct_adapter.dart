import 'dart:io';
import 'dart:math';

import '../../../core/constants/app_constants.dart';
import '../../../domain/contracts/direct_link_adapter.dart';

/// Windows Wi-Fi Direct / Mobile Hotspot adapter
class WindowsDirectAdapter implements DirectLinkAdapter {
  bool _isHosting = false;
  bool _isConnected = false;
  DirectLinkCredentials? _activeCredentials;

  @override
  Future<DirectLinkCapabilities> checkCapabilities() async {
    if (!Platform.isWindows) {
      return const DirectLinkCapabilities(
        canHost: false,
        canConnect: false,
        status: DirectLinkStatus.hardwareUnsupported,
        unsupportedReason: 'WindowsDirectAdapter only runs on Windows',
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

    final hostIp = await _resolveLocalIp() ?? '192.168.137.1';

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
        if (iface.name.toLowerCase().contains('wi-fi') || iface.name.toLowerCase().contains('wireless')) {
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
