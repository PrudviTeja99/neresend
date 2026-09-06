import '../../../domain/contracts/direct_link_adapter.dart';

/// Direct Link operational role for a peer in a session
enum DirectLinkRole {
  host,
  client,
  unsupported,
}

/// Negotiates Direct Link Hotspot roles between two peers based on capability probing and tie-breaking
class DirectLinkNegotiator {
  DirectLinkNegotiator._();

  /// Determine the role for local device given both parties' capability reports
  static DirectLinkRole negotiateRole({
    required DirectLinkCapabilities localCaps,
    required String localDeviceId,
    required DirectLinkCapabilities remoteCaps,
    required String remoteDeviceId,
  }) {
    // 1. If neither device can form a connection
    final canLocalAct = localCaps.canHost || localCaps.canConnect;
    final canRemoteAct = remoteCaps.canHost || remoteCaps.canConnect;
    if (!canLocalAct || !canRemoteAct) {
      return DirectLinkRole.unsupported;
    }

    // 2. Asymmetric hosting capabilities: only one peer can host
    if (localCaps.canHost && !remoteCaps.canHost) {
      if (remoteCaps.canConnect) return DirectLinkRole.host;
      return DirectLinkRole.unsupported;
    }

    if (!localCaps.canHost && remoteCaps.canHost) {
      if (localCaps.canConnect) return DirectLinkRole.client;
      return DirectLinkRole.unsupported;
    }

    // 3. Both devices can host and connect: use deterministic tie-breaking on deviceId hash
    if (localCaps.canHost && remoteCaps.canHost) {
      final isLocalHigher = localDeviceId.compareTo(remoteDeviceId) > 0;
      return isLocalHigher ? DirectLinkRole.host : DirectLinkRole.client;
    }

    // Neither can host
    return DirectLinkRole.unsupported;
  }
}
