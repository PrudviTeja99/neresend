# Phase 5: Driver 3 — Remote Internet Magic Wormhole Transit Relay Engine

This phase implements internet-wide peer-to-peer sharing using the **Magic Wormhole Transit Relay Protocol** over outbound TCP sockets, deterministic SHA-256 token rendezvous, 5-minute single-use session countdown, structured QR pairing, continuous socket stream splicing, and Short Authentication String (SAS) emoji verification.

---

## 🎯 Phase Goals & Objectives

1. Implement **Magic Wormhole Transit Relay Connector** via `WormholeConnectionManager` connecting outbound to `transit.magic-wormhole.io:4001` (or self-hosted transit relays).
2. Implement **Deterministic 3-Step Transit Handshake Sequence**:
   - Host generates 6-digit PIN $\to$ normalized to `transitToken = SHA-256("neresend-transit-$normalizedPin")`.
   - Host connects outbound to relay: `please relay <transitToken> for side <hostSideId>\n`.
   - Client joins with PIN/QR, computes identical `transitToken`, and connects outbound: `please relay <transitToken> for side <clientSideId>\n`.
   - Relay pairs both sockets by `transitToken`, responds `ok\n` to both sides, and splices the raw byte streams.
3. Implement **Continuous Socket Stream Invariant**:
   - `WormholeConnectionManager` listens to the raw `dart:io` `Socket` using a single continuous `StreamController<List<int>>`.
   - Any bytes arriving immediately after the `ok\n` handshake delimiter are preserved and routed seamlessly to `WormholeTransitTransport` without stream re-subscription errors.
4. Implement **Human-Friendly PIN + Token Security Model**:
   - 6-digit human PIN (`550 573`) acts as a lookup pointer and token derivation seed.
   - 5-minute single-use session countdown timer (`Expires in 4:52`).
   - Single-use consumption: session is automatically closed upon transfer completion.
5. Implement **Structured QR Code Pairing**:
   - Receiver generates QR code containing `neresend://pair?session=<id>&token=<token>&pin=<code>`.
   - Sender scans QR via `QrScannerDialog` for instant 1-tap connection with zero manual typing.
6. **100% Cellular & Firewall Penetration**:
   - Both peers initiate outbound TCP connections, cleanly penetrating 100% of mobile carrier Symmetric CGNATs (4G/5G) and strict firewalls.
   - Zero proprietary bandwidth limits or paid monthly quotas.
7. Implement **Non-Blocking High-Throughput Sender Engine**:
   - Sender streams dynamically-sized chunks (1–4 MB) directly into the TCP socket buffer and completes its session as soon as all frames are flushed, delivering maximum asynchronous network throughput.
8. Implement **SAS 3-Emoji Verification** (`🌟 🚀 🎸`) derived symmetrically from `SHA-256(localFingerprint || remoteFingerprint || PIN)`.
9. Implement **Transparent Error Handling** (`RELAY_NETWORK_ERROR`, `PIN_FORMAT_INVALID`, `PIN_EXPIRED`, `PIN_TIMEOUT`).
10. Wrap in `NeReSendTransport` (`WormholeTransitTransport`) to power `NeReSendProtocolEngine`.

---

## 📁 Directory Structure & File Map

```text
lib/
├── data/
│   ├── discovery/
│   │   └── remote_discovery_driver.dart  # Ephemeral PIN generation & countdown timer
│   └── transports/
│       └── wormhole/
│           ├── wormhole_transit_transport.dart # Implements NeReSendTransport over spliced TCP socket
│           └── wormhole_connection_manager.dart # Outbound TCP connect, token handshake & stream splicing
└── presentation/
    ├── screens/
    │   └── remote_tab_screen.dart        # Reactive Remote Tab with 5-minute countdown & QR scan button
    └── widgets/
        ├── qr_code_card.dart             # Receiver pairing QR Code renderer
        └── qr_scanner_dialog.dart        # Cross-platform live camera & image QR code scanner
```

---

## ☁️ Magic Wormhole Transit Rendezvous Architecture

```text
                  MAGIC WORMHOLE TRANSIT RELAY (Port 4001)
                                     │
                  ┌──────────────────▼──────────────────┐
                  │   Rendezvous & Stream Splice Hub    │
                  │   Token: SHA-256(neresend-transit)  │
                  └─────────┬─────────────────┬─────────┘
                            │                 │
                Outbound TCP│                 │Outbound TCP
                (Side A)    │                 │(Side B)
                  ┌─────────▼────────┐   ┌────▼─────────────┐
                  │ Device A (Host)  │   │ Device B (Sender)│
                  │ (Linux / Wi-Fi)  │   │ (Android / 4G-5G)│
                  └─────────┬────────┘   └────┬─────────────┘
                            │                 │
                            └=================┘
                     End-to-End Encrypted Duplex Stream
                  (NeReSend Binary Framing & SAS Emojis)
```

### 1. The Deterministic 3-Step Handshake Protocol
```text
1. Receiver (Host)           2. Transit Relay (:4001)        3. Sender (Client)
   │                               │                               │
   ├─ Socket.connect(relay:4001) ─►│                               │
   ├─ "please relay <T> for A\n" ─►│ (Stored on token room)        │
   │                               │                               │
   │                               │ ◄─ Socket.connect(relay:4001) ┤
   │                               │ ◄─ "please relay <T> for B\n" ┤
   │                               ├─ Token matched!               │
   │ ◄── "ok\n" ───────────────────┤                               │
   │                               ├── "ok\n" ────────────────────►│
   │                               │                               │
   ├─ (Derive SAS Emojis)          │ (Relay blindly splices bytes) ├─ (Derive SAS Emojis)
   ▼                               ▼                               ▼
   └────────────── Single Continuous Framed ByteStream ────────────┘
```

### 2. Single Continuous Socket Stream Invariant
In Dart `dart:io`, `Socket` is a single-subscription stream. Cancelling a listener permanently closes the stream. `WormholeConnectionManager` ensures a seamless stream transition:
```dart
final socket = await Socket.connect(transitHost, transitPort);
final streamController = StreamController<List<int>>();

// Single persistent listener across handshake AND file transfer
socket.listen(
  (data) {
    if (!handshakeCompleted) {
      buffer.addAll(data);
      if (bufferContainsDelimiter) {
        handshakeCompleted = true;
        final remainder = extractRemainderBytes(buffer);
        if (remainder.isNotEmpty) streamController.add(remainder);
      }
    } else {
      streamController.add(data);
    }
  },
  onDone: () => streamController.close(),
  onError: (err) => streamController.addError(err),
);
```

### 3. SAS (Short Authentication String) Emoji Generation
* Computed as:
  $$\text{SAS Hash} = \text{SHA-256}(\text{Local\_Fingerprint} \parallel \text{Remote\_Fingerprint} \parallel \text{PIN})$$
* Maps the first 3 bytes of the hash into an emoji dictionary of 64 distinct visual symbols (e.g. `🌟 🚀 🎸`). Both peers confirm matching emojis on screen before transfer begins.

---

## 🧪 Verification & Network Simulation Tests

- [x] `test/data/wormhole_transit_transport_test.dart`:
  - Validates `FakeTransitRelayServer` in-memory transit relay token matching.
  - Validates `WormholeConnectionManager` side negotiation and `ok\n` handshake.
  - Validates `WormholeTransitTransport` binary frame transmission, chunk parsing, and closing.
- [x] `test/integration/wormhole_remote_transfer_test.dart`:
  - Full end-to-end 250 KB file transfer over transit relay with SHA-256 integrity verification.
- [x] `test/data/remote_discovery_driver_test.dart`:
  - Validates host session creation, PIN normalization, countdown progression, and QR pairing.
- [x] `test/presentation/remote_tab_lifecycle_test.dart`:
  - Validates provider loading, ready state transitions, countdown timer progression, and sequential "New PIN" regeneration.
- [x] `test/data/sas_generator_test.dart`:
  - Consistent bidirectional 3-emoji generation given identical fingerprints and session PIN.
