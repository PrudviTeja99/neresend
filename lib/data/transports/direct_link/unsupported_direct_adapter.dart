import '../../../core/errors/exceptions.dart';
import '../../../domain/contracts/direct_link_adapter.dart';

/// Fallback DirectLinkAdapter for systems without compatible Wi-Fi Direct or Hotspot hardware
class UnsupportedDirectAdapter implements DirectLinkAdapter {
  final String reason;

  const UnsupportedDirectAdapter({
    this.reason = 'Direct offline link is not supported on this device hardware or OS.',
  });

  @override
  Future<DirectLinkCapabilities> checkCapabilities() async {
    return DirectLinkCapabilities(
      canHost: false,
      canConnect: false,
      status: DirectLinkStatus.hardwareUnsupported,
      unsupportedReason: reason,
    );
  }

  @override
  Future<DirectLinkCredentials> startHosting() async {
    throw DirectLinkUnavailableException(reason, code: 'DIRECT_LINK_UNAVAILABLE');
  }

  @override
  Future<void> connectToHost(DirectLinkCredentials credentials) async {
    throw DirectLinkUnavailableException(reason, code: 'DIRECT_LINK_UNAVAILABLE');
  }

  @override
  Future<void> stop() async {
    // No-op for unsupported devices
  }
}
