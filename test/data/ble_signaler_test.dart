import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:dropflow/data/discovery/ble_discovery_driver.dart';
import 'package:dropflow/data/transports/direct_link/ble_signaler.dart';
import 'package:dropflow/domain/contracts/direct_link_adapter.dart';
import 'package:dropflow/domain/models/device_identity.dart';
import 'package:dropflow/domain/models/transfer_mode.dart';

void main() {
  group('BleSignaler & BleDiscoveryDriver Tests', () {
    const mockIdentity = DeviceIdentity(
      deviceId: 'ble_dev_01',
      alias: 'Pixel 8 Pro',
      publicKeyBase64: 'bW9ja19rZXk=',
      fingerprint: '33:44:55:66:77:88',
      publicKeyBytes: [1, 2, 3],
    );

    test('BleSignaler advertisement encode and decode round-trip', () {
      final advBytes = BleSignaler.encodeAdvertisementData(
        identity: mockIdentity,
        port: 53318,
      );

      final parsedPeer = BleSignaler.parseAdvertisementData(advBytes);
      expect(parsedPeer, isNotNull);
      expect(parsedPeer!.id, equals('ble_dev_01'));
      expect(parsedPeer.alias, equals('Pixel 8 Pro'));
      expect(parsedPeer.fingerprint, equals('33:44:55:66:77:88'));
      expect(parsedPeer.supportedMode, equals(TransferMode.direct));
      expect(parsedPeer.port, equals(53318));
    });

    test('BleSignaler credentials encode and decode round-trip', () {
      const originalCreds = DirectLinkCredentials(
        ssid: 'DropFlow-9876',
        psk: 'wpa2secretkey',
        hostIp: '192.168.49.1',
        port: 53318,
      );

      final encoded = BleSignaler.encodeCredentials(originalCreds);
      final decoded = BleSignaler.decodeCredentials(encoded);

      expect(decoded.ssid, equals(originalCreds.ssid));
      expect(decoded.psk, equals(originalCreds.psk));
      expect(decoded.hostIp, equals(originalCreds.hostIp));
      expect(decoded.port, equals(originalCreds.port));
    });

    test('BleDiscoveryDriver ingests advertisement and emits discovered peer', () async {
      final driver = BleDiscoveryDriver(localIdentity: mockIdentity);
      await driver.startDiscovery();

      const peerIdentity = DeviceIdentity(
        deviceId: 'ble_dev_02',
        alias: 'MacBook Pro',
        publicKeyBase64: 'bW9ja19rZXky',
        fingerprint: 'AA:BB:CC:DD:EE:00',
        publicKeyBytes: [4, 5, 6],
      );

      final peerAdvBytes = BleSignaler.encodeAdvertisementData(identity: peerIdentity);

      final peerEmittedCompleter = Completer<void>();
      driver.onPeersChanged.listen((peers) {
        if (peers.any((p) => p.id == 'ble_dev_02')) {
          if (!peerEmittedCompleter.isCompleted) {
            peerEmittedCompleter.complete();
          }
        }
      });

      driver.handleRawAdvertisement(peerAdvBytes);

      await peerEmittedCompleter.future;
      expect(driver.currentPeers.length, equals(1));
      expect(driver.currentPeers.first.alias, equals('MacBook Pro'));

      await driver.stopDiscovery();
      await driver.dispose();
    });
  });
}
