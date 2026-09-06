# Phase 5: Driver 3 — Remote Internet WebRTC Engine (RFC 8831 Dual DataChannels)

This phase implements internet-wide peer-to-peer sharing using WebRTC RTCDataChannels, lightweight WebSocket PIN signaling, RFC 8831 independent SCTP stream separation, asynchronous backpressure flow control, and Short Authentication String (SAS) emoji verification.

---

## 🎯 Phase Goals & Objectives

1. Implement **RemoteDiscoveryDriver** and the lightweight **SignalingClient** for 10-minute session PIN matching (`749 312`) and SDP/ICE candidate exchange.
2. Implement **3-Strike Rate Limiting** on PIN matching to prevent brute-force attacks.
3. Configure `flutter_webrtc` `RTCPeerConnection` with public STUN servers (`stun.l.google.com:19302`) and TURN relay fallback if direct candidate pairs fail.
4. Implement **RFC 8831 Dual DataChannels**:
   - `'control'` channel: Priority stream for manifests, SAS verification, and instant $< 20\text{ ms}$ pause/cancel commands.
   - `'data'` channel: Bulk binary data stream with dynamic chunks (1–4 MB).
5. Implement the **Non-Blocking Backpressure Loop** (`bufferedAmountLowThreshold = 1 MB`) keeping client RAM under $15\text{ MB}$.
6. Implement **SAS 3-Emoji Verification** (`🌟 🚀 🎸`) derived from DTLS fingerprints.
7. Wrap in `DropFlowTransport` (`WebRtcTransport`) to power `DropFlowProtocolEngine`.

---

## 📁 Directory Structure & File Map

```text
lib/
├── data/
│   ├── discovery/
│   │   └── remote_discovery_driver.dart  # Implements PeerDiscoveryPort via 10-min PIN lookup
│   └── transports/
│       └── webrtc/
│           ├── webrtc_transport.dart     # Implements DropFlowTransport over Dual RTCDataChannels
│           ├── webrtc_connection_manager.dart # RTCPeerConnection lifecycle & ICE candidate gatherer
│           ├── signaling_client.dart     # WebSocket client for 6-digit PIN SDP swap
│           ├── webrtc_backpressure_streamer.dart # BufferedAmount watcher throttle loop
│           └── sas_generator.dart        # Derives 3-emoji SAS from DTLS public keys
```

---

## 🌐 WebRTC Pipeline & RFC 8831 Dual Streams

```
                      SINGLE WEBRTC PEER CONNECTION (DTLS / UDP)
                                           │
          ┌────────────────────────────────┴────────────────────────────────┐
          ▼                                                                 ▼
┌─────────────────────────────────┐                       ┌─────────────────────────────────┐
│ Control Channel (SCTP Stream 0) │                       │ Data Channel (SCTP Stream 1)    │
│  • Label: 'control'             │                       │  • Label: 'data'                │
│  • Ordered + Reliable           │                       │  • Ordered + Reliable           │
│  • Manifest, Accept, Decline    │                       │  • 1–4 MB Dynamic Binary Chunks │
│  • Instant PAUSE / CANCEL / SAS │                       │  • Backpressure Throttle Loop   │
└─────────────────────────────────┘                       └─────────────────────────────────┘
```

### 1. Application-Level Stream Isolation
* **Why it matters:** On lossy 4G/5G connections, packet loss on the `'data'` stream will cause TCP/SCTP re-ordering on that stream. Because `'control'` runs on independent **SCTP Stream 0**, control packets (like `CANCEL` or `PAUSE`) are processed immediately without waiting for bulk data re-ordering at the stream sequencing layer.

### 2. Backpressure Flow Control & 64 KB Sub-Packetization Algorithm
```dart
class WebRtcBackpressureStreamer {
  static const int maxBufferedBytes = 1024 * 1024; // 1 MB Backpressure Threshold
  static const int maxDataChannelPacketSize = 64 * 1024; // 64 KB MTU for libwebrtc

  /// Streams an application-level chunk (1–4 MB) sub-packetized into 64 KB wire frames
  Future<void> sendChunkSubPacketized(
    RTCDataChannel dataChannel,
    int fileIndex,
    int chunkIndex,
    Uint8List chunkBytes,
  ) async {
    final totalLen = chunkBytes.length;
    int offset = 0;

    while (offset < totalLen) {
      // Backpressure: Suspend sender read loop until native C++ buffers drain below 1 MB
      while (dataChannel.bufferedAmount > maxBufferedBytes) {
        await dataChannel.onBufferedAmountReceive;
      }

      final sliceEnd = math.min(offset + maxDataChannelPacketSize, totalLen);
      final slice = chunkBytes.sublist(offset, sliceEnd);

      // Packet Header: [4B FileIdx] [4B ChunkIdx] [4B SubOffset] [4B TotalChunkLen] [Raw Slice]
      final wirePacket = buildSubPacket(fileIndex, chunkIndex, offset, totalLen, slice);
      dataChannel.send(RTCDataChannelMessage.fromBinary(wirePacket));

      offset = sliceEnd;
    }
  }
}
```

### 3. SAS (Short Authentication String) Emoji Generation
* Computed as:
  $$\text{SAS Hash} = \text{SHA-256}(\text{Local\_DTLS\_Fingerprint} \parallel \text{Remote\_DTLS\_Fingerprint} \parallel \text{Session\_PIN})$$
* Maps the first 3 bytes of the hash into an emoji dictionary of 64 distinct visual symbols (e.g. `🌟 🚀 🎸`). Both peers confirm matching emojis on screen before transfer begins.

---

## 🧪 Verification & Network Simulation Tests

- [ ] `test/data/signaling_client_test.dart`:
  - Validates 10-minute PIN expiration timer.
  - Validates 3-strike invalid entry code auto-destruction.
- [ ] `test/data/sas_generator_test.dart`:
  - Consistent bidirectional 3-emoji generation given identical DTLS fingerprints.
- [ ] `test/data/webrtc_backpressure_test.dart`:
  - Verifies sender suspends chunk reading when `bufferedAmount > 1 MB`.
  - Verifies total memory consumption stays $< 15\text{ MB}$ even when sending 1 GB synthetic streams.
- [ ] `test/integration/remote_webrtc_transfer_test.dart`:
  - Full end-to-end file exchange over simulated WebRTC loopback channels with 50ms latency and 2% packet loss.

