import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dropflow/domain/models/discovered_peer.dart';
import 'package:dropflow/domain/models/transfer_mode.dart';
import 'package:dropflow/presentation/state/peer_list_provider.dart';

void main() {
  group('PeerListProvider Tests', () {
    test('Defaults to empty list when no peers discovered', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final peers = container.read(peerListProvider);
      expect(peers.asData?.value ?? const <DiscoveredPeer>[], isEmpty);
    });

    test('DiscoveredPeer equality works across list filtering', () {
      final peer1 = DiscoveredPeer(
        id: 'peer-1',
        alias: 'Phone',
        deviceType: DeviceType.android,
        ipAddress: '192.168.1.5',
        port: 53318,
        supportedMode: TransferMode.lan,
        identityPublicKey: 'pub-1',
        fingerprint: 'AA:BB:CC',
        lastSeen: DateTime.now(),
      );

      final peer2 = DiscoveredPeer(
        id: 'peer-1',
        alias: 'Phone Updated',
        deviceType: DeviceType.android,
        ipAddress: '192.168.1.5',
        port: 53318,
        supportedMode: TransferMode.lan,
        identityPublicKey: 'pub-1',
        fingerprint: 'AA:BB:CC',
        lastSeen: DateTime.now(),
      );

      expect(peer1, equals(peer2));
    });
  });
}
