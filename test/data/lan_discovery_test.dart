import 'package:flutter_test/flutter_test.dart';
import 'package:neresend/data/discovery/lan_discovery_driver.dart';
import 'package:neresend/data/discovery/udp_discovery_beacon.dart';
import 'package:neresend/domain/models/device_identity.dart';

void main() {
  group('LAN Discovery & UDP Beacon Tests', () {
    const localIdentity1 = DeviceIdentity(
      deviceId: 'dev_001',
      alias: 'Test Alpha',
      publicKeyBase64: 'pubkey_alpha',
      fingerprint: '11:11:11:11:11:11',
      publicKeyBytes: [1, 2, 3],
    );

    const localIdentity2 = DeviceIdentity(
      deviceId: 'dev_002',
      alias: 'Test Beta',
      publicKeyBase64: 'pubkey_beta',
      fingerprint: '22:22:22:22:22:22',
      publicKeyBytes: [4, 5, 6],
    );

    test('UDP discovery beacon initializes and broadcasts without error',
        () async {
      final beacon1 = UdpDiscoveryBeacon(
        localIdentity: localIdentity1,
        listeningPort: 0,
        tcpServicePort: 0,
      );

      final beacon2 = UdpDiscoveryBeacon(
        localIdentity: localIdentity2,
        listeningPort: 0,
        tcpServicePort: 0,
      );

      await beacon1.start();
      await beacon2.start();

      expect(beacon1.isRunning, isTrue);
      expect(beacon2.isRunning, isTrue);

      beacon1.broadcastBeacon();
      beacon2.broadcastBeacon();

      await Future.delayed(const Duration(milliseconds: 200));

      await beacon1.stop();
      await beacon2.stop();

      expect(beacon1.isRunning, isFalse);
      expect(beacon2.isRunning, isFalse);
    });

    test('LanDiscoveryDriver starts and stops cleanly', () async {
      final driver = LanDiscoveryDriver(
        localIdentity: localIdentity1,
        tcpPort: 53318,
      );

      expect(driver.isDiscovering, isFalse);
      await driver.startDiscovery();
      expect(driver.isDiscovering, isTrue);

      await driver.stopDiscovery();
      expect(driver.isDiscovering, isFalse);

      driver.dispose();
    });
  });
}
