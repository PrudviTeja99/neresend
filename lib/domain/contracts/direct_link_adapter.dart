/// Direct Link operational readiness status
enum DirectLinkStatus {
  ready,
  permissionRequired,
  hardwareUnsupported,
  disabled,
}

/// Runtime capability report of the host device's Wi-Fi hardware/OS
class DirectLinkCapabilities {
  final bool canHost;
  final bool canConnect;
  final DirectLinkStatus status;
  final String? unsupportedReason;

  const DirectLinkCapabilities({
    required this.canHost,
    required this.canConnect,
    required this.status,
    this.unsupportedReason,
  });

  bool get isSupported => canHost || canConnect;
}

/// Ad-hoc Wi-Fi credentials exchanged over encrypted BLE
class DirectLinkCredentials {
  final String ssid;
  final String psk;
  final String hostIp;
  final int port;

  const DirectLinkCredentials({
    required this.ssid,
    required this.psk,
    required this.hostIp,
    required this.port,
  });
}

/// Port for OS-specific router-free Wi-Fi Direct / SoftAP adapters
abstract class DirectLinkAdapter {
  /// Probes hardware and OS permissions at runtime
  Future<DirectLinkCapabilities> checkCapabilities();

  /// Hosts an ad-hoc local Wi-Fi AP and returns credentials
  Future<DirectLinkCredentials> startHosting();

  /// Connects as a client to a peer-hosted AP
  Future<void> connectToHost(DirectLinkCredentials credentials);

  /// Tears down direct link and restores previous network interface state
  Future<void> stop();
}

