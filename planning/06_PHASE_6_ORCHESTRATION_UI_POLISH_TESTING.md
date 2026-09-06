# Phase 6: Orchestration, Presentation UI, Testing & Release Packaging

This final phase binds all domain ports, data drivers, and protocol engines into a cohesive user experience. It implements the `TransferOrchestrator`, rich animations (animated radar, breathing glow avatar, docked mini-player), settings, transfer history, and multiplatform packaging.

---

## 🎯 Phase Goals & Objectives

1. Implement **TransferOrchestrator** to manage discovery lifecycles, transport failover (Same-LAN $\rightarrow$ Direct Link), session queues, and out-of-range remote prompts.
2. Build the **Nearby Radar Screen** with the 0-click receiver experience, animated radar pulses, floating peer bubbles, and traffic-light readiness avatar (`🟢/🟡/🔴`).
3. Build the **Remote Screen** with 10-minute session PIN cards, QR code display/scanner, and recipient code input card.
4. Implement the **Docked Mini-Player Bar** with live MB/s, ETA, progress ring, and expanded modal sheet.
5. Implement the **Incoming Transfer Modal** with TOFU fingerprint verification, SAS emoji badges, and *"Always accept from this device"* pinning.
6. Implement **Settings Screen** (device alias, trusted devices list, diagnostics logs) and **History Modal**.
7. Acquire wake locks and Wi-Fi performance locks via **PowerManagementService**.
8. Conduct cross-platform verification and package release binaries for Android (APK), Linux (AppImage/tar.gz), and Windows (MSIX/ZIP).

---

## 📁 Directory Structure & File Map

```text
lib/
├── data/
│   └── services/
│       ├── transfer_orchestrator.dart   # Main controller coordinating Discovery, Transports, Protocol
│       ├── power_management_service.dart # WakeLock & Wi-Fi performance lock management
│       └── storage_service.dart         # Destination directory path resolution & history database
└── presentation/
    ├── state/
    │   ├── peer_list_provider.dart      # Discovered peers stream aggregator
    │   ├── active_transfer_provider.dart # Live transfer progress state notifier
    │   ├── trusted_device_provider.dart # Pinned fingerprints list
    │   └── readiness_state_provider.dart # Computes 🟢 Ready / 🟡 Scanning / 🔴 Offline
    ├── screens/
    │   ├── nearby_tab_screen.dart       # Radar canvas, central avatar, send file FAB
    │   ├── remote_tab_screen.dart       # PIN card, QR code viewer, send code input
    │   ├── history_modal.dart           # Past transfer logs with file reveal buttons
    │   └── settings_modal.dart          # Device alias, trusted peers, diagnostics
    └── widgets/
        ├── animated_radar_canvas.dart   # CustomPainter with concentric pulse rings & data beams
        ├── center_device_avatar.dart    # Breathing glow avatar with traffic-light status pill
        ├── peer_bubble_node.dart        # Floating peer node with OS icon and tap-to-send action
        ├── docked_transfer_bar.dart     # Spotify-style bottom bar with pause/cancel controls
        ├── transfer_progress_sheet.dart # Expanded modal dashboard with chunk progress & speed graph
        ├── incoming_transfer_modal.dart # Bottom sheet accept/decline with SAS emoji & fingerprint
        └── qr_code_dialog.dart          # High-contrast QR code display and camera scanner
```

---

## 📱 Core UI Flow & Widget Specifications

### 1. Traffic-Light Readiness States (`center_device_avatar.dart`)
| State | Visual | Meaning | Action Trigger |
| :---: | :---: | :--- | :--- |
| **🟢 Ready** | Green breathing glow + `Ready to receive` | Wi-Fi connected, sockets listening, 0 taps to receive | None needed |
| **🟡 Scanning** | Yellow pulse + `Searching nearby...` | Bluetooth scanning, searching for peers | None needed |
| **🔴 Offline** | Red badge + `Wi-Fi Disabled` | No network interfaces active | Tapping opens OS Wi-Fi / Bluetooth settings |

### 2. Docked Mini-Player Bar (`docked_transfer_bar.dart`)
* Persistent across all tabs (`Nearby` and `Remote`).
* Collapsed: Displays animated progress ring, active filename, transfer speed (e.g. `48.2 MB/s`), ETA (`ETA: 12s`), and quick `[ ⏸️ / ❌ ]` buttons.
* Tapping expands into `TransferProgressSheet` showing individual file statuses, chunk verification bar, and destination folder selector.

### 3. Incoming Transfer Sheet (`incoming_transfer_modal.dart`)
* Displays sender alias, OS badge, file count, and total size.
* **Security Badges:**
  - `[ 🛡️ Trusted Device ]`: Auto-accepted if fingerprint is pinned.
  - `[ ⚠️ New Device: A3:8F:2B:... ]`: Prompts user with Trust on First Use (TOFU).
  - Remote: Displays SAS Emojis (`🌟 🚀 🎸`) for visual parity confirmation.
* Action buttons: `[ ❌ Decline ]` and `[ 🟢 Accept & Save ]`.

---

## 🧪 Comprehensive Verification & Release Matrix

### 1. Automated Test Suite
- [ ] `test/presentation/peer_list_provider_test.dart`: Verifies peers update reactively from multiple discovery drivers.
- [ ] `test/presentation/active_transfer_provider_test.dart`: Validates progress smoothing, speed rolling average, and state transitions.
- [ ] `test/orchestration/transfer_orchestrator_test.dart`:
  - Validates auto-accept for pinned trusted fingerprints.
  - Validates prompt fallback when physical link drops: `"Cannot reach nearby • [ Send Remotely ]"`.
  - Validates simultaneous open tie-breaking (deterministic arbitration via Ed25519 public key hash).
  - Validates storage space pre-check and `INSUFFICIENT_STORAGE` decline dispatch.

### 2. Cross-Platform Validation Matrix
| Feature | Android (10+) | Linux (Ubuntu/Debian) | Windows (10/11) |
| :--- | :---: | :---: | :---: |
| **Same-LAN mDNS / TLS** | ✅ Verified | ✅ Verified | ✅ Verified |
| **Direct Link Hotspot** | ✅ LocalOnlyHotspot | ✅ NetworkManager D-Bus | ✅ WiFiDirect API |
| **Remote WebRTC P2P** | ✅ Verified | ✅ Verified | ✅ Verified |
| **Secure KeyStore** | ✅ Android KeyStore | ✅ SecretService D-Bus | ✅ Windows DPAPI |
| **Background WakeLock** | ✅ PartialWakeLock + Wi-Fi | ✅ systemd-inhibit | ✅ SetThreadExecutionState |
| **System Tray / Min-to-Tray** | N/A | ✅ libappindicator | ✅ Win32 Tray Icon |

