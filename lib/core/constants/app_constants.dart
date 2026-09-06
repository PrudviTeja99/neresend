/// Application-wide constants for NeReSend
class AppConstants {
  AppConstants._();

  static const String appName = 'NeReSend';
  static const String appVersion = '1.0.0';

  // Default Network Ports
  static const int mdnsPort = 5353;
  static const int udpDiscoveryPort = 53317;
  static const int tcpTlsPort = 53318;

  // Multicast Group Addresses
  static const String mdnsIpv4Multicast = '224.0.0.251';
  static const String mdnsIpv6Multicast = 'FF02::FB';
  static const String neReSendUdpMulticast = '224.0.0.167';
  static const String neReSendUdpBroadcast = '255.255.255.255';

  // DNS-SD Service Identifier
  static const String mdnsServiceType = '_neresend._tcp.local.';

  // Session & Security
  static const Duration remotePinTtl = Duration(minutes: 10);
  static const int maxPinFailedAttempts = 3;
  static const int defaultPinLength = 6;

  // Default Chunk Sizes (Bytes)
  static const int chunkSize1MB = 1024 * 1024;
  static const int chunkSize2MB = 2 * 1024 * 1024;
  static const int chunkSize4MB = 4 * 1024 * 1024;
  static const int chunkSize8MB = 8 * 1024 * 1024;
}

