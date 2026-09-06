import 'package:flutter_test/flutter_test.dart';
import 'package:neresend/data/transports/direct_link/direct_link_negotiator.dart';
import 'package:neresend/domain/contracts/direct_link_adapter.dart';

void main() {
  group('DirectLinkNegotiator Tests', () {
    const fullCaps = DirectLinkCapabilities(
      canHost: true,
      canConnect: true,
      status: DirectLinkStatus.ready,
    );

    const clientOnlyCaps = DirectLinkCapabilities(
      canHost: false,
      canConnect: true,
      status: DirectLinkStatus.ready,
    );

    const unsupportedCaps = DirectLinkCapabilities(
      canHost: false,
      canConnect: false,
      status: DirectLinkStatus.hardwareUnsupported,
      unsupportedReason: 'No Wi-Fi card',
    );

    test('Asymmetric hosting: local can host, remote can only connect -> local is Host', () {
      final role = DirectLinkNegotiator.negotiateRole(
        localCaps: fullCaps,
        localDeviceId: 'device_alpha',
        remoteCaps: clientOnlyCaps,
        remoteDeviceId: 'device_beta',
      );

      expect(role, equals(DirectLinkRole.host));
    });

    test('Asymmetric hosting: local can only connect, remote can host -> local is Client', () {
      final role = DirectLinkNegotiator.negotiateRole(
        localCaps: clientOnlyCaps,
        localDeviceId: 'device_alpha',
        remoteCaps: fullCaps,
        remoteDeviceId: 'device_beta',
      );

      expect(role, equals(DirectLinkRole.client));
    });

    test('Symmetric hosting: both can host -> deterministic tie-break based on deviceId', () {
      // 'device_z' > 'device_a' -> device_z is host, device_a is client
      final role1 = DirectLinkNegotiator.negotiateRole(
        localCaps: fullCaps,
        localDeviceId: 'device_z',
        remoteCaps: fullCaps,
        remoteDeviceId: 'device_a',
      );
      expect(role1, equals(DirectLinkRole.host));

      final role2 = DirectLinkNegotiator.negotiateRole(
        localCaps: fullCaps,
        localDeviceId: 'device_a',
        remoteCaps: fullCaps,
        remoteDeviceId: 'device_z',
      );
      expect(role2, equals(DirectLinkRole.client));
    });

    test('Unsupported hardware returns DirectLinkRole.unsupported', () {
      final role = DirectLinkNegotiator.negotiateRole(
        localCaps: unsupportedCaps,
        localDeviceId: 'device_alpha',
        remoteCaps: fullCaps,
        remoteDeviceId: 'device_beta',
      );

      expect(role, equals(DirectLinkRole.unsupported));
    });
  });
}
