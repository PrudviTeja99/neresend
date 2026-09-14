import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../../core/crypto/sas_generator.dart';
import '../../../core/errors/exceptions.dart';
import 'wormhole_transit_transport.dart';

/// Manages Magic Wormhole transit relay connectivity and rendezvous for cross-network file sharing
class WormholeConnectionManager {
  static const String defaultTransitHost = 'transit.magic-wormhole.io';
  static const int defaultTransitPort = 4001;

  final String transitHost;
  final int transitPort;

  Socket? _activeHostSocket;
  bool _isDisposed = false;

  WormholeConnectionManager({
    this.transitHost = defaultTransitHost,
    this.transitPort = defaultTransitPort,
  });

  /// Derive a 64-hex SHA-256 transit token from a 6-digit PIN
  static String deriveTransitToken(String pin) {
    final normalized = pin.replaceAll(' ', '').trim();
    final digest = sha256.convert(utf8.encode('neresend-transit-$normalized'));
    return digest.toString();
  }

  /// Generate a 16-hex character random side ID for Wormhole transit
  static String generateSideId() {
    final random = Random.secure();
    final bytes = List<int>.generate(8, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Connect to the Wormhole transit relay and await the matching peer
  Future<WormholeTransitTransport> connectAndRendezvous({
    required String pin,
    required String localFingerprint,
    required String remoteFingerprint,
    bool isHost = false,
    Duration timeout = const Duration(minutes: 5),
    void Function(String message)? onStatusLog,
  }) async {
    _isDisposed = false;
    final normalizedPin = pin.replaceAll(' ', '').trim();
    final transitToken = deriveTransitToken(normalizedPin);
    final sideId = generateSideId();

    onStatusLog?.call(
        '[WORMHOLE] Connecting to transit relay $transitHost:$transitPort...');
    debugPrint(
        '[WORMHOLE] Connecting to transit relay $transitHost:$transitPort (side: $sideId, isHost: $isHost)...');

    Socket socket;
    try {
      socket = await Socket.connect(
        transitHost,
        transitPort,
        timeout: const Duration(seconds: 15),
      );
      if (isHost) {
        _activeHostSocket = socket;
      }
    } catch (e) {
      throw NetworkException(
        'Failed to connect to Wormhole transit relay $transitHost:$transitPort: $e',
        code: 'TRANSIT_CONNECT_ERROR',
      );
    }

    if (_isDisposed) {
      socket.destroy();
      throw const NetworkException('Connection aborted',
          code: 'TRANSIT_ABORTED');
    }

    // Send standard Magic Wormhole transit relay handshake:
    // "please relay {64-hex-token} for side {16-hex-side}\n"
    final handshakeLine = 'please relay $transitToken for side $sideId\n';
    socket.write(handshakeLine);
    await socket.flush();
    onStatusLog?.call('[WORMHOLE] Handshake sent, awaiting peer match...');
    debugPrint(
        '[WORMHOLE] Handshake sent to transit relay for token $transitToken');

    final handshakeCompleter = Completer<void>();
    final byteController = StreamController<List<int>>();
    final buffer = <int>[];
    bool handshaked = false;

    socket.listen(
      (chunk) {
        if (handshaked) {
          byteController.add(chunk);
          return;
        }

        buffer.addAll(chunk);
        final text = utf8.decode(buffer, allowMalformed: true);
        final okIndex = text.indexOf('ok\n');
        if (okIndex != -1) {
          handshaked = true;
          // Find the exact byte index corresponding to "ok\n"
          final okByteIndex =
              utf8.encode(text.substring(0, okIndex + 3)).length;
          if (buffer.length > okByteIndex) {
            byteController.add(buffer.sublist(okByteIndex));
          }
          if (!handshakeCompleter.isCompleted) {
            handshakeCompleter.complete();
          }
        } else if (text.contains('bad handshake\n') ||
            text.contains('impatient\n')) {
          socket.destroy();
          byteController.close();
          if (!handshakeCompleter.isCompleted) {
            handshakeCompleter.completeError(
              NetworkException('Wormhole transit handshake rejected: $text',
                  code: 'TRANSIT_HANDSHAKE_REJECTED'),
            );
          }
        }
      },
      onError: (err) {
        byteController.addError(err);
        if (!handshakeCompleter.isCompleted) {
          handshakeCompleter.completeError(
            NetworkException('Transit relay error: $err',
                code: 'TRANSIT_SOCKET_ERROR'),
          );
        }
      },
      onDone: () {
        byteController.close();
        if (!handshakeCompleter.isCompleted) {
          handshakeCompleter.completeError(
            const NetworkException(
                'Transit relay closed connection prematurely',
                code: 'TRANSIT_CLOSED_PREMATURELY'),
          );
        }
      },
      cancelOnError: false,
    );

    try {
      await handshakeCompleter.future.timeout(timeout);
    } on TimeoutException {
      socket.destroy();
      byteController.close();
      throw NetworkException(
        'Timed out waiting for peer on transit relay ($transitHost)',
        code: 'PIN_TIMEOUT',
      );
    } catch (e) {
      socket.destroy();
      byteController.close();
      rethrow;
    } finally {
      if (isHost && _activeHostSocket == socket) {
        _activeHostSocket = null;
      }
    }

    final sasEmojis = SasGenerator.formatEmojis(
      localFingerprint: localFingerprint,
      remoteFingerprint: remoteFingerprint,
      sessionPin: normalizedPin,
    );

    onStatusLog?.call(
        '[WORMHOLE] Connected to peer via transit relay (SAS: $sasEmojis)');
    debugPrint(
        '[WORMHOLE] Successfully connected to peer via transit relay (SAS: $sasEmojis)');

    return WormholeTransitTransport(
      socket: socket,
      byteStream: byteController.stream,
      sideId: sideId,
      pin: normalizedPin,
      localFingerprint: localFingerprint,
      remoteFingerprint: remoteFingerprint,
      sasEmojis: sasEmojis,
    );
  }

  /// Idempotently closes active waiting sockets
  Future<void> dispose() async {
    _isDisposed = true;
    final s = _activeHostSocket;
    _activeHostSocket = null;
    if (s != null) {
      try {
        await s.close();
      } catch (_) {}
      s.destroy();
    }
  }
}
