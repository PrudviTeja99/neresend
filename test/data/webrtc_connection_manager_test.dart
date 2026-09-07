import 'package:flutter_test/flutter_test.dart';
import 'package:neresend/data/transports/webrtc/webrtc_connection_manager.dart';

void main() {
  group('WebRtcConnectionManager Tests', () {
    test('Data-only SDP constraints explicitly disable audio and video', () {
      const constraints = WebRtcConnectionManager.dataOnlySdpConstraints;
      expect(constraints['mandatory']['OfferToReceiveAudio'], isFalse);
      expect(constraints['mandatory']['OfferToReceiveVideo'], isFalse);
    });

    test('disposeConnection is idempotent and safely handles null parameters',
        () async {
      final manager = WebRtcConnectionManager();

      // Calling with null parameters should not throw
      await expectLater(
        manager.disposeConnection(
          peerConnection: null,
          controlChannel: null,
          dataChannel: null,
        ),
        completes,
      );

      // Calling multiple times sequentially should be safe
      await expectLater(
        manager.disposeConnection(),
        completes,
      );
    });
  });
}
