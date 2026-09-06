# Phase 4: Driver 2 — Capability-Probed Router-Free Direct Link (BLE + SoftAP)

This phase implements the offline, router-free transfer driver (similar to AirDrop / Quick Share). It uses Bluetooth Low Energy (BLE) for out-of-band discovery and credential exchange, coupled with a platform-adaptive `DirectLinkAdapter` to spin up local Wi-Fi hotspots across Android, Linux, and Windows.

---

## 🎯 Phase Goals & Objectives

1. Implement **BleDiscoveryDriver** for cross-platform BLE GATT peripheral advertising and central scanning.
2. Implement the **Capability-Probed `DirectLinkAdapter` Port** to discover runtime hardware and OS capabilities.
3. Build platform-specific adapters:
   - **AndroidHotspotAdapter:** Uses `WifiManager.startLocalOnlyHotspot()` (local-only, zero cellular routing) and `WifiNetworkSpecifier` for client connection.
   - **LinuxNmAdapter:** Uses NetworkManager D-Bus API to spawn an ad-hoc AP (`mode = "ap"`).
   - **WindowsDirectAdapter:** Uses WinRT `WiFiDirect` / Mobile Hotspot APIs.
   - **UnsupportedDirectAdapter:** Gracefully returns `DIRECT_LINK_UNAVAILABLE` on Ethernet-only PCs or missing Wi-Fi hardware.
4. Implement **Encrypted BLE Credential Exchange & Role Negotiation** (determining which device hosts the AP).
5. Hook the negotiated Direct Link IP connection directly into the Phase 3 **`LocalTlsTransport`**.

---

## 📁 Directory Structure & File Map

```text
lib/
├── data/
│   ├── discovery/
│   │   └── ble_discovery_driver.dart     # Implements PeerDiscoveryPort via BLE GATT
│   └── transports/
│       └── direct_link/
│           ├── ble_signaler.dart            # Handles GATT advertising, scanning, and encrypted read/write
│           ├── direct_link_negotiator.dart  # Role negotiation (Host vs Client selection)
│           ├── android_hotspot_adapter.dart # Android LocalOnlyHotspot + NetworkSpecifier
│           ├── linux_nm_adapter.dart        # Linux NetworkManager D-Bus Hotspot
│           ├── windows_direct_adapter.dart  # Windows WinRT WiFiDirect adapter
│           └── unsupported_direct_adapter.dart # Fallback reporting DIRECT_LINK_UNAVAILABLE
```

---

## 🔄 Direct Link Handshake & Workflow

```
Peer A (Initiator)                                            Peer B (Target)
      │                                                              │
      ├────────────────────── 1. BLE GATT Discovery ─────────────────┤
      │                                                              │
      ├────── 2. Exchange Capabilities (canHost, canConnect, bands) ─►│
      │                                                              │
      │◄───── 3. Role Decision (Peer B spins up Local Hotspot) ───────┤
      │                                                              │
      │◄───── 4. Encrypted BLE sends SSID, PSK & Host IP (Dynamic) ──┤ (Resolved via NetworkInterface.list())
      │                                                              │
      │ ── 5. Peer A connects to Peer B's Wi-Fi Hotspot ────────────►│
      │                                                              │
      │ ── 6. LocalTlsClient connects to Peer B IP:53318 ───────────►│
      │                                                              │
      └────── 7. Shared DropFlowProtocolEngine streams files ────────┘
```

---

## 🛡️ Graceful Degradation on `DIRECT_LINK_UNAVAILABLE`

If an operating system or hardware setup cannot support hosting or connecting to a direct AP (e.g. Linux desktop plugged into Ethernet without Wi-Fi card):
1. `checkCapabilities()` returns:
   ```dart
   DirectLinkCapabilities(
     canHost: false,
     canConnect: false,
     status: DirectLinkStatus.hardwareUnsupported,
     unsupportedReason: "No compatible Wi-Fi adapter detected.",
   );
   ```
2. The UI never crashes or hangs; it immediately presents the clean, non-blocking fallback dialog:  
   *`"Direct offline link unavailable on this device (No compatible Wi-Fi adapter) • [ 🌐 Send Remotely via Code ]"`*

---

## 🧪 Verification & Platform Testing Checklist

- [ ] `test/data/direct_link_negotiator_test.dart`:
  - Verified role negotiation: Android (canHost=true) + Linux (canHost=false) correctly assigns Android as AP host.
  - Two capable devices deterministically pick the host based on highest deviceId hash.
- [ ] `test/data/unsupported_direct_adapter_test.dart`:
  - Validates `DIRECT_LINK_UNAVAILABLE` error propagation to UI.
- [ ] **Platform Manual Testing:**
  - **Android:** Validates `LocalOnlyHotspot` spins up with isolated local IP (`192.168.49.1`).
  - **Linux:** Validates NetworkManager D-Bus AP activation and clean teardown.
  - **Windows:** Validates Wi-Fi Direct connection listener.

