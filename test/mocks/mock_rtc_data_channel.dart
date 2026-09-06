import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// In-memory paired RTCDataChannel simulation for unit and integration testing
class MockRtcDataChannel implements RTCDataChannel {
  @override
  final String label;

  @override
  final int id;

  RTCDataChannelState _state = RTCDataChannelState.RTCDataChannelOpen;
  MockRtcDataChannel? peer;

  @override
  int? bufferedAmountLowThreshold = 1024 * 1024;

  int _bufferedAmount = 0;

  @override
  void Function(RTCDataChannelMessage message)? onMessage;

  @override
  void Function(RTCDataChannelState state)? onDataChannelState;

  @override
  void Function(int current)? onBufferedAmountLow;

  @override
  void Function(int previous, int current)? onBufferedAmountChange;

  final StreamController<RTCDataChannelMessage> _messageStreamController =
      StreamController<RTCDataChannelMessage>.broadcast();
  final StreamController<RTCDataChannelState> _stateChangeStreamController =
      StreamController<RTCDataChannelState>.broadcast();

  MockRtcDataChannel({
    required this.label,
    required this.id,
  });

  static ({MockRtcDataChannel channelA, MockRtcDataChannel channelB})
      createPair({
    required String label,
    required int id,
  }) {
    final a = MockRtcDataChannel(label: label, id: id);
    final b = MockRtcDataChannel(label: label, id: id);
    a.peer = b;
    b.peer = a;
    return (channelA: a, channelB: b);
  }

  @override
  RTCDataChannelState? get state => _state;

  @override
  int? get bufferedAmount => _bufferedAmount;

  @override
  Future<int> getBufferedAmount() async => _bufferedAmount;

  @override
  Stream<RTCDataChannelMessage> get messageStream =>
      _messageStreamController.stream;

  @override
  set messageStream(Stream<RTCDataChannelMessage> stream) {}

  @override
  Stream<RTCDataChannelState> get stateChangeStream =>
      _stateChangeStreamController.stream;

  @override
  set stateChangeStream(Stream<RTCDataChannelState> stream) {}

  @override
  Future<void> send(RTCDataChannelMessage message) async {
    if (_state != RTCDataChannelState.RTCDataChannelOpen) {
      throw StateError('Cannot send on closed DataChannel');
    }

    _bufferedAmount += message.binary.length;
    scheduleMicrotask(() {
      _bufferedAmount = 0;
      onBufferedAmountLow?.call(0);
      peer?.onMessage?.call(message);
      peer?._messageStreamController.add(message);
    });
  }

  @override
  Future<void> close() async {
    _state = RTCDataChannelState.RTCDataChannelClosed;
    onDataChannelState?.call(_state);
    _stateChangeStreamController.add(_state);
  }
}
