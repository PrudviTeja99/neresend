import 'dart:convert';
import 'dart:typed_data';

/// Application-layer mutual authentication payload exchanged immediately after transport open
class AuthHandshake {
  /// 32-byte Ed25519 public key of the sending peer
  final Uint8List publicKey;

  /// 16-byte random session nonce
  final Uint8List nonce;

  /// 64-byte Ed25519 signature over (Peer_TLS_Cert_Fingerprint + Session_Nonce)
  final Uint8List signature;

  const AuthHandshake({
    required this.publicKey,
    required this.nonce,
    required this.signature,
  });

  /// Binary serialization: [32B PubKey] [16B Nonce] [64B Signature] = 112 Bytes
  Uint8List toBytes() {
    final builder = BytesBuilder();
    builder.add(publicKey);
    builder.add(nonce);
    builder.add(signature);
    return builder.toBytes();
  }

  factory AuthHandshake.fromBytes(Uint8List bytes) {
    if (bytes.length < 112) {
      throw const FormatException('AuthHandshake buffer too short (expected 112 bytes)');
    }
    final pubKey = bytes.sublist(0, 32);
    final nonce = bytes.sublist(32, 48);
    final sig = bytes.sublist(48, 112);
    return AuthHandshake(
      publicKey: pubKey,
      nonce: nonce,
      signature: sig,
    );
  }
}

