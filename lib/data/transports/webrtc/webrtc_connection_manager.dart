import 'dart:async';
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
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  final Map<String, dynamic> configuration;

  WebRtcConnectionManager({
    this.configuration = defaultConfiguration,
  });

  /// Host creates offer and initializes 'control' & 'data' RTCDataChannels
  Future<({
    RTCPeerConnection peerConnection,
    String sdpOffer,
    RTCDataChannel controlChannel,
    RTCDataChannel dataChannel,
  })> createHostOffer() async {
    final pc = await createPeerConnection(configuration);

    final controlInit = RTCDataChannelInit()..ordered = true;
    final controlChannel = await pc.createDataChannel('control', controlInit);

    final dataInit = RTCDataChannelInit()..ordered = true;
    final dataChannel = await pc.createDataChannel('data', dataInit);
    dataChannel.bufferedAmountLowThreshold = WebRtcBackpressureStreamer.maxBufferedBytes;

    final offer = await pc.createOffer();
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
    final answerDesc = RTCSessionDescription(sdpAnswer, 'answer');
    await peerConnection.setRemoteDescription(answerDesc);

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
  Future<({
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

    final controlCompleter = Completer<RTCDataChannel>();
    final dataCompleter = Completer<RTCDataChannel>();

    pc.onDataChannel = (channel) {
      if (channel.label == 'control' && !controlCompleter.isCompleted) {
        controlCompleter.complete(channel);
      } else if (channel.label == 'data' && !dataCompleter.isCompleted) {
        channel.bufferedAmountLowThreshold = WebRtcBackpressureStreamer.maxBufferedBytes;
        dataCompleter.complete(channel);
      }
    };

    final offerDesc = RTCSessionDescription(sdpOffer, 'offer');
    await pc.setRemoteDescription(offerDesc);

    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);

    await _waitForIceGatheringComplete(pc);

    final localDesc = await pc.getLocalDescription();
    final sdp = localDesc?.sdp ?? answer.sdp ?? '';

    Future<WebRtcTransport> finalizeTransport({
      required String localFingerprint,
      required String remoteFingerprint,
      required String sessionPin,
    }) async {
      final controlChannel = await controlCompleter.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw const NetworkException('Timeout waiting for control channel'),
      );
      final dataChannel = await dataCompleter.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw const NetworkException('Timeout waiting for data channel'),
      );

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
    if (pc.iceGatheringState == RTCIceGatheringState.RTCIceGatheringStateComplete) {
      return;
    }

    final completer = Completer<void>();
    pc.onIceGatheringState = (state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete && !completer.isCompleted) {
        completer.complete();
      }
    };

    // Timeout after 3 seconds so slow candidate gathering doesn't block forever
    await completer.future.timeout(const Duration(seconds: 3), onTimeout: () {});
  }

  Future<void> _waitForDataChannelsOpen(
    RTCDataChannel control,
    RTCDataChannel data,
  ) async {
    Future<void> waitForOpen(RTCDataChannel ch) async {
      if (ch.state == RTCDataChannelState.RTCDataChannelOpen) return;
      final completer = Completer<void>();
      ch.onDataChannelState = (state) {
        if (state == RTCDataChannelState.RTCDataChannelOpen && !completer.isCompleted) {
          completer.complete();
        }
      };
      await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          if (ch.state != RTCDataChannelState.RTCDataChannelOpen) {
            throw const NetworkException('DataChannel failed to open in time');
          }
        },
      );
    }

    await Future.wait([waitForOpen(control), waitForOpen(data)]);
  }
}
