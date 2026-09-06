import 'transfer_mode.dart';

/// Represents an active peer discovered over LAN, BLE, or Remote Signaling
class DiscoveredPeer {
  /// Unique node identifier
  final String id;

  /// User-defined friendly alias
  final String alias;

  /// Operating system type
  final DeviceType deviceType;

  /// IP address (IPv4 or IPv6) for direct network connection
  final String ipAddress;

  /// TCP listening port (default 53318)
  final int port;

  /// Transport mode through which this peer was discovered
  final TransferMode supportedMode;

  /// Base64 encoded Ed25519 public key
  final String identityPublicKey;

  /// Uppercase hex formatted SHA-256 fingerprint ("XX:XX:...")
  final String fingerprint;

  /// True if the user has pinned this device for automatic acceptance
  final bool isTrusted;

  /// Timestamp of last seen beacon/heartbeat
  final DateTime lastSeen;

  const DiscoveredPeer({
    required this.id,
    required this.alias,
    required this.deviceType,
    required this.ipAddress,
    required this.port,
    required this.supportedMode,
    required this.identityPublicKey,
    required this.fingerprint,
    this.isTrusted = false,
    required this.lastSeen,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'alias': alias,
    'deviceType': deviceType.name,
    'ipAddress': ipAddress,
    'port': port,
    'supportedMode': supportedMode.name,
    'identityPublicKey': identityPublicKey,
    'fingerprint': fingerprint,
    'isTrusted': isTrusted,
    'lastSeen': lastSeen.toIso8601String(),
  };

  factory DiscoveredPeer.fromJson(Map<String, dynamic> json) {
    return DiscoveredPeer(
      id: json['id'] as String,
      alias: json['alias'] as String,
      deviceType: DeviceType.fromString(json['deviceType'] as String?),
      ipAddress: json['ipAddress'] as String,
      port: json['port'] as int,
      supportedMode: TransferMode.values.byName(json['supportedMode'] as String),
      identityPublicKey: json['identityPublicKey'] as String,
      fingerprint: json['fingerprint'] as String,
      isTrusted: json['isTrusted'] as bool? ?? false,
      lastSeen: DateTime.parse(json['lastSeen'] as String),
    );
  }

  DiscoveredPeer copyWith({
    String? alias,
    bool? isTrusted,
    DateTime? lastSeen,
  }) {
    return DiscoveredPeer(
      id: id,
      alias: alias ?? this.alias,
      deviceType: deviceType,
      ipAddress: ipAddress,
      port: port,
      supportedMode: supportedMode,
      identityPublicKey: identityPublicKey,
      fingerprint: fingerprint,
      isTrusted: isTrusted ?? this.isTrusted,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoveredPeer &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          fingerprint == other.fingerprint;

  @override
  int get hashCode => id.hashCode ^ fingerprint.hashCode;
}

