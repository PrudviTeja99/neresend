import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neresend/core/constants/protocol_constants.dart';
import 'package:neresend/core/protocol/frame_writer.dart';
import 'package:neresend/core/protocol/neresend_frame.dart';
import 'package:neresend/data/transports/wormhole/wormhole_connection_manager.dart';

/// Lightweight in-memory test server simulating a Magic Wormhole transit relay
class _FakeSession {
  final Socket socket;
  final String sideId;
  _FakeSession? peer;
  bool handshaked = false;

  _FakeSession({required this.socket, required this.sideId});
}

class FakeTransitRelayServer {
  ServerSocket? _server;
  final Map<String, List<_FakeSession>> _pendingRooms = {};

  Future<int> start() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handleConnection);
    return _server!.port;
  }

  void _handleConnection(Socket socket) {
    final buffer = <int>[];
    _FakeSession? session;

    socket.listen(
      (data) {
        if (session != null && session!.peer != null) {
          session!.peer!.socket.add(data);
          return;
        }

        buffer.addAll(data);
        final text = utf8.decode(buffer, allowMalformed: true);
        if (text.contains('\n')) {
          final line = text.split('\n').first.trim();
          final match =
              RegExp(r'^please relay ([a-f0-9]+) for side ([a-f0-9]+)$')
                  .firstMatch(line);

          if (match == null) {
            socket.write('bad handshake\n');
            socket.flush().then((_) => socket.destroy());
            return;
          }

          final token = match.group(1)!;
          final sideId = match.group(2)!;
          session = _FakeSession(socket: socket, sideId: sideId);

          final room = _pendingRooms.putIfAbsent(token, () => []);
          room.add(session!);

          if (room.length == 2) {
            final peerA = room[0];
            final peerB = room[1];
            _pendingRooms.remove(token);

            peerA.peer = peerB;
            peerB.peer = peerA;

            peerA.socket.write('ok\n');
            peerB.socket.write('ok\n');

            peerA.socket.flush();
            peerB.socket.flush();
          }
        }
      },
      onError: (_) => socket.destroy(),
      onDone: () => socket.destroy(),
    );
  }

  Future<void> stop() async {
    await _server?.close();
    for (final room in _pendingRooms.values) {
      for (final p in room) {
        p.socket.destroy();
      }
    }
    _pendingRooms.clear();
  }
}

void main() {
  group('Wormhole Transit Transport Tests', () {
    late FakeTransitRelayServer fakeRelay;
    late int relayPort;

    setUp(() async {
      fakeRelay = FakeTransitRelayServer();
      relayPort = await fakeRelay.start();
    });

    tearDown(() async {
      await fakeRelay.stop();
    });

    test('deriveTransitToken generates consistent 64-hex SHA-256 token', () {
      final token1 = WormholeConnectionManager.deriveTransitToken('123 456');
      final token2 = WormholeConnectionManager.deriveTransitToken('123456');
      expect(token1, equals(token2));
      expect(token1.length, equals(64));
      expect(RegExp(r'^[a-f0-9]{64}$').hasMatch(token1), isTrue);
    });

    test('generateSideId produces valid 16-hex side identifier', () {
      final side1 = WormholeConnectionManager.generateSideId();
      final side2 = WormholeConnectionManager.generateSideId();
      expect(side1.length, equals(16));
      expect(side2.length, equals(16));
      expect(side1, isNot(equals(side2)));
    });

    test('Host and Client pair over Wormhole transit relay and exchange frames',
        () async {
      const pin = '789 123';
      final hostManager = WormholeConnectionManager(
        transitHost: '127.0.0.1',
        transitPort: relayPort,
      );
      final clientManager = WormholeConnectionManager(
        transitHost: '127.0.0.1',
        transitPort: relayPort,
      );

      final hostFuture = hostManager.connectAndRendezvous(
        pin: pin,
        localFingerprint: 'AA:BB:CC',
        remoteFingerprint: 'DD:EE:FF',
        isHost: true,
        timeout: const Duration(seconds: 5),
      );

      final clientFuture = clientManager.connectAndRendezvous(
        pin: pin,
        localFingerprint: 'DD:EE:FF',
        remoteFingerprint: 'AA:BB:CC',
        isHost: false,
        timeout: const Duration(seconds: 5),
      );

      final results = await Future.wait([hostFuture, clientFuture]);
      final hostTransport = results[0];
      final clientTransport = results[1];

      expect(hostTransport.isConnected, isTrue);
      expect(clientTransport.isConnected, isTrue);
      expect(hostTransport.sasEmojis, equals(clientTransport.sasEmojis));

      final receivedFrames = <NeReSendFrame>[];
      final hostCompleter = Completer<void>();

      hostTransport.incomingFrames.listen((frame) {
        receivedFrames.add(frame);
        if (receivedFrames.length == 2) {
          hostCompleter.complete();
        }
      });

      // Client sends a control frame and a data chunk
      await clientTransport.sendFrame(
        FrameWriter.createAcceptResponse(
          transferId: 'transfer-123',
          acceptedRanges: {},
        ),
      );

      await clientTransport.sendDataChunk(
        0,
        0,
        Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
      );

      await hostCompleter.future.timeout(const Duration(seconds: 5));

      expect(receivedFrames.length, equals(2));
      expect(receivedFrames[0].type,
          equals(ProtocolConstants.frameTypeAcceptResponse));
      expect(receivedFrames[1].type,
          equals(ProtocolConstants.frameTypeFileDataChunk));

      await hostTransport.close();
      await clientTransport.close();
    });
  });
}
