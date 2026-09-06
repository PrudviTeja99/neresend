import 'package:flutter_test/flutter_test.dart';
import 'package:dropflow/core/errors/exceptions.dart';
import 'package:dropflow/data/transports/direct_link/unsupported_direct_adapter.dart';
import 'package:dropflow/domain/contracts/direct_link_adapter.dart';

void main() {
  group('UnsupportedDirectAdapter Graceful Fallback Tests', () {
    const adapter = UnsupportedDirectAdapter(
      reason: 'Ethernet-only workstation: No wireless adapter detected.',
    );

    test('checkCapabilities returns hardwareUnsupported status', () async {
      final caps = await adapter.checkCapabilities();
      expect(caps.canHost, isFalse);
      expect(caps.canConnect, isFalse);
      expect(caps.isSupported, isFalse);
      expect(caps.status, equals(DirectLinkStatus.hardwareUnsupported));
      expect(caps.unsupportedReason, contains('Ethernet-only'));
    });

    test('startHosting throws DirectLinkUnavailableException', () async {
      expect(
        () => adapter.startHosting(),
        throwsA(isA<DirectLinkUnavailableException>()),
      );
    });

    test('connectToHost throws DirectLinkUnavailableException', () async {
      const creds = DirectLinkCredentials(
        ssid: 'DropFlow-1234',
        psk: 'secret123',
        hostIp: '192.168.49.1',
        port: 53318,
      );

      expect(
        () => adapter.connectToHost(creds),
        throwsA(isA<DirectLinkUnavailableException>()),
      );
    });
  });
}
