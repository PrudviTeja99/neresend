import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import '../../core/errors/exceptions.dart';
import '../../domain/contracts/secure_storage_port.dart';
import '../../domain/models/device_identity.dart';

/// Manages the long-lived Ed25519 identity keypair, certificate signing, and trusted peers
class IdentityService {
  static const String _keyPrivateKey = 'dropflow_identity_priv_key';
  static const String _keyPublicKey = 'dropflow_identity_pub_key';
  static const String _keyDeviceAlias = 'dropflow_device_alias';
  static const String _prefixTrustedPeer = 'dropflow_trusted_peer_';

  final SecureStoragePort _secureStorage;
  final Ed25519 _algorithm;

  SimpleKeyPair? _keyPair;
  DeviceIdentity? _currentIdentity;

  IdentityService({
    required SecureStoragePort secureStorage,
    Ed25519? algorithm,
  })  : _secureStorage = secureStorage,
        _algorithm = algorithm ?? Ed25519();

  DeviceIdentity? get currentIdentity => _currentIdentity;

  /// Initializes identity: loads existing keypair from secure storage or generates a new one
  Future<DeviceIdentity> initialize() async {
    final storedPrivKey = await _secureStorage.read(_keyPrivateKey);
    final storedPubKey = await _secureStorage.read(_keyPublicKey);
    var storedAlias = await _secureStorage.read(_keyDeviceAlias);

    if (storedAlias == null || storedAlias.trim().isEmpty) {
      storedAlias = _getDefaultPlatformAlias();
      await _secureStorage.write(_keyDeviceAlias, storedAlias);
    }

    if (storedPrivKey != null && storedPubKey != null) {
      final privBytes = base64Decode(storedPrivKey);
      final pubBytes = base64Decode(storedPubKey);

      _keyPair = SimpleKeyPairData(
        privBytes,
        publicKey: SimplePublicKey(pubBytes, type: KeyPairType.ed25519),
        type: KeyPairType.ed25519,
      );

      final fingerprint = formatFingerprint(pubBytes);
      final deviceId = computeDeviceId(pubBytes);

      _currentIdentity = DeviceIdentity(
        deviceId: deviceId,
        alias: storedAlias,
        publicKeyBase64: storedPubKey,
        fingerprint: fingerprint,
        publicKeyBytes: pubBytes,
      );
    } else {
      // Generate new Ed25519 keypair
      final keyPair = await _algorithm.newKeyPair();
      final pubKey = await keyPair.extractPublicKey();
      final privKeyBytes = await keyPair.extractPrivateKeyBytes();
      final pubKeyBytes = pubKey.bytes;

      final pubBase64 = base64Encode(pubKeyBytes);
      final privBase64 = base64Encode(privKeyBytes);

      await _secureStorage.write(_keyPrivateKey, privBase64);
      await _secureStorage.write(_keyPublicKey, pubBase64);

      _keyPair = keyPair;
      final fingerprint = formatFingerprint(pubKeyBytes);
      final deviceId = computeDeviceId(pubKeyBytes);

      _currentIdentity = DeviceIdentity(
        deviceId: deviceId,
        alias: storedAlias,
        publicKeyBase64: pubBase64,
        fingerprint: fingerprint,
        publicKeyBytes: pubKeyBytes,
      );
    }

    return _currentIdentity!;
  }

  /// Updates user-facing device alias
  Future<void> updateAlias(String newAlias) async {
    final sanitized = newAlias.trim();
    if (sanitized.isEmpty) return;
    final limited =
        sanitized.length > 32 ? sanitized.substring(0, 32) : sanitized;
    await _secureStorage.write(_keyDeviceAlias, limited);
    if (_currentIdentity != null) {
      _currentIdentity = _currentIdentity!.copyWith(alias: limited);
    }
  }

  /// Signs an arbitrary message using the persistent Ed25519 private key
  Future<Uint8List> sign(List<int> message) async {
    if (_keyPair == null) {
      throw const CryptoException('IdentityService not initialized');
    }
    final signature = await _algorithm.sign(message, keyPair: _keyPair!);
    return Uint8List.fromList(signature.bytes);
  }

  /// Verifies an Ed25519 signature from a peer
  Future<bool> verify({
    required List<int> message,
    required List<int> signatureBytes,
    required List<int> publicKeyBytes,
  }) async {
    try {
      final signature = Signature(
        signatureBytes,
        publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
      );
      return await _algorithm.verify(message, signature: signature);
    } catch (_) {
      return false;
    }
  }

  /// Pins a peer's identity fingerprint as trusted for safe auto-accept
  Future<void> trustPeer(String fingerprint) async {
    await _secureStorage.write(
        '$_prefixTrustedPeer$fingerprint', DateTime.now().toIso8601String());
  }

  Future<void> pinTrustedDevice(String fingerprint) => trustPeer(fingerprint);

  /// Removes a peer's fingerprint from trusted list
  Future<void> untrustPeer(String fingerprint) async {
    await _secureStorage.delete('$_prefixTrustedPeer$fingerprint');
  }

  Future<void> unpinTrustedDevice(String fingerprint) =>
      untrustPeer(fingerprint);

  /// Checks if a peer's fingerprint is currently pinned as trusted
  Future<bool> isPeerTrusted(String fingerprint) async {
    final record = await _secureStorage.read('$_prefixTrustedPeer$fingerprint');
    return record != null;
  }

  Future<bool> isTrusted(String fingerprint) => isPeerTrusted(fingerprint);

  /// Derives a 16-character Device ID from public key
  static String computeDeviceId(List<int> publicKeyBytes) {
    final digest = crypto.sha256.convert(publicKeyBytes);
    return digest.toString().substring(0, 16);
  }

  /// Formats SHA-256 fingerprint in uppercase hex with colons ("A3:8F:2B:...")
  static String formatFingerprint(List<int> publicKeyBytes) {
    final digest = crypto.sha256.convert(publicKeyBytes);
    final hex = digest.toString().toUpperCase();
    final buffer = StringBuffer();
    for (int i = 0; i < hex.length; i += 2) {
      if (i > 0) buffer.write(':');
      buffer.write(hex.substring(i, i + 2));
    }
    return buffer.toString();
  }

  String _getDefaultPlatformAlias() {
    try {
      final hostname = Platform.localHostname;
      if (hostname.isNotEmpty && hostname != 'localhost') {
        return hostname;
      }
    } catch (_) {}

    if (Platform.isAndroid) return 'Android Device';
    if (Platform.isLinux) return 'Linux PC';
    if (Platform.isWindows) return 'Windows PC';
    if (Platform.isMacOS) return 'Mac';
    return 'DropFlow Device';
  }
}
