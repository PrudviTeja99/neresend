# System Architecture & Technical Blueprint

This document outlines the architecture, networking protocols, cryptographic identity model, UI/UX structure, and component design for the cross-platform Peer-to-Peer (P2P) File Sharing application built for **Android, Linux, and Windows** using **Flutter** and **WebRTC / Native Sockets**.

---

## 1. Architectural Pattern: Hexagonal Architecture (Ports & Adapters)

The application strictly follows **Hexagonal Architecture** (also known as the **Ports & Adapters** pattern). The core business logic is completely isolated from Flutter UI widgets, platform-specific operating system APIs, and network transport drivers.

```
                  ┌──────────────────────────────────────────────────────────┐
                  │                      OUTSIDE WORLD                       │
                  │  (Flutter UI, CLI, Network Sockets, OS APIs, File System)│
                  └────────────────────────────┬─────────────────────────────┘
                                               │
               ┌───────────────────────────────▼───────────────────────────────┐
               │                         ADAPTERS                              │
               │  Translates external tech/data formats to domain interfaces   │
               └───────────────────────────────┬───────────────────────────────┘
                                               │
                        ┌──────────────────────▼──────────────────────┐
                        │                    PORTS                    │
                        │       (Abstract Interfaces / Contracts)     │
                        └──────────────────────┬──────────────────────┘
                                               │
                                 ┌─────────────▼─────────────┐
                                 │       INSIDE / CORE       │
                                 │    TransferOrchestrator,  │
                                 │   Identity & Domain Rules │
                                 └───────────────────────────┘
```

### Components in our Hexagon:
1. **Core Domain (Inside):**
   * `TransferOrchestrator`: Coordinates discovery lifecycles, transport selection, session state, permissions, and transfer queue.
   * `TransferProtocolEngine`: Network-agnostic transfer state machine (manifests, chunk hashing, sparse range set negotiation, PartFileManager disk writes, and integrity verification).
   * `IdentityManager`: Manages long-lived Ed25519 identity keypairs, certificate signing, and trusted peer fingerprint store.
   * `TransferManifest`, `DiscoveredPeer`, `TransferProgress`, `ChunkRange`: Pure domain data entities.
2. **Ports (Interfaces):**
   * **Driving (Inbound) Port:** `TransferUseCase` API consumed by UI state notifiers.
   * **Driven (Outbound) Ports:**
     * `PeerDiscoveryPort`: Discovers and announces peer presence.
     * `TransportPort`: Establishes authenticated full-duplex communication channels (`DropFlowTransport`).
     * `DirectLinkAdapter`: Runtime capability-probed OS SoftAP / Wi-Fi Direct interface.
     * `StorageRepository`: Abstract file system read/write and part file storage.
     * `SecureStoragePort`: Hardware keystore / keychain for Ed25519 identity keys.
     * `PowerManagerPort`: Wake locks and Wi-Fi performance locks.
3. **Adapters (Implementations):**
   * **Driving Adapters:** Flutter Nearby Radar Screen, Remote P2P Screen, Docked Transfer Bar, Android Share-Sheet Receiver.
   * **Driven Adapters:**
     * **Discovery:** `LanDiscoveryDriver` (mDNS RFC 6762 + UDP Multicast Beacon), `BleDiscoveryDriver` (BLE GATT), `RemoteDiscoveryDriver` (WebSocket PIN matching).
     * **Transport:** `LocalTlsTransportDriver` (TCP + TLS 1.3 `SecureSocket`), `WebRtcTransportDriver` (RFC 8831 Dual DataChannels).
     * **Direct Link:** `AndroidHotspotAdapter`, `LinuxNetworkManagerAdapter`, `WindowsDirectAdapter`, `UnsupportedDirectAdapter`.
     * **Storage & Security:** `AndroidKeyStoreAdapter`, `LinuxSecretServiceAdapter`, `WindowsDpapiAdapter`.

---

## 2. Decoupled Core Contracts & Pipeline Architecture

DropFlow cleanly decouples **Discovery**, **Transport Connection**, and **Transfer Protocol** into independent, highly testable ports:

```
                             TRANSFER ORCHESTRATOR
                (Coordinates Discovery, Connection, & Transfer)
                                       │
        ┌──────────────────────────────┼──────────────────────────────┐
        ▼                              ▼                              ▼
 1. PeerDiscoveryPort           2. TransportPort          3. TransferProtocolEngine
        │                              │                              │
 ├── LanDiscovery               ├── LocalTlsTransport          └── DropFlowProtocolEngine
 │    • mDNS (224.0.0.251:5353) │    • TCP + TLS 1.3                • Manifest Exchange
 │    • UDP Beacon (224.0.0.167)│    • Identity-Signed Cert         • Dynamic Chunk Sizing
 ├── BleDiscovery               └── WebRtcTransport                 • Sparse Range Resume
 │    • GATT Scan/Advertise          • Dual SCTP DataChannels       • Backpressure Loop
 └── RemoteDiscovery                 • Host / STUN / TURN Relay     • PartFileManager I/O
      • WebSocket PIN Match
```

### 1. Discovery Port (`lib/domain/contracts/peer_discovery_port.dart`)
```dart
abstract class PeerDiscoveryPort {
  /// Stream of active peers discovered via this discovery mechanism
  Stream<List<DiscoveredPeer>> get onPeersChanged;

  /// Start discovering and advertising presence
  Future<void> startDiscovery();

  /// Stop discovery to save battery and network bandwidth
  Future<void> stopDiscovery();

  /// Dispose discovery resources
  Future<void> dispose();
}
```

### 2. Transport Port & Duplex Abstraction (`lib/domain/contracts/transport_port.dart`)
```dart
/// Represents an active, authenticated bidirectional transport pipe
abstract class DropFlowTransport {
  /// Stream of incoming binary frames
  Stream<DropFlowFrame> get incomingFrames;

  /// Send a framed control message (Manifest, Accept, Cancel, Pause)
  Future<void> sendFrame(DropFlowFrame frame);

  /// Send a bulk binary chunk with backpressure flow control
  Future<void> sendDataChunk(int fileIdx, int chunkIdx, List<int> chunkBytes);

  /// Close the transport connection gracefully
  Future<void> close();
}

/// Port responsible for creating and accepting DropFlowTransport instances
abstract class TransportPort {
  /// Stream of incoming authenticated connections from remote peers
  Stream<DropFlowTransport> get onIncomingTransport;

  /// Initiate an outbound connection to a discovered peer
  Future<DropFlowTransport> connect(DiscoveredPeer peer);

  /// Start listening for incoming connections
  Future<void> startListening(int port);

  /// Stop listening for connections
  Future<void> stopListening();

  /// Clean up sockets and listeners
  Future<void> dispose();
}
```

### 3. Transfer Protocol Engine (`lib/domain/contracts/transfer_protocol_engine.dart`)
```dart
/// Network-agnostic file transfer state machine operating on any DropFlowTransport
abstract class TransferProtocolEngine {
  /// Live stream of file transfer progress
  Stream<TransferProgress> get onProgress;

  /// Stream of incoming transfer requests requiring user approval
  Stream<IncomingTransferRequest> get onIncomingRequest;

  /// Run sender transfer session over an established transport
  Future<void> startSenderSession(DropFlowTransport transport, List<TransferFile> files);

  /// Accept an incoming transfer request and begin receiving
  Future<void> acceptTransfer(String transferId, String destinationDirectory);

  /// Decline an incoming transfer request
  Future<void> declineTransfer(String transferId);

  /// Pause an ongoing transfer
  Future<void> pauseTransfer(String transferId);

  /// Resume a paused transfer
  Future<void> resumeTransfer(String transferId);

  /// Cancel an ongoing transfer
  Future<void> cancelTransfer(String transferId);
}
```

---

## 3. Strict Mental Model Separation: Nearby vs. Remote

To prevent security violations, unexpected mobile data usage, and cognitive confusion, **Nearby** and **Remote** operate under strict, non-overlapping architectural boundaries:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ TAB 1: NEARBY (Physical Proximity — Local Only)                             │
│ • Scope: Devices in the same room / on same Wi-Fi / within Bluetooth range. │
│ • Transports: Driver 1 (Same-LAN) OR Driver 2 (Direct Local SoftAP).        │
│ • Protocol: Unified DropFlow Persistent Framed Stream (TLS 1.3 over TCP).   │
│ • Rule: NEVER silently falls back to the internet.                         │
│ • If Local Link Fails: Shows explicit dialog:                              │
│   "Device unreachable nearby • [ 🌐 Send Remotely via Code ]"              │
├─────────────────────────────────────────────────────────────────────────────┤
│ TAB 2: REMOTE (Global Internet — Deliberate Pairing)                        │
│ • Scope: Devices in different locations / networks across the WAN.          │
│ • Transport: Driver 3 (WebRTC Dual DataChannels over DTLS / UDP).           │
│ • Rule: ONLY initiated when a user explicitly enters a 6-digit PIN or QR.   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Unified Local Streaming Architecture (DropFlow Framed Stream)

All local transfers (LAN and Direct Hotspot) share a single, persistent full-duplex socket protocol with **Dynamic Chunk Sizing** and **Sparse Range Set Resumption**.

```
Sender                                                               Receiver
  │                                                                     │
  ├────────────────────── 1. Discovery (mDNS / Multicast / BLE) ───────┤
  │                                                                     │
  ├────────────────────── 2. TCP Connect + TLS 1.3 Handshake ──────────►│ (Single Persistent Socket)
  │                                                                     │
  ├────── 3. [FRAME_MANIFEST] (File List, Dynamic Chunk Hash Table) ───►│
  │                                                                     │
  │◄───── 4. [FRAME_ACCEPT] (Verified Ranges: [[0,500], [502,2600]]) ───┤ (Receiver sends existing chunk state)
  │                                                                     │
  ├────── 5. [FRAME_CHUNK] (Missing Chunk 501 Data) ───────────────────►│ (Hole-filling in RAM & Sparse Disk Write)
  ├────── 6. [FRAME_CHUNK] (Chunk 2601... Data) ───────────────────────►│ (Continuous high-speed stream)
  │                                                                     │
  │◄───── 7. (Optional) [FRAME_PAUSE] / [FRAME_CANCEL] ─────────────────┤ (Instant bidirectional control)
  │                                                                     │
  ├────── 8. [FRAME_COMPLETE] (All Chunks & Whole-File Hash Verified) ──►│
  │                                                                     │
  └────────────────────── Socket Closed Gracefully ─────────────────────┘
```

### Binary Frame Specification
Every message on the wire is framed with a compact 5-byte header:
```text
┌──────────────────────┬──────────────────────┬───────────────────────────────┐
│ Frame Type (1 byte)  │ Payload Size (4 B)   │ Payload Data (N bytes)        │
│ Uint8                │ Uint32 Big-Endian    │ Raw Byte Payload              │
└──────────────────────┴──────────────────────┴───────────────────────────────┘
```

* **Frame Safety Boundary:** $\text{MAX\_FRAME\_PAYLOAD\_SIZE} = 9,437,184\text{ bytes}\ (9\text{ MB})$. Any frame with $\text{Payload Size} > \text{MAX\_FRAME\_PAYLOAD\_SIZE}$ results in immediate socket termination to prevent Out-Of-Memory (OOM) attacks.

| Type Byte | Frame Name | Direction | Description |
| :---: | :--- | :---: | :--- |
| `0x00` | `AUTH_HANDSHAKE` | Full-Duplex | Carries `[32B Ed25519_PubKey] [16B Nonce] [64B Sig(Peer_TLS_Fingerprint + Nonce)]` immediately following transport connection. |
| `0x01` | `MANIFEST_REQUEST` | Sender $\rightarrow$ Receiver | Single-frame JSON metadata (transfer ID, file list, dynamic chunk hash tables) when total manifest $\le 512\text{ KB}$. |
| `0x04` | `MANIFEST_PART` | Sender $\rightarrow$ Receiver | Paginated manifest chunk ($\le 512\text{ KB}$): `[16B TransferId] [2B PartIdx] [2B TotalParts] [JSON Payload]`. |
| `0x05` | `MANIFEST_END` | Sender $\rightarrow$ Receiver | Terminal frame concluding multi-part manifest transmission; prompts receiver for acceptance. |
| `0x02` | `ACCEPT_RESPONSE` | Receiver $\rightarrow$ Sender | Approved transfer; carries `verifiedRanges: [[start, end], ...]` to resume only missing chunks. |
| `0x03` | `DECLINE_RESPONSE` | Receiver $\rightarrow$ Sender | Transfer declined by user or rejected due to `INSUFFICIENT_STORAGE`. Socket closes cleanly. |
| `0x10` | `FILE_DATA_CHUNK` | Sender $\rightarrow$ Receiver | Framed binary chunk: `[4B FileIdx] [4B ChunkIdx] [Raw Payload Bytes]`. |
| `0x20` | `PAUSE_COMMAND` | Full-Duplex | Pauses active disk reads/writes without dropping the underlying transport. |
| `0x21` | `RESUME_COMMAND` | Full-Duplex | Resumes streaming from current chunk index. |
| `0x22` | `RETRY_CHUNK` | Receiver $\rightarrow$ Sender | Requested retransmission of a single chunk that failed RAM hash check. |
| `0x30` | `CANCEL_COMMAND` | Full-Duplex | Immediately aborts the transfer and triggers cleanup of unverified part files. |
| `0xFF` | `TRANSFER_COMPLETE` | Sender $\rightarrow$ Receiver | Confirms all chunks transmitted; receiver triggers final whole-file verification. |

---

## 5. Invariant-Driven Dynamic Chunk Sizing & Sparse Resumption

DropFlow dynamically selects the smallest supported chunk size required to keep the total transfer manifest within its size budget invariant:

$$\text{MAX\_MANIFEST\_SIZE} = 512\text{ KB}\ (524,288\text{ bytes})$$

### A. Dynamic Sizing Algorithm
Instead of brittle hardcoded file-size thresholds, DropFlow calculates:
$$\text{Estimated Manifest Bytes} = \text{Metadata Bytes} + \left(\left\lceil\frac{\text{File Size}}{\text{Chunk Size}}\right\rceil \times 32\text{ bytes}\right)$$
* **Rule:** DropFlow selects the **smallest supported chunk size** where $\text{Estimated Manifest Bytes} \le \text{MAX\_MANIFEST\_SIZE}$.
* **Transport-Aware Bounds:**
  * **Nearby (LAN / Direct Hotspot):** Supports $[1\text{ MB}, 2\text{ MB}, 4\text{ MB}, 8\text{ MB}]$. Disconnections are rare, so larger chunks are safely permitted.
  * **Remote (WebRTC over WAN):** Conservatively bounded to $[1\text{ MB}, 2\text{ MB}, 4\text{ MB}]$ to minimize the retransmission penalty on lossy mobile connections.

### B. Multi-Frame Manifest Segmentation Protocol Rule
In pathological scenarios where a transfer contains thousands of individual files (e.g. 5,000 files in a large project folder), base metadata alone (filenames, paths, MIME types, whole-file hashes) can exceed $512\text{ KB}$ regardless of chunk size.

* **Strict Protocol Invariant:** Under no circumstance may an individual frame on the wire exceed $\text{MAX\_MANIFEST\_SIZE} = 512\text{ KB}$.
* **Multi-Part Fallback:** If $\text{Estimated Manifest Bytes} > 512\text{ KB}$ at the maximum allowed chunk size, DropFlow segments the manifest stream across sequential $\le 512\text{ KB}$ frames:
  ```text
  [0x04 MANIFEST_PART (Files 0..1200)] ──►
  [0x04 MANIFEST_PART (Files 1201..2500)] ──►
  [0x05 MANIFEST_END (Terminal & Summary)] ──►
  ```
  The receiver reconstructs the manifest state in memory before dispatching the user approval prompt.

---

## 6. Driver 2: Capability-Probed Direct Link Architecture (`DirectLinkAdapter`)

Router-free direct transfers (offline mobile-to-mobile, mobile-to-PC) are the most platform-heterogeneous layer of the system. Operating systems and hardware configurations differ widely in their Wi-Fi Direct and SoftAP capabilities (e.g., Ethernet-only desktop PCs, missing OS AP support, or Android API nuances).

Rather than assuming all platforms can establish the same kind of direct Wi-Fi link, DropFlow utilizes a **Capability-Probed Adapter Pattern**:

```text
DirectLinkAdapter (Abstract Port / Interface)
      │
      ├── checkCapabilities(): Future<DirectLinkCapabilities>
      │
      ├── AndroidLocalOnlyHotspotAdapter
      │     ├── Host: WifiManager.startLocalOnlyHotspot() (API 26+, local-only, zero cellular routing)
      │     └── Client: WifiNetworkSpecifier + ConnectivityManager.requestNetwork() (Android 10+)
      │
      ├── LinuxNetworkManagerAdapter
      │     ├── Host: NetworkManager D-Bus API (802-11-wireless.mode = "ap")
      │     └── Client: nmcli / NetworkManager D-Bus device connect
      │
      ├── WindowsDirectLinkAdapter
      │     ├── Host: WinRT WiFiDirectAdvertisementPublisher / Mobile Hotspot APIs
      │     └── Client: WinRT WiFiDirectDevice.FromIdAsync()
      │
      └── UnsupportedDirectLinkAdapter
            └── Reports DIRECT_LINK_UNAVAILABLE (e.g., Ethernet-only desktops, missing Wi-Fi cards)
```

### Direct Link Handshake & Graceful Fallback Flow:
1. **BLE Presence & Capability Negotiation:** Over GATT advertisement / characteristic, peers exchange `DirectLinkCapabilities` (`canHost`, `canConnect`, `supportedBands`).
2. **Role Selection:** If one device can host (e.g., Android phone via `LocalOnlyHotspot`) and the other can connect (e.g., Linux laptop), the host spins up the AP, resolves its dynamic local IP address via `NetworkInterface.list()`, and securely transfers SSID + PSK credentials and host IP over encrypted BLE.
3. **Graceful Fallback on Failure (`DIRECT_LINK_UNAVAILABLE`):**
   - If neither device can host an AP (or Wi-Fi hardware is absent), DropFlow does not crash, freeze, or hang.
   - It gracefully notifies the user with an actionable alternative:
     *`"Direct offline link unavailable on this device (No compatible Wi-Fi adapter) • [ 🌐 Send Remotely via Code ]"`*
4. **Shared Streaming Engine:** Once the Direct Link IP connection is established, DropFlow uses the **exact same authenticated persistent TLS 1.3 streaming socket** (`DropFlowStreamServer` / `DropFlowStreamClient`) as LAN transfers.

---

## 7. Remote Internet P2P Architecture: Dual-Channel SCTP Isolation (RFC 8831) & Cloud Signaling Bridge

For devices located in different cities or networks across the internet, NeReSend uses a high-performance **WebRTC Dual DataChannel Architecture** governed by **RFC 8831** coupled with an ephemeral **Cloud Signaling Rendezvous Bridge**:

```
                  INTERNET (Signaling Phase Only)
                                 │
                      ┌──────────▼──────────┐
                      │  Signaling Service  │
                      │  (WSS / Ephemeral)  │
                      │  PIN → SDP/ICE      │
                      │  Offer ↔ Answer     │
                      └───────┬───────┬─────┘
                              │       │
                          signaling signaling
                              │       │
                      ┌───────▼──┐ ┌──▼────────┐
                      │ Device A │ │ Device B  │
                      │ Receiver │ │ Sender    │
                      └───────┬──┘ └──┬────────┘
                              │       │
                              ▼       ▼
                      ┌───────────────────────┐
                      │    WebRTC ICE / STUN  │
                      └───────────┬───────────┘
                                  │
                          Can connect directly?
                             /         \
                           YES          NO
                            │            │
                            ▼            ▼
                       Direct P2P    TURN Relay
                            │            │
                            └─────┬──────┘
                                  ▼
                    RFC 8831 Dual DataChannels
                     (DTLS / SCTP over UDP)
                                  │
                          Direct P2P Files
```

### A. The Critical Architectural Distinction: Signaling Relay $\neq$ Cloud File Storage
* **Connection Establishment Only:** The signaling bridge *only* handles temporary routing of the initial $\approx 1\text{ KB}$ SDP handshake and ICE candidate messages (`create`, `join`, `offer`, `answer`, `candidate`, `close`).
* **Zero Payload in Cloud:** No file data, chunk payloads, or persistent personal metadata ever passes through or touches the signaling server.
* **Product Promise:** **"Files stream directly device-to-device with end-to-end encryption."**

### B. Human-Friendly Rendezvous & Token Security Model
* **PIN as Rendezvous Pointer, Not the Secret:** A 6-digit PIN (`550 573`) serves strictly as a human-friendly lookup pointer to a cryptographically strong 128-bit `sessionId` and short-lived `authToken`.
* **Single-Use Ephemeral Lifecycle:**
  * Receiver taps **"Receive Remotely"** $\rightarrow$ generates a session with a 5-minute countdown (`Expires in 4:52`).
  * Once pairing succeeds and the DataChannels open, the session is consumed and purged from the signaling broker immediately (`DELETE /session`).
* **Structured QR Code Invitation (`neresend://pair?...`):**
  * The receiver presents a dynamic QR code encoding:
    ```text
    neresend://pair?session=<sessionId>&token=<token>&pin=550573
    ```
  * Mobile senders scan the QR code for instant 1-tap connection with 0 typing, while the 6-digit PIN serves as a convenient manual entry fallback.

* **Cross-Platform QR Scanner Architecture (`QrScannerDialog`):**
  * **Live Camera Viewfinder (Mobile / macOS):** Utilizes `mobile_scanner` with real-time barcode recognition, torch/flashlight toggle, and front/back camera switching.
  * **Static Image QR Analysis (`analyzeImage`):** Senders can pick an image file or screenshot via `FilePicker` to extract pairing metadata directly from images without requiring camera hardware.
  * **Clipboard Auto-Paste Fallback (Desktop Linux / Windows):** Provides 1-tap clipboard paste on environments where camera drivers or permissions are unavailable.
  * **Universal Parser (`RemoteSessionInfo.parseInviteUri`):** Accepts structured URIs (`neresend://pair?...`), raw 6-digit PIN strings (`550 573` or `550573`), or session tokens interchangeably.
  * **Permissive Manifest Integration:** Configured with `<uses-permission android:name="android.permission.CAMERA" />` and `android:required="false"` camera features, allowing full installation on camera-less Android devices (tablets/emulators/STBs).

### C. NAT Traversal & TURN Fallback Guarantee
1. **Application-Level Stream Isolation (RFC 8831):** Separates `'control'` (SCTP Stream 0) and `'data'` (SCTP Stream 1) over a single DTLS association.
2. **Backpressure Flow Control:** The `'data'` channel monitors `bufferedAmountLowThreshold` (set to 1 MB), keeping RAM usage under **15 MB**.
3. **64 KB Wire Sub-Packetization:** `WebRtcTransport` sub-packetizes 1–4 MB dynamic chunks into $\le 64\text{ KB}$ wire frames (`[4B ChunkIdx] [4B SubOffset] [4B TotalChunkLen] [Raw Bytes]`), reassembled in memory by `WebRtcChunkReassembler`.
4. **ICE / STUN / TURN Resolution:**
   * Prioritizes direct host and STUN server-reflexive candidate pairs ($>85\%$ of residential connections).
   * Automatically falls back to TURN relaying when restrictive symmetric NATs or corporate/university firewalls prevent direct UDP hole-punching.
5. **Transparent UX:** The user interface abstracts all network negotiation into smooth, friendly states:
   ```text
   Idle ──► Connecting… ──► ✓ Connected (Ready to send files)
   ```

### D. Data-Only SDP Negotiation & Platform Safety
* **Elimination of Audio/Video Subsystems:** NeReSend is strictly a high-speed data transfer engine. `WebRtcConnectionManager` explicitly disables media transceiver negotiation on all SDP offers and answers:
  ```dart
  static const Map<String, dynamic> dataOnlySdpConstraints = {
    'mandatory': {
      'OfferToReceiveAudio': false,
      'OfferToReceiveVideo': false,
    },
    'optional': [],
  };
  ```
* **Desktop & Linux Headless Safety:** Disabling media negotiation prevents native `libwebrtc` from initializing the Audio Device Module (ADM), PulseAudio, or ALSA drivers, eliminating audio-related initialization crashes on desktop and Linux environments.

### E. Idempotent Resource Teardown & Sequential Regeneration Lifecycle
* **Centralized Teardown:** A single cleanup pathway (`disposeConnection()`) idempotently unbinds event listeners, closes DataChannels, terminates the `RTCPeerConnection`, and purges ephemeral signaling entries across all lifecycle events:
  - User generates a new PIN ("New PIN")
  - Remote tab is disposed or app enters background
  - Session expires after 5 minutes
  - Connection succeeds or encounters an unrecoverable network error
* **Sequential "New PIN" Allocation:** When regenerating a session, the UI immediately locks the action button (`Creating...`), sequentially destroys the prior connection and signaling entry, allocates a fresh `RTCPeerConnection`, registers the new session on the signaling bridge, and starts a fresh 5:00 countdown.
* **Reactive Provider State Machine:** `RemoteTabScreen` natively binds to `transferOrchestratorProvider` via Riverpod's `.when(loading:, error:, data:)`, eliminating silent early returns and guaranteeing the UI always matches background engine readiness.

---

## 8. Cryptographic Identity & Security Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ 1. TIER 1: LONG-LIVED DEVICE IDENTITY (Authentication & Trust)             │
│    • Generated once on cold start: Ed25519 Keypair saved to Secure Storage. │
│    • Device ID = UUID / SHA-256(Identity_Public_Key)[0..16].                │
│    • Identity Fingerprint = SHA-256(Identity_Public_Key) formatted in Hex.  │
│    • Never changes across app restarts; forms the basis of "Trusted Devices"│
├─────────────────────────────────────────────────────────────────────────────┤
│ 2. TIER 2: EPHEMERAL TRANSPORT SESSIONS (PFS & In-Flight Confidentiality)   │
│    • Every transfer session generates standard in-memory ephemeral TLS/DTLS │
│      keys (ECDSA P-256 / X25519) to guarantee Perfect Forward Secrecy (PFS).│
├─────────────────────────────────────────────────────────────────────────────┤
│ 3. TIER 3: DISCOVERY FINGERPRINT BINDING & MUTUAL SESSION HANDSHAKE         │
│    • Immediately upon transport open, peers exchange [0x00 AUTH_HANDSHAKE]. │
│    • Public key is extracted and verified against discovered endpoint       │
│      fingerprint (`SHA-256(PublicKey)`). Mismatches fail immediately with   │
│      FINGERPRINT_MISMATCH.                                                  │
│    • Verified fingerprint is matched against pinned trusted devices for     │
│      safe auto-accept or prompted to user via interactive modal.            │
├─────────────────────────────────────────────────────────────────────────────┤
│ 4. TIER 4: DATA INTEGRITY & STORAGE SAFETY                                  │
│    • In-Flight: Dynamic Chunk SHA-256 verified in RAM before disk writes.   │
│    • End-of-File: Whole-file SHA-256 verified upon 100% completion.         │
│    • Path Traversal Defense: Strict filename sanitization; writes locked to │
│      user-selected download directory.                                      │
│    • Storage Space Pre-Check: StatFs validation before accepting manifests. │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Cross-Platform Peer Authentication & Transport Security
NeReSend follows the battle-tested local network security model (similar to LocalSend):

```
Sender (Client)                                          Receiver (Server)
      │                                                         │
      │ ── 1. TCP Connect (Port 53318) ───────────────────────► │
      │                                                         │
      │ ◄─ 2. TLS 1.3 Handshake (Standard Ephemeral ECDSA P256)► │ (PFS Encrypted Transport Pipe)
      │                                                         │
      │ ── 3. [0x00 AUTH_HANDSHAKE: PubKeyA, NonceA, SigA] ──► │
      │ ◄─ 4. [0x00 AUTH_HANDSHAKE: PubKeyB, NonceB, SigB] ───┤ (Peers exchange public keys)
      │                                                         │
      │    [Both peers verify public key fingerprints against   │
      │     advertised identities discovered via mDNS/UDP]      │
      │                                                         │
      │ ◄─ 5. Authenticated Secure Pipe Confirmed ────────────► │
```

* **Transport Confidentiality & PFS:** Ephemeral TLS 1.3 (`SecureSocket`) protects all data on the wire against eavesdropping on untrusted Wi-Fi.
* **Identity Spoofing Immunity:** The connecting peer's derived fingerprint is strictly validated against the expected discovery fingerprint (`expectedRemoteFingerprint`), preventing impersonation.
* **User Authorization & Auto-Accept:** The receiver matches the verified sender fingerprint against pinned trusted devices (for automatic acceptance) or displays the interactive confirmation modal ("Accept & Save / Decline").

| Security Aspect | Driver 1 (LAN) | Driver 2 (Direct Hotspot) | Driver 3 (Remote WebRTC) |
| :--- | :--- | :--- | :--- |
| **Peer Authentication** | App-Layer Ed25519 Handshake (`0x00`) | App-Layer Ed25519 Handshake (`0x00`) | 10-Min Session PIN + SAS Emoji Match |
| **Transport Encryption** | Ephemeral TLS 1.3 (ECDSA P-256) | Ephemeral TLS 1.3 over WPA3 | WebRTC Dual DataChannels (Negotiated DTLS) |
| **Control Isolation** | Duplex Sockets | Duplex Sockets | RFC 8831 Independent SCTP Control Stream |
| **Forward Secrecy** | Yes (Ephemeral ECDHE) | Yes (Ephemeral ECDHE) | Yes (Ephemeral ECDHE) |
| **Trusted Auto-Accept** | Fingerprint Pinned in Secure Storage | Fingerprint Pinned in Secure Storage | Not permitted (Requires explicit PIN/SAS) |
| **Data Integrity** | Sparse Chunk + File SHA-256 | Sparse Chunk + File SHA-256 | Sparse Chunk + File SHA-256 |

---

## 9. Core Data Models

```dart
class DiscoveredPeer {
  final String id;
  final String alias;
  final DeviceType deviceType; // android, linux, windows
  final String ipAddress;
  final int port;
  final TransferMode supportedMode; // lan, direct, remote
  final String identityPublicKey; // Base64 encoded Ed25519 public key
  final String fingerprint; // SHA-256 of identityPublicKey (e.g. A3:8F:2B:...)
  final bool isTrusted; // True if pinned by user for auto-accept
  final DateTime lastSeen;
}

class TransferManifest {
  final String transferId;
  final String senderAlias;
  final String senderFingerprint;
  final List<TransferItem> files;
  final int totalBytes;
  final int totalFiles;
  final String createdAt;
}

class TransferItem {
  final String id;
  final String fileName;
  final int size;
  final String mimeType;
  final String wholeFileSha256;
  final int chunkSize; // Dynamically calculated (e.g. 1MB, 2MB, 4MB, 8MB)
  final int totalChunks;
  final List<String> chunkHashes; // SHA-256 per chunk
}

class ChunkRange {
  final int start;
  final int end;
  const ChunkRange(this.start, this.end);
}

class TransferProgress {
  final String transferId;
  final String currentFileName;
  final int currentFileIndex;
  final int totalFiles;
  final List<ChunkRange> verifiedRanges;
  final int currentChunkIndex;
  final int totalChunks;
  final int bytesTransferred;
  final int totalBytes;
  final double speedBytesPerSecond;
  final Duration estimatedTimeRemaining;
  final TransferStatus status; // inProgress, paused, completed, failed, cancelled
}
```
