/// Represents the long-lived cryptographic identity of a DropFlow node
class DeviceIdentity {
  /// Unique 16-character identifier derived from SHA-256(publicKey)
  final String deviceId;

  /// User-customizable display name (e.g., "Rahul's Laptop")
  final String alias;

  /// Base64 encoded Ed25519 Public Key (32 bytes raw)
  final String publicKeyBase64;

  /// Formatted SHA-256 fingerprint in uppercase hex with colons (e.g. "A3:8F:2B:...")
  final String fingerprint;

  /// Raw Ed25519 public key bytes
  final List<int> publicKeyBytes;

  const DeviceIdentity({
    required this.deviceId,
    required this.alias,
    required this.publicKeyBase64,
    required this.fingerprint,
    required this.publicKeyBytes,
  });

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'alias': alias,
    'publicKeyBase64': publicKeyBase64,
    'fingerprint': fingerprint,
  };

  factory DeviceIdentity.fromJson(Map<String, dynamic> json, List<int> publicKeyBytes) {
    return DeviceIdentity(
      deviceId: json['deviceId'] as String,
      alias: json['alias'] as String,
      publicKeyBase64: json['publicKeyBase64'] as String,
      fingerprint: json['fingerprint'] as String,
      publicKeyBytes: publicKeyBytes,
    );
  }

  DeviceIdentity copyWith({String? alias}) {
    return DeviceIdentity(
      deviceId: deviceId,
      alias: alias ?? this.alias,
      publicKeyBase64: publicKeyBase64,
      fingerprint: fingerprint,
      publicKeyBytes: publicKeyBytes,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceIdentity &&
          runtimeType == other.runtimeType &&
          deviceId == other.deviceId &&
          fingerprint == other.fingerprint;

  @override
  int get hashCode => deviceId.hashCode ^ fingerprint.hashCode;
}

