import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../domain/contracts/direct_link_adapter.dart';
import '../../../domain/models/device_identity.dart';
import '../../../domain/models/discovered_peer.dart';
import '../../../domain/models/transfer_mode.dart';

/// Handles BLE GATT advertisement formatting, scanning parser, and out-of-band credential exchange
class BleSignaler {
  static const String serviceUuid = '0000DF01-0000-1000-8000-00805F9B34FB';
  static const String identityCharUuid = '0000DF02-0000-1000-8000-00805F9B34FB';
  static const String credentialsCharUuid = '0000DF04-0000-1000-8000-00805F9B34FB';

  BleSignaler._();

  /// Encodes local device identity into compact BLE advertisement packet
  static Uint8List encodeAdvertisementData({
    required DeviceIdentity identity,
    int port = 53318,
  }) {
    final payloadJson = jsonEncode({
      'id': identity.deviceId,
      'alias': identity.alias,
      'fp': identity.fingerprint,
      'pk': identity.publicKeyBase64,
      'p': port,
      'os': Platform.operatingSystem,
    });
    return Uint8List.fromList(utf8.encode(payloadJson));
  }

  /// Parses raw BLE advertisement bytes into a DiscoveredPeer
  static DiscoveredPeer? parseAdvertisementData(Uint8List bytes) {
    try {
      final jsonStr = utf8.decode(bytes);
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;

      return DiscoveredPeer(
        id: json['id'] as String,
        alias: json['alias'] as String,
        fingerprint: json['fp'] as String,
        identityPublicKey: json['pk'] as String,
        ipAddress: '192.168.49.1', // Placeholder resolved upon Wi-Fi Direct connection
        port: json['p'] as int? ?? 53318,
        deviceType: DeviceType.fromString(json['os'] as String?),
        supportedMode: TransferMode.direct,
        lastSeen: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Encodes DirectLinkCredentials for out-of-band BLE exchange
  static Uint8List encodeCredentials(DirectLinkCredentials creds) {
    final jsonStr = jsonEncode({
      'ssid': creds.ssid,
      'psk': creds.psk,
      'hostIp': creds.hostIp,
      'port': creds.port,
    });
    return Uint8List.fromList(utf8.encode(jsonStr));
  }

  /// Decodes DirectLinkCredentials from received BLE characteristic bytes
  static DirectLinkCredentials decodeCredentials(Uint8List bytes) {
    final jsonStr = utf8.decode(bytes);
    final json = jsonDecode(jsonStr) as Map<String, dynamic>;

    return DirectLinkCredentials(
      ssid: json['ssid'] as String,
      psk: json['psk'] as String,
      hostIp: json['hostIp'] as String,
      port: json['port'] as int,
    );
  }
}
