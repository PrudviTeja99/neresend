import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../core/errors/exceptions.dart';
import 'sas_generator.dart';
import 'webrtc_backpressure_streamer.dart';
import 'webrtc_transport.dart';

/// WebRTC connection lifecycle manager configuring RTCPeerConnection, STUN/TURN, and Dual DataChannels
class WebRtcConnectionManager {
  static const Map<String, dynamic> defaultConfiguration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:global.stun.twilio.com:3478'},
      {
        'urls': 'turn:openrelay.metered.ca:80',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls': 'turn:openrelay.metered.ca:443?transport=tcp',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ],
    'sdpSemantics': 'unified-plan',
  };

  static const Map<String, dynamic> dataOnlySdpConstraints = {
    'mandatory': {
      'OfferToReceiveAudio': false,
      'OfferToReceiveVideo': false,
    },
    'optional': [],
  };

  final Map<String, dynamic> configuration;

  WebRtcConnectionManager({
    this.configuration = defaultConfiguration,
  });

  /// Host creates offer and initializes 'control' & 'data' RTCDataChannels
  Future<
      ({
        RTCPeerConnection peerConnection,
        String sdpOffer,
        RTCDataChannel controlChannel,
        RTCDataChannel dataChannel,
      })> createHostOffer() async {
    final pc = await createPeerConnection(configuration);

    pc.onIceConnectionState = (state) {
      debugPrint('[WEBRTC HOST] ICE Connection State: $state');
    };
    pc.onConnectionState = (state) {
      debugPrint('[WEBRTC HOST] PeerConnection State: $state');
    };
    pc.onSignalingState = (state) {
      debugPrint('[WEBRTC HOST] Signaling State: $state');
    };

    final controlInit = RTCDataChannelInit()..ordered = true;
    final controlChannel = await pc.createDataChannel('control', controlInit);

    final dataInit = RTCDataChannelInit()..ordered = true;
    final dataChannel = await pc.createDataChannel('data', dataInit);
    try {
      dataChannel.bufferedAmountLowThreshold =
          WebRtcBackpressureStreamer.maxBufferedBytes;
    } catch (_) {}

    controlChannel.onDataChannelState = (state) {
      debugPrint('[WEBRTC HOST] Control DataChannel State: $state');
    };
    dataChannel.onDataChannelState = (state) {
      debugPrint('[WEBRTC HOST] Data DataChannel State: $state');
    };

    final offer = await pc.createOffer(dataOnlySdpConstraints);
    await pc.setLocalDescription(offer);

    // Wait for ICE candidate gathering to settle
    await _waitForIceGatheringComplete(pc);

    final localDesc = await pc.getLocalDescription();
    final sdp = localDesc?.sdp ?? offer.sdp ?? '';

    return (
      peerConnection: pc,
      sdpOffer: sdp,
      controlChannel: controlChannel,
      dataChannel: dataChannel,
    );
  }

  /// Host receives client answer and completes WebRtcTransport
  Future<WebRtcTransport> finalizeHostTransport({
    required RTCPeerConnection peerConnection,
    required String sdpAnswer,
    required RTCDataChannel controlChannel,
    required RTCDataChannel dataChannel,
    required String localFingerprint,
    required String remoteFingerprint,
    required String sessionPin,
  }) async {
    debugPrint('[WEBRTC HOST] Setting remote description from SDP answer...');
    final answerDesc = RTCSessionDescription(sdpAnswer, 'answer');
    await peerConnection.setRemoteDescription(answerDesc);

    debugPrint(
        '[WEBRTC HOST] Waiting for control and data channels to open...');
    await _waitForDataChannelsOpen(controlChannel, dataChannel);

    final sasEmojis = SasGenerator.formatEmojis(
      localFingerprint: localFingerprint,
      remoteFingerprint: remoteFingerprint,
      sessionPin: sessionPin,
    );

    return WebRtcTransport(
      controlChannel: controlChannel,
      dataChannel: dataChannel,
      peerConnection: peerConnection,
      sasEmojis: sasEmojis,
    );
  }

  /// Client accepts host offer, gathers ICE candidates, and produces SDP answer
  Future<
      ({
        RTCPeerConnection peerConnection,
        String sdpAnswer,
        Future<WebRtcTransport> Function({
          required String localFingerprint,
          required String remoteFingerprint,
          required String sessionPin,
        }) finalizeTransport,
      })> acceptHostOffer({
    required String sdpOffer,
  }) async {
    final pc = await createPeerConnection(configuration);

    pc.onIceConnectionState = (state) {
      debugPrint('[WEBRTC CLIENT] ICE Connection State: $state');
    };
    pc.onConnectionState = (state) {
      debugPrint('[WEBRTC CLIENT] PeerConnection State: $state');
    };
    pc.onSignalingState = (state) {
      debugPrint('[WEBRTC CLIENT] Signaling State: $state');
    };

    final controlCompleter = Completer<RTCDataChannel>();
    final dataCompleter = Completer<RTCDataChannel>();

    pc.onDataChannel = (channel) {
      debugPrint(
          '[WEBRTC CLIENT] onDataChannel event received: ${channel.label}');
      if (channel.label == 'control' && !controlCompleter.isCompleted) {
        channel.onDataChannelState = (state) {
          debugPrint('[WEBRTC CLIENT] Control DataChannel State: $state');
        };
        controlCompleter.complete(channel);
      } else if (channel.label == 'data' && !dataCompleter.isCompleted) {
        try {
          channel.bufferedAmountLowThreshold =
              WebRtcBackpressureStreamer.maxBufferedBytes;
        } catch (_) {}
        channel.onDataChannelState = (state) {
          debugPrint('[WEBRTC CLIENT] Data DataChannel State: $state');
        };
        dataCompleter.complete(channel);
      }
    };

    final offerDesc = RTCSessionDescription(sdpOffer, 'offer');
    await pc.setRemoteDescription(offerDesc);

    final answer = await pc.createAnswer(dataOnlySdpConstraints);
    await pc.setLocalDescription(answer);

    await _waitForIceGatheringComplete(pc);

    final localDesc = await pc.getLocalDescription();
    final sdp = localDesc?.sdp ?? answer.sdp ?? '';

    Future<WebRtcTransport> finalizeTransport({
      required String localFingerprint,
      required String remoteFingerprint,
      required String sessionPin,
    }) async {
      debugPrint('[WEBRTC CLIENT] Waiting for DataChannels from host...');
      final controlChannel = await controlCompleter.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () =>
            throw const NetworkException('Timeout waiting for control channel'),
      );
      final dataChannel = await dataCompleter.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () =>
            throw const NetworkException('Timeout waiting for data channel'),
      );

      debugPrint('[WEBRTC CLIENT] Awaiting open state for DataChannels...');
      await _waitForDataChannelsOpen(controlChannel, dataChannel);

      final sasEmojis = SasGenerator.formatEmojis(
        localFingerprint: localFingerprint,
        remoteFingerprint: remoteFingerprint,
        sessionPin: sessionPin,
      );

      return WebRtcTransport(
        controlChannel: controlChannel,
        dataChannel: dataChannel,
        peerConnection: pc,
        sasEmojis: sasEmojis,
      );
    }

    return (
      peerConnection: pc,
      sdpAnswer: sdp,
      finalizeTransport: finalizeTransport,
    );
  }

  Future<void> _waitForIceGatheringComplete(RTCPeerConnection pc) async {
    if (pc.iceGatheringState ==
        RTCIceGatheringState.RTCIceGatheringStateComplete) {
      return;
    }

    final completer = Completer<void>();
    pc.onIceGatheringState = (state) {
      debugPrint('[WEBRTC] ICE Gathering State: $state');
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !completer.isCompleted) {
        completer.complete();
      }
    };

    // Timeout after 4 seconds so slow candidate gathering doesn't block forever
    await completer.future.timeout(const Duration(seconds: 4), onTimeout: () {
      debugPrint(
          '[WEBRTC] ICE Gathering reached timeout (4s), continuing with gathered candidates.');
    });
  }

  Future<void> _waitForDataChannelsOpen(
    RTCDataChannel control,
    RTCDataChannel data,
  ) async {
    Future<void> waitForOpen(RTCDataChannel ch) async {
      if (ch.state == RTCDataChannelState.RTCDataChannelOpen) return;
      final completer = Completer<void>();
      ch.onDataChannelState = (state) {
        debugPrint('[WEBRTC] DataChannel (${ch.label}) State: $state');
        if (state == RTCDataChannelState.RTCDataChannelOpen &&
            !completer.isCompleted) {
          completer.complete();
        }
      };
      await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          if (ch.state != RTCDataChannelState.RTCDataChannelOpen) {
            throw NetworkException(
                'DataChannel (${ch.label}) failed to open in time (state: ${ch.state})');
          }
        },
      );
    }

    await Future.wait([waitForOpen(control), waitForOpen(data)]);
  }

  /// Centralized and idempotent teardown of WebRTC peer connection, data channels, and native callbacks
  Future<void> disposeConnection({
    RTCPeerConnection? peerConnection,
    RTCDataChannel? controlChannel,
    RTCDataChannel? dataChannel,
  }) async {
    try {
      if (controlChannel != null) {
        controlChannel.onDataChannelState = null;
        controlChannel.onMessage = null;
        await controlChannel.close();
      }
    } catch (_) {}

    try {
      if (dataChannel != null) {
        dataChannel.onDataChannelState = null;
        dataChannel.onMessage = null;
        await dataChannel.close();
      }
    } catch (_) {}

    try {
      if (peerConnection != null) {
        peerConnection.onDataChannel = null;
        peerConnection.onIceGatheringState = null;
        peerConnection.onIceConnectionState = null;
        peerConnection.onSignalingState = null;
        await peerConnection.close();
        await peerConnection.dispose();
      }
    } catch (_) {}
  }
}
