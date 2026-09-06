import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../../../core/constants/protocol_constants.dart';
import '../../../core/errors/exceptions.dart';
import '../../../core/protocol/frame_writer.dart';
import '../../services/identity_service.dart';
import '../../../domain/contracts/neresend_transport.dart';
import '../../../domain/models/auth_handshake.dart';
import '../../../domain/models/device_identity.dart';

/// Result of successful mutual application-layer Ed25519 authentication
class AuthResult {
  final String remoteFingerprint;
  final Uint8List remotePublicKey;
  final bool isPinnedTrusted;

  const AuthResult({
    required this.remoteFingerprint,
    required this.remotePublicKey,
    required this.isPinnedTrusted,
  });
}

/// Mutual application-layer Ed25519 authentication handler binding the TLS session to persistent identity keys
class AuthHandshakeHandler {
  final IdentityService identityService;
  final DeviceIdentity localIdentity;

  AuthHandshakeHandler({
    required this.identityService,
    required this.localIdentity,
  });

  /// Perform bidirectional Ed25519 handshake over an open NeReSendTransport
  Future<AuthResult> authenticateTransport({
    required NeReSendTransport transport,
    required String peerTlsCertFingerprint,
    required String localTlsCertFingerprint,
    String? expectedRemoteFingerprint,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    // 1. Generate local 16-byte cryptographically secure session nonce
    final random = Random.secure();
    final localNonce = Uint8List.fromList(List.generate(16, (_) => random.nextInt(256)));

    // 2. Local signature binds remote TLS cert fingerprint + local nonce to local Ed25519 key
    final dataToSign = Uint8List.fromList([
      ...utf8.encode(peerTlsCertFingerprint),
      ...localNonce,
    ]);
    final localSig = await identityService.sign(dataToSign);

    final localHandshake = AuthHandshake(
      publicKey: Uint8List.fromList(localIdentity.publicKeyBytes),
      nonce: localNonce,
      signature: localSig,
    );

    // 3. Send 0x00 AUTH_HANDSHAKE frame
    final localFrame = FrameWriter.createAuthHandshake(localHandshake);
    await transport.sendFrame(localFrame);

    // 4. Await remote 0x00 AUTH_HANDSHAKE frame
    final remoteFrame = await transport.incomingFrames.firstWhere(
      (f) => f.type == ProtocolConstants.frameTypeAuthHandshake,
      orElse: () => throw const ProtocolException('Remote closed before sending AUTH_HANDSHAKE'),
    ).timeout(
      timeout,
      onTimeout: () => throw const NetworkException('AUTH_HANDSHAKE timed out'),
    );

    final remoteHandshake = AuthHandshake.fromBytes(remoteFrame.payload);

    // 5. Verify remote signature over (local TLS cert fingerprint + remote nonce)
    final remoteExpectedData = Uint8List.fromList([
      ...utf8.encode(localTlsCertFingerprint),
      ...remoteHandshake.nonce,
    ]);

    final isSigValid = await identityService.verify(
      message: remoteExpectedData,
      signatureBytes: remoteHandshake.signature,
      publicKeyBytes: remoteHandshake.publicKey,
    );

    if (!isSigValid) {
      throw const CryptoException(
        'Remote peer Ed25519 signature verification failed',
        code: 'INVALID_SIGNATURE',
      );
    }

    // 6. Compute remote identity fingerprint
    final remoteFingerprint = IdentityService.formatFingerprint(remoteHandshake.publicKey);

    // 7. Verify against expected discovery fingerprint if provided
    if (expectedRemoteFingerprint != null &&
        expectedRemoteFingerprint.toUpperCase() != remoteFingerprint.toUpperCase()) {
      throw CryptoException(
        'Identity mismatch: expected $expectedRemoteFingerprint but received $remoteFingerprint',
        code: 'FINGERPRINT_MISMATCH',
      );
    }

    final isPinned = await identityService.isPeerTrusted(remoteFingerprint);

    return AuthResult(
      remoteFingerprint: remoteFingerprint,
      remotePublicKey: remoteHandshake.publicKey,
      isPinnedTrusted: isPinned,
    );
  }
}
