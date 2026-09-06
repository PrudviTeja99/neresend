import 'package:flutter_test/flutter_test.dart';
import 'package:neresend/data/transports/direct_link/android_hotspot_adapter.dart';
import 'package:neresend/data/transports/direct_link/direct_link_factory.dart';
import 'package:neresend/data/transports/direct_link/linux_nm_adapter.dart';
import 'package:neresend/data/transports/direct_link/windows_direct_adapter.dart';

void main() {
  group('DirectLink Platform Adapters Tests', () {
    test('DirectLinkFactory returns valid adapter for host OS', () {
      final adapter = DirectLinkFactory.createPlatformAdapter();
      expect(adapter, isNotNull);
    });

    test('AndroidHotspotAdapter starts hosting and generates credentials', () async {
      final adapter = AndroidHotspotAdapter();
      final creds = await adapter.startHosting();

      expect(creds.ssid, startsWith('NeReSend-'));
      expect(creds.psk.length, equals(12));
      expect(creds.hostIp, isNotEmpty);
      expect(creds.port, equals(53318));

      await adapter.stop();
    });

    test('LinuxNmAdapter starts hosting and generates credentials', () async {
      final adapter = LinuxNmAdapter();
      final creds = await adapter.startHosting();

      expect(creds.ssid, startsWith('NeReSend-'));
      expect(creds.psk.length, equals(12));
      expect(creds.hostIp, isNotEmpty);
      expect(creds.port, equals(53318));

      await adapter.stop();
    });

    test('WindowsDirectAdapter starts hosting and generates credentials', () async {
      final adapter = WindowsDirectAdapter();
      final creds = await adapter.startHosting();

      expect(creds.ssid, startsWith('NeReSend-'));
      expect(creds.psk.length, equals(12));
      expect(creds.hostIp, isNotEmpty);
      expect(creds.port, equals(53318));

      await adapter.stop();
    });
  });
}
