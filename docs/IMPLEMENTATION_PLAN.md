# Implementation Plan & Execution Roadmap

This document details the phased implementation plan, platform dependencies, project structure, and verification strategy for developing the cross-platform P2P File Sharing app (**Android, Linux, Windows**).

---

## 1. Technology Stack & Key Dependencies

### Flutter & Dart Layer
* **Framework:** Flutter (Channel stable, target SDK $\ge$ 3.19)
* **Architecture:** Hexagonal Architecture (Ports & Adapters)
* **Navigation Pattern:** 2-Tab Action Model (`Nearby | Remote`) with secondary History / Settings
* **State Management:** `flutter_riverpod` (v2.x) for reactive state & dependency injection
* **Cryptographic Identity & Secure Storage:**
  * `pointycastle` / `cryptography` (Ed25519 key generation & digital signatures)
  * `flutter_secure_storage` (Hardware-backed keystore on Android, SecretService on Linux, DPAPI on Windows)
  * `basic_utils` (X.509 certificate generation & signing)
* **Local Networking & Streaming:**
  * `dart:io` (RawDatagramSocket, SecureServerSocket, SecureSocket)
* **Bluetooth Low Energy (BLE):**
  * `flutter_reactive_ble` or platform-specific MethodChannels for advertising & scanning
* **Remote Internet P2P:**
  * `flutter_webrtc` (RFC 8831 Dual-Channel SCTP over DTLS over UDP: `'control'` + `'data'`)
  * `web_socket_channel` (Lightweight WebSocket signaling client for 10-min PIN & SDP exchange)
* **Storage & UI:**
  * `file_picker` for selecting files & directories
  * `path_provider` & `open_filex` for local file storage & previews
  * `permission_handler` for camera/location/Bluetooth permissions
  * `flutter_local_notifications` for background progress alerts

---

## 2. Platform Matrix & Native Capabilities

```
┌──────────────────────────────┬──────────────────┬──────────────────┬──────────────────┐
│ Capability                   │ Android          │ Linux            │ Windows          │
├──────────────────────────────┼──────────────────┼──────────────────┼──────────────────┤
│ LAN Multicast / TLS Stream   │ dart:io sockets  │ dart:io sockets  │ dart:io sockets  │
│ BLE Scan & Advertise         │ Android BLE APIs │ BlueZ (D-Bus)    │ WinRT Bluetooth  │
│ SoftAP / Wi-Fi Direct        │ LocalOnlyHotspot │ nmcli / D-Bus    │ WlanHostedNetwork│
│ WebRTC Native Shared Lib     │ libwebrtc.so     │ libwebrtc.so     │ webrtc.dll       │
│ Secure Keystore Storage      │ Android KeyStore │ Secret Service   │ Windows DPAPI    │
│ Background / Wake-Lock       │ Foreground Svc   │ D-Bus Inhibitor  │ Win32 ExecState  │
│ Storage Model                │ SAF / Scoped     │ Standard POSIX   │ Standard Win32   │
└──────────────────────────────┴──────────────────┴──────────────────┴──────────────────┘
```

---

## 3. Project Directory Structure

```text
FileSharing/
├── android/                         # Android native project & JNI libs
├── linux/                           # Linux native runner & CMake
├── windows/                         # Windows native runner & CMake
├── lib/
│   ├── main.dart
│   ├── core/
│   │   ├── constants/               # Port numbers, Multicast IPs, Protocol IDs, MAX_MANIFEST_SIZE (512 KB)
│   │   ├── crypto/                  # Identity & Cryptography Engine
│   │   │   ├── identity_manager.dart # Ed25519 keypair generation, persistence, fingerprinting
│   │   │   ├── cert_signer.dart     # Signs ephemeral X.509 certs with Ed25519 identity key
│   │   │   └── sha256_hasher.dart   # File & chunk SHA-256 helpers
│   │   ├── framing/                 # DropFlow Binary Framing Engine (Frame types, Reader/Writer)
│   │   │   ├── frame_type.dart      # Enum: manifest, accept, chunk, pause, retry, cancel
│   │   │   ├── frame_reader.dart    # Binary buffer frame parser
│   │   │   └── frame_writer.dart    # Binary buffer frame serializer
│   │   ├── integrity/               # Dynamic Chunking & Sparse Resumption Engine
│   │   │   ├── dynamic_chunk_sizer.dart # Invariant calculator (selects 1/2/4/8 MB for MAX_MANIFEST_SIZE)
│   │   │   ├── chunk_hasher.dart    # Pre-computes chunk SHA-256 array
│   │   │   ├── chunk_range.dart     # Interval arithmetic ([start, end] range set & merging)
│   │   │   └── part_file_manager.dart # .dropflow.part sidecar manager & RandomAccessFile writer
│   │   ├── errors/                  # TransferException, NetworkException, SecurityException
│   │   ├── theme/                   # App theme, Dark/Light palettes
│   │   └── utils/                   # File formatters, Speed calculator
│   ├── domain/
│   │   ├── contracts/               # DRIVEN PORTS
│   │   │   ├── peer_discovery_port.dart      # Discovery & presence advertising interface
│   │   │   ├── transport_port.dart           # Transport listener & client connector interface
│   │   │   ├── dropflow_transport.dart       # Duplex stream/frame transport abstraction
│   │   │   ├── transfer_protocol_engine.dart # Network-agnostic transfer session state machine
│   │   │   ├── direct_link_adapter.dart      # Capability-probed Direct Link port
│   │   │   ├── storage_repository.dart       # File I/O & destination directory persistence
│   │   │   ├── secure_storage_port.dart      # Hardware Keystore / Keychain for Ed25519 keys
│   │   │   └── power_manager_port.dart       # Wake locks & Wi-Fi performance locks
│   │   └── models/
│   │       ├── discovered_peer.dart # Includes identityPublicKey, fingerprint, isTrusted
│   │       ├── transfer_manifest.dart
│   │       ├── transfer_progress.dart # Includes verifiedRanges
│   │       └── transfer_mode.dart
│   ├── data/
│   │   ├── discovery/               # PEER DISCOVERY DRIVERS
│   │   │   ├── lan_discovery_driver.dart     # Standard RFC 6762 mDNS + UDP Multicast fallback
│   │   │   ├── ble_discovery_driver.dart     # BLE GATT advertisement & central scanner
│   │   │   └── remote_discovery_driver.dart  # WebSocket 10-minute PIN discovery client
│   │   ├── transports/              # AUTHENTICATED TRANSPORT IMPLEMENTATIONS
│   │   │   ├── local_tls/
│   │   │   │   ├── local_tls_transport.dart  # DropFlowTransport over persistent TLS 1.3 SecureSocket
│   │   │   │   ├── local_tls_server.dart     # SecureServerSocket presenting identity-signed cert
│   │   │   │   └── local_tls_client.dart     # SecureSocket connector validating peer Ed25519 signature
│   │   │   ├── direct_link/                  # Driver 2 Platform Hotspot/P2P Adapters
│   │   │   │   ├── android_hotspot_adapter.dart # LocalOnlyHotspot + WifiNetworkSpecifier
│   │   │   │   ├── linux_nm_adapter.dart        # NetworkManager D-Bus AP creation
│   │   │   │   ├── windows_direct_adapter.dart  # WinRT WiFiDirect / Hotspot APIs
│   │   │   │   └── unsupported_direct_adapter.dart # Reports DIRECT_LINK_UNAVAILABLE
│   │   │   └── webrtc/                       # Driver 3 WebRTC Transport
│   │   │       ├── webrtc_transport.dart     # DropFlowTransport over RFC 8831 Dual DataChannels
│   │   │       └── signaling_client.dart     # WebSocket SDP & ICE exchange client
│   │   ├── protocol/                # NETWORK-AGNOSTIC TRANSFER ENGINE & FRAMING
│   │   │   ├── dropflow_protocol_engine.dart # Agnostic transfer state machine (Sender/Receiver)
│   │   │   ├── frame_codec.dart              # FrameReader & FrameWriter (5-byte binary header)
│   │   │   ├── dynamic_chunk_sizer.dart      # Invariant calculator (Manifest <= 512 KB budget)
│   │   │   ├── chunk_hasher.dart             # Pre-computes chunk SHA-256 hash tables
│   │   │   ├── chunk_range.dart              # Sparse interval arithmetic & verifiedRanges
│   │   │   └── part_file_manager.dart        # .dropflow.part sidecar manager & RandomAccessFile writer
│   │   └── services/                # CORE SERVICES & ADAPTERS
│   │       ├── transfer_orchestrator.dart # Coordinates Discovery -> Transport -> Protocol Engine
│   │       ├── identity_service.dart      # Identity key generation, TOFU verification & trusted peer store
│   │       ├── storage_service.dart
│   │       ├── permission_service.dart
│   │       └── power_management_service.dart
│   └── presentation/                # DRIVING ADAPTERS (UI & State)
│       ├── state/                   # Riverpod providers (peers, active transfers, settings)
│       ├── screens/
│       │   ├── nearby_screen.dart   # Radar discovery, traffic-light readiness, peer bubbles
│       │   ├── remote_screen.dart   # Dedicated 10-min PIN & QR code pairing screen
│       │   ├── history_modal.dart   # Secondary transfer history view
│       │   └── settings_screen.dart # Device alias, trusted devices list, diagnostics logs
│       └── widgets/
│           ├── animated_radar_canvas.dart # Radar canvas with peer bubbles & data beams
│           ├── peer_list_view.dart        # Accessible / dense grid/list view toggle
│           ├── center_device_avatar.dart  # "🟢 Ready to receive" breathing glow node
│           ├── peer_bubble_node.dart      # Discovered peer bubble with OS badge & progress ring
│           ├── docked_transfer_bar.dart   # Spotify-style bottom mini-player bar
│           ├── transfer_progress_sheet.dart # Expanded full-screen modal dashboard
│           └── incoming_transfer_modal.dart # Bottom sheet accept/decline dialog with fingerprint badge
├── test/
└── pubspec.yaml
```

---

## 4. Phased Implementation Roadmap

### Phase 1: Foundation, Domain Models & Device Identity
* [ ] Initialize Flutter multiplatform workspace (Android, Linux, Windows).
* [ ] Set up `pubspec.yaml` with core dependencies (`flutter_riverpod`, `flutter_secure_storage`, `crypto`, `file_picker`, `flutter_webrtc`, `permission_handler`).
* [ ] Implement domain models (`DiscoveredPeer`, `TransferManifest`, `TransferProgress`, `ChunkRange`, `TransferMode`).
* [ ] Implement `IdentityManager` to generate persistent Ed25519 keypair on first launch and store in hardware keystore.
* [ ] Define domain ports (`PeerDiscoveryPort`, `TransportPort`, `DropFlowTransport`, `TransferProtocolEngine`, `DirectLinkAdapter`, `StorageRepository`, `SecureStoragePort`, `PowerManagerPort`).
* [ ] Build the **2-Tab Primary Navigation (`Nearby | Remote`)** and secondary header icons (`History`, `Settings`).
* [ ] Implement **NearbyScreen** with the central traffic-light avatar (`🟢 Ready to receive`), floating peer bubbles, and `[ ➕ Send Files ]` action.

### Phase 2: Binary Framing, Dynamic Chunking & Network-Agnostic Protocol Engine
* [ ] Implement `FrameReader` and `FrameWriter` binary codecs (5-byte header: `[Type: 1B] [Size: 4B]`) with `MAX_FRAME_PAYLOAD_SIZE = 9,437,184 bytes (9 MB)` guard.
* [ ] Implement Frame `0x00 AUTH_HANDSHAKE` (`[32B Ed25519_PubKey] [16B Nonce] [64B Sig]`).
* [ ] Build `DynamicChunkSizer` implementing the invariant rule ($\text{Manifest} \le 512\text{ KB}$).
* [ ] Support multi-frame manifest segmentation (`MANIFEST_PART` / `MANIFEST_END`) for large batches of files exceeding 512 KB metadata.
* [ ] Build `ChunkHasher` to pre-compute dynamic SHA-256 chunk hash tables for the manifest.
* [ ] Build `PartFileManager` with `ChunkRange` interval merging, `.dropflow.part` sidecar serialization, and sparse random-access disk writes (`RandomAccessFile`).
* [ ] Implement filename path traversal sanitization and pre-transfer disk space validation.
* [ ] Implement `DropFlowProtocolEngine` as a pure, network-agnostic transfer state machine operating on any `DropFlowTransport`.
* [ ] Unit test `DropFlowProtocolEngine` using in-memory mock transports with simulated packet loss, hole filling, and pause/cancel.

### Phase 3: Driver 1 — Local TLS Transport & LAN Discovery
* [ ] Implement `LocalTlsTransport` implementing `DropFlowTransport` over Dart `SecureSocket`.
* [ ] Build `LocalTlsServer` (`SecureServerSocket` generating standard ephemeral TLS 1.3 ECDSA P-256 certs).
* [ ] Build `LocalTlsClient` with mutual application-layer Ed25519 `0x00 AUTH_HANDSHAKE` signature verification.
* [ ] Implement `LanDiscoveryDriver` (Standard RFC 6762 mDNS `224.0.0.251:5353` + DropFlow UDP Multicast `224.0.0.167:53317` fallback).
* [ ] Verify end-to-end LAN file transfer with zero UI dependencies.

### Phase 4: Driver 2 — Capability-Probed Direct Link (BLE + SoftAP)
* [ ] Implement `BleDiscoveryDriver` for GATT peripheral advertising and central scanning.
* [ ] Implement `DirectLinkAdapter` port with runtime capability probing (`checkCapabilities()`).
* [ ] Implement OS-specific adapters:
  * `AndroidHotspotAdapter` (`LocalOnlyHotspot` + `WifiNetworkSpecifier`).
  * `LinuxNmAdapter` (NetworkManager D-Bus AP creation).
  * `WindowsDirectAdapter` (WinRT WiFiDirect / Hotspot).
  * `UnsupportedDirectAdapter` (Reports `DIRECT_LINK_UNAVAILABLE`).
* [ ] Implement role negotiation and dynamic host IP exchange (`NetworkInterface.list()`) over encrypted BLE.
* [ ] Connect the resulting Direct Link socket directly to `LocalTlsTransport`.

### Phase 5: Driver 3 — Remote WebRTC P2P Engine & Cloud Signaling Bridge
* [ ] Implement `RemoteSignalingClient` WebSocket adapter for ephemeral cloud signaling (PIN/Token rendezvous & SDP/ICE candidate routing).
* [ ] Implement human-friendly rendezvous model: 6-digit PIN pointer, 128-bit session tokens, 5-minute single-use session countdown.
* [ ] Implement structured QR Code pairing (`neresend://pair?session=<id>&token=<token>&pin=<code>`) for instant 1-tap mobile pairing.
* [ ] Configure WebRTC `RTCPeerConnection` with Google STUN servers (`stun.l.google.com:19302`) and TURN relay fallback for strict symmetric NATs.
* [ ] Enforce **Data-Only SDP Negotiation** (`OfferToReceiveAudio: false`, `OfferToReceiveVideo: false`) on offer/answer generation to eliminate audio subsystem / ADM initialization on desktop/Linux.
* [ ] Implement centralized, idempotent WebRTC connection lifecycle teardown (`disposeConnection()`) for sequential regeneration, expiration, and tab disposal.
* [ ] Implement `WebRtcTransport` implementing `NeReSendTransport` over RFC 8831 Dual DataChannels:
  * `'control'` channel: Priority commands (`CANCEL`, `PAUSE`, `MANIFEST`, SAS emojis).
  * `'data'` channel: Bulk binary payload with $\le 64\text{ KB}$ sub-packetization and `bufferedAmountLowThreshold` (1 MB) backpressure.
* [ ] Implement 3-strike rate-limiting and SAS emoji verification (`🌟 🚀 🎸`).

### Phase 6: Orchestration, UI Integration & Multiplatform Packaging
* [ ] Implement `IdentityService` with TOFU (Trust-On-First-Use) fingerprint pinning and "Trusted Device" safe auto-accept.
* [ ] Implement `TransferOrchestrator` with local failover (LAN $\rightarrow$ Direct Hotspot), simultaneous open tie-breaking, and storage space validation.
* [ ] Build the **Docked Mini-Player Bar** and expanded progress dashboard with live MB/s, ETA, and cancellation.
* [ ] Implement `NearbyScreen` radar animations and traffic-light readiness state machine (`🟢/🟡/🔴`).
* [ ] Implement `RemoteTabScreen` with reactive Riverpod lifecycle, 5-minute PIN generation/pairing, dynamic QR code card (`QrCodeCard`), and cross-platform QR camera/image scanner modal (`QrScannerDialog`).
* [ ] Acquire power wake locks (`PowerManagementService`) to keep Wi-Fi and CPU active during background transfers.
* [ ] Multiplatform packaging and cross-platform verification matrix.

---

## 5. Verification & Testing Matrix

| Test Level | Scope | Tools / Methods |
| :--- | :--- | :--- |
| **Unit Tests** | Dynamic chunk sizer invariant tests, Ed25519 signature verification, `ChunkRange` interval math | `flutter_test` |
| **Sparse Resume Tests** | Inject simulated socket drops at arbitrary chunk offsets and verify hole-filling without re-downloading existing ranges | Custom mock socket loopback harness |
| **Security Tests** | MitM test harness: Inject forged self-signed certificate and confirm TLS handshake aborts | Custom invalid-cert mock socket |
| **WebRTC Dual-Channel** | Verify `< 20ms` cancel command execution over `'control'` channel during full payload saturation | Mock latency / packet-loss test harness |
| **End-to-End Tests** | Full file transfer lifecycle (Radar $\rightarrow$ Handshake $\rightarrow$ Stream $\rightarrow$ Verify $\rightarrow$ Save) | Real devices across Android, Linux, and Windows |
