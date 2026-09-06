import '../models/discovered_peer.dart';
import 'neresend_transport.dart';

/// Port responsible for creating and accepting authenticated NeReSendTransport instances
abstract class TransportPort {
  /// Stream of incoming authenticated transport connections from remote peers
  Stream<NeReSendTransport> get onIncomingTransport;

  /// Initiate an outbound connection to a discovered peer
  Future<NeReSendTransport> connect(DiscoveredPeer peer);

  /// Start listening for incoming connections on the specified port
  Future<void> startListening(int port);

  /// Stop listening for connections
  Future<void> stopListening();

  /// Clean up sockets, listeners, and native resources
  Future<void> dispose();
}

