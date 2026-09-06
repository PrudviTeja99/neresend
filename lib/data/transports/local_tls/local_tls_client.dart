import 'dart:async';
import 'dart:io';

import '../../../core/errors/exceptions.dart';
import '../../services/identity_service.dart';
import '../../../domain/contracts/neresend_transport.dart';
import '../../../domain/models/device_identity.dart';
import 'auth_handshake_handler.dart';
import 'local_tls_transport.dart';
import 'tls_certificate_manager.dart';

/// Local TLS Client connecting to remote peer TLS servers on LAN
class LocalTlsClient {
  final IdentityService identityService;
  final DeviceIdentity localIdentity;

  LocalTlsClient({
    required this.identityService,
    required this.localIdentity,
  });

  /// Connect to a peer server over TLS 1.3 and perform mutual Ed25519 authentication
  Future<NeReSendTransport> connectToPeer({
    required String host,
    required int port,
    String? expectedFingerprint,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    SecureSocket? rawSocket;
    LocalTlsTransport? transport;

    try {
      X509Certificate? receivedCert;

      rawSocket = await SecureSocket.connect(
        host,
        port,
        onBadCertificate: (cert) {
          receivedCert = cert;
          return true; // Accept ephemeral cert; identity verified via Ed25519 signature
        },
        timeout: timeout,
      );

      final cert = rawSocket.peerCertificate ?? receivedCert;
      final serverCertFingerprint = cert != null
          ? TlsCertificateManager.calculateCertFingerprint(cert.der)
          : TlsCertificateManager.defaultCertFingerprint;

      transport = LocalTlsTransport(socket: rawSocket);

      final handler = AuthHandshakeHandler(
        identityService: identityService,
        localIdentity: localIdentity,
      );

      final authResult = await handler.authenticateTransport(
        transport: transport,
        peerTlsCertFingerprint: serverCertFingerprint,
        localTlsCertFingerprint: serverCertFingerprint,
        expectedRemoteFingerprint: expectedFingerprint,
        timeout: timeout,
      );

      transport.authResult = authResult;
      return transport;
    } catch (e) {
      if (transport != null) {
        await transport.close();
      } else if (rawSocket != null) {
        await rawSocket.close();
        rawSocket.destroy();
      }

      if (e is NeReSendException) rethrow;
      throw NetworkException('Failed to connect to peer at $host:$port: $e', cause: e);
    }
  }
}
