import 'dart:async';
import 'dart:io';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/exceptions.dart';
import '../../services/identity_service.dart';
import '../../../domain/contracts/dropflow_transport.dart';
import '../../../domain/contracts/transport_port.dart';
import '../../../domain/models/device_identity.dart';
import '../../../domain/models/discovered_peer.dart';
import 'auth_handshake_handler.dart';
import 'local_tls_client.dart';
import 'local_tls_transport.dart';
import 'tls_certificate_manager.dart';

/// Local TLS Server listening for incoming peer connections on LAN
class LocalTlsServer implements TransportPort {
  final IdentityService identityService;
  final DeviceIdentity localIdentity;
  final SecurityContext? customSecurityContext;

  SecureServerSocket? _serverSocket;
  final StreamController<DropFlowTransport> _incomingConnections =
      StreamController<DropFlowTransport>.broadcast();

  LocalTlsServer({
    required this.identityService,
    required this.localIdentity,
    this.customSecurityContext,
  });

  @override
  Stream<DropFlowTransport> get onIncomingTransport => _incomingConnections.stream;

  bool get isListening => _serverSocket != null;
  int? get boundPort => _serverSocket?.port;

  @override
  Future<void> startListening(int port) async {
    if (_serverSocket != null) return;

    final context = customSecurityContext ?? TlsCertificateManager.createServerContext();

    try {
      _serverSocket = await SecureServerSocket.bind(
        InternetAddress.anyIPv4,
        port,
        context,
        shared: true,
      );

      _serverSocket!.listen(
        _handleIncomingSocket,
        onError: (err) {
          // Socket error
        },
      );
    } catch (e) {
      throw NetworkException('Failed to bind TLS server to port $port: $e', cause: e);
    }
  }

  Future<void> _handleIncomingSocket(SecureSocket socket) async {
    final transport = LocalTlsTransport(socket: socket);
    try {
      final certFingerprint = TlsCertificateManager.defaultCertFingerprint;

      final handler = AuthHandshakeHandler(
        identityService: identityService,
        localIdentity: localIdentity,
      );

      final authResult = await handler.authenticateTransport(
        transport: transport,
        peerTlsCertFingerprint: certFingerprint,
        localTlsCertFingerprint: certFingerprint,
      );

      transport.authResult = authResult;
      _incomingConnections.add(transport);
    } catch (e) {
      await transport.close();
    }
  }

  @override
  Future<DropFlowTransport> connect(DiscoveredPeer peer) async {
    final client = LocalTlsClient(
      identityService: identityService,
      localIdentity: localIdentity,
    );
    return await client.connectToPeer(
      host: peer.ipAddress,
      port: peer.port,
      expectedFingerprint: peer.fingerprint,
    );
  }

  @override
  Future<void> stopListening() async {
    await _serverSocket?.close();
    _serverSocket = null;
  }

  @override
  Future<void> dispose() async {
    await stopListening();
    await _incomingConnections.close();
  }
}
