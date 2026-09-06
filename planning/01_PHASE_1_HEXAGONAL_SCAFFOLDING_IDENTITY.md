# Phase 1: Hexagonal Scaffolding, Domain Entities & Device Identity

This phase establishes the foundational project structure, core domain models, abstract port contracts, cryptographic device identity system (Ed25519), and base 2-Tab UI navigation.

---

## 🎯 Phase Goals & Objectives

1. Initialize multiplatform Flutter project supporting **Android, Linux, and Windows**.
2. Configure production dependencies (`flutter_riverpod`, `flutter_secure_storage`, `crypto`, `cryptography`, `file_picker`, `permission_handler`, `flutter_webrtc`).
3. Define pure domain entities (`DiscoveredPeer`, `TransferManifest`, `TransferItem`, `TransferProgress`, `ChunkRange`, `TransferMode`).
4. Define abstract domain ports (`PeerDiscoveryPort`, `TransportPort`, `DropFlowTransport`, `TransferProtocolEngine`, `DirectLinkAdapter`, `StorageRepository`, `SecureStoragePort`, `PowerManagerPort`).
5. Implement the `IdentityManager` to generate persistent Ed25519 keypairs, compute SHA-256 fingerprints, and persist in hardware-backed secure storage.
6. Build the base Flutter presentation shell with the **2-Tab Navigation (`Nearby | Remote`)**, central avatar status, and placeholder docked transfer bar.

---

## 📁 Directory Structure & File Map

```text
lib/
├── core/
│   ├── constants/
│   │   ├── app_constants.dart          # Default ports (5353, 53317, 53318), chunk size bounds
│   │   └── protocol_constants.dart     # Magic bytes, MAX_MANIFEST_SIZE (524,288 B), MAX_FRAME_PAYLOAD_SIZE (9,437,184 B)
│   ├── errors/
│   │   ├── exceptions.dart             # DropFlowException hierarchy
│   │   └── failures.dart               # Failure types for domain/UI mapping
│   ├── theme/
│   │   ├── app_theme.dart              # Dark/Light theme definitions (Indigo/Teal palettes)
│   │   └── app_colors.dart             # Traffic-light colors (Green, Yellow, Red)
│   └── utils/
│       ├── size_formatter.dart         # B, KB, MB, GB human readable strings
│       └── speed_calculator.dart       # Rolling average MB/s & ETA estimator
├── domain/
│   ├── contracts/                      # DRIVEN PORTS (Pure Dart, Zero Flutter UI dependencies)
│   │   ├── peer_discovery_port.dart
│   │   ├── transport_port.dart
│   │   ├── dropflow_transport.dart
│   │   ├── transfer_protocol_engine.dart
│   │   ├── direct_link_adapter.dart
│   │   ├── storage_repository.dart
│   │   ├── secure_storage_port.dart
│   │   └── power_manager_port.dart
│   └── models/                         # CORE DATA ENTITIES
│       ├── discovered_peer.dart
│       ├── transfer_manifest.dart
│       ├── transfer_item.dart
│       ├── transfer_progress.dart
│       ├── chunk_range.dart
│       ├── transfer_mode.dart
│       ├── device_identity.dart
│       └── auth_handshake.dart         # Ed25519 public key, session nonce, signature
├── data/
│   └── services/
│       ├── identity_service.dart       # Ed25519 generation, Hex fingerprint, keystore storage
│       ├── secure_storage_adapter.dart # flutter_secure_storage implementation
│       └── permission_service.dart     # Wi-Fi, Bluetooth, Storage permission checks
└── presentation/
    ├── state/
    │   ├── identity_provider.dart      # Exposes current device identity & alias
    │   └── navigation_provider.dart    # 0 = Nearby, 1 = Remote
    ├── screens/
    │   ├── main_scaffold_screen.dart   # Top header, TabView, Docked Mini-Player slot
    │   ├── nearby_tab_screen.dart      # Radar discovery canvas placeholder
    │   ├── remote_tab_screen.dart      # PIN / QR code card placeholder
    │   ├── history_modal.dart          # Secondary transfer history modal
    │   └── settings_modal.dart         # Device alias editor & trusted fingerprints
    └── widgets/
        ├── center_device_avatar.dart   # Traffic-light breathing glow node
        └── docked_transfer_bar.dart    # Spotify-style bottom mini-player slot
```

---

## 🔑 Key Implementations

### 1. Cryptographic Identity Manager (`DeviceIdentity`)
```dart
class DeviceIdentity {
  final String deviceId;        // Hex SHA-256(publicKey)[0..16]
  final String alias;           // User-defined friendly name (e.g. "Rahul's Laptop")
  final String publicKeyBase64; // Ed25519 Public Key
  final String privateKeyBase64;// Ed25519 Private Key (Never sent over network)
  final String fingerprint;     // Formatted Hex SHA-256(publicKey) e.g. "A3:8F:2B:..."
}
```

* **Cold Start Workflow:**
  1. Check `SecureStoragePort` for existing keypair.
  2. If absent, generate new `Ed25519` keypair via `cryptography` package.
  3. Derive device ID and SHA-256 fingerprint formatted as uppercase hex with colons (`XX:XX:XX:...`).
  4. Persist private key securely into hardware keystore (KeyStore on Android, SecretService on Linux, DPAPI on Windows).
  5. Read default system hostname/model to initialize `alias`.

### 2. Domain Port Definitions

#### A. `PeerDiscoveryPort`
```dart
abstract class PeerDiscoveryPort {
  Stream<List<DiscoveredPeer>> get onPeersChanged;
  Future<void> startDiscovery();
  Future<void> stopDiscovery();
  Future<void> dispose();
}
```

#### B. `DropFlowTransport` & `TransportPort`
```dart
abstract class DropFlowTransport {
  Stream<DropFlowFrame> get incomingFrames;
  Future<void> sendFrame(DropFlowFrame frame);
  Future<void> sendDataChunk(int fileIdx, int chunkIdx, List<int> chunkBytes);
  Future<void> close();
}

abstract class TransportPort {
  Stream<DropFlowTransport> get onIncomingTransport;
  Future<DropFlowTransport> connect(DiscoveredPeer peer);
  Future<void> startListening(int port);
  Future<void> stopListening();
  Future<void> dispose();
}
```

#### C. `DirectLinkAdapter`
```dart
enum DirectLinkStatus { ready, permissionRequired, hardwareUnsupported, disabled }

class DirectLinkCapabilities {
  final bool canHost;
  final bool canConnect;
  final DirectLinkStatus status;
  final String? unsupportedReason;
  const DirectLinkCapabilities({
    required this.canHost,
    required this.canConnect,
    required this.status,
    this.unsupportedReason,
  });
}

abstract class DirectLinkAdapter {
  Future<DirectLinkCapabilities> checkCapabilities();
  Future<DirectLinkCredentials> startHosting();
  Future<void> connectToHost(DirectLinkCredentials credentials);
  Future<void> stop();
}
```

---

## 🧪 Unit Tests & Verification Checklist

- [ ] `test/domain/models_test.dart`: Serialization/deserialization of `DiscoveredPeer`, `TransferManifest`, `ChunkRange`.
- [ ] `test/data/identity_service_test.dart`:
  - Generates valid 32-byte Ed25519 keypair.
  - Computes exact SHA-256 formatted fingerprint (`XX:XX:...`).
  - Persists and reloads identical identity on second run.
  - Sign and verify test payload signatures.
- [ ] `test/presentation/navigation_test.dart`:
  - 2-Tab switching between `Nearby` and `Remote`.
  - Header actions correctly open `History` and `Settings`.
- [ ] `flutter analyze`: 0 warnings, 0 errors.

