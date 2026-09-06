# NeReSend: Cross-Platform P2P File Sharing

**NeReSend** is a modern, privacy-first, cross-platform Peer-to-Peer (P2P) file-sharing application for **Android, Linux, and Windows** built with **Flutter**.

It employs **Hexagonal Architecture (Ports & Adapters)**, a **Long-Lived Cryptographic Identity (Ed25519) with Authenticated Ephemeral TLS 1.3 Sessions**, a unified **Persistent Framed Socket Protocol** with **Invariant-Driven Dynamic Chunk Sizing and Sparse Range Set Resumption**, and a high-performance **RFC 8831 Dual-Channel WebRTC Pipeline** for remote internet sharing.

---

## 🚀 Three Transfer Modes (Invisible Networking)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ 1. Same-LAN Mode (Local Network)                                            │
│    • Standard RFC 6762 mDNS & NeReSend UDP Multicast discovery.             │
│    • Single persistent TLS 1.3 socket signed by Ed25519 Identity Key.       │
│    • Invariant-driven dynamic chunk sizing (1–8 MB) & sparse resumption.    │
│    • Full-duplex real-time control (instant pause / resume / cancel).       │
├─────────────────────────────────────────────────────────────────────────────┤
│ 2. Router-Free Direct Mode (AirDrop / Quick Share Model)                    │
│    • BLE discovery & handshake with Out-of-Band Key Exchange.               │
│    • Automatically negotiates an ad-hoc Wi-Fi Direct or Local Hotspot link. │
│    • Uses the EXACT SAME authenticated NeReSend binary stream engine.       │
├─────────────────────────────────────────────────────────────────────────────┤
│ 3. Global Internet P2P Mode (Remote Cross-Network)                          │
│    • Powered by RFC 8831 Dual-Channel WebRTC (SCTP over DTLS over UDP).    │
│    • Isolated Control Stream guarantees < 20ms cancellation under load.     │
│    • Direct UDP NAT hole-punching via public Google STUN.                   │
│    • Asynchronous backpressure loop keeps RAM under 15 MB.                  │
│    • Zero-Knowledge 10-minute session PINs & QR code pairing.               │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## ✨ Key Technical Highlights

* **RFC 8831 Dual-Channel SCTP Separation:** WebRTC remote sharing multiplexes two independent SCTP streams over a single DTLS association: a `'control'` stream (preventing bulk data ordering delays on urgent cancellation/pause commands) and a dedicated `'data'` stream (with 1–4 MB dynamic chunks and backpressure flow control).
* **Invariant-Driven Dynamic Chunk Sizing:** Enforces $\text{MAX\_MANIFEST\_SIZE} = 512\text{ KB}$ budget. Automatically selects the smallest supported chunk size ($1\text{ MB} \rightarrow 2\text{ MB} \rightarrow 4\text{ MB} \rightarrow 8\text{ MB}$) based on total manifest metadata plus hash table size.
* **Sparse Range Set Resumption & Hole-Filling:** Replaces fragile scalar integers with an interval-based chunk bitmap (`verifiedRanges: [[0, 500], [502, 2600]]`). Interrupted transfers resume with zero wasted bandwidth.
* **Two-Tier Cryptographic Identity & MitM Defense:** Generated once on cold start, a persistent **Ed25519 Identity Keypair** is stored in hardware-backed keystores (Android KeyStore / Linux SecretService / Windows DPAPI). Ephemeral TLS certificates are signed by this identity key, completely eliminating local Man-in-the-Middle attacks.
* **Trusted Devices & Safe Auto-Accept:** "Always accept" rules pin the peer's permanent cryptographic identity fingerprint (`SHA-256(PublicKey)`), preventing device-name spoofing.
* **Unified Local Streaming Engine:** Replaces stateless HTTP/REST servers with a **Single Persistent Duplex Socket (`SecureSocket` over TLS 1.3)**. Driver 1 (LAN) and Driver 2 (Hotspot) share 100% of the same high-speed streaming code.
* **2-Tab Primary Navigation (`Nearby | Remote`):** Clean separation between spatial nearby radar and intentional remote internet pairing.
* **Radar on Entry:** The moment you open the app, the animated radar starts scanning and broadcasting. Receivers do not need to click any buttons (0 taps).
* **Traffic-Light Receiver Confidence:** Center avatar shows `🟢 Ready to receive` (or actionable plain-English fixes like `🔴 Can't receive • [Turn On Wi-Fi]`).

---

## 📖 Architecture & Documentation

Comprehensive design and execution documents are located in the [`docs/`](./docs) directory:

1. **[System Architecture & Blueprint](./docs/ARCHITECTURE.md):**
   * Hexagonal Architecture (Ports & Adapters) specification.
   * **RFC 8831 Dual-Channel WebRTC DataChannel Pipeline & Backpressure Specification**.
   * Invariant-Driven Dynamic Chunk Sizing & Sparse Resumption (`PartFileManager`).
   * Cryptographic Identity & Security Architecture (Long-Lived Ed25519 + Signed Ephemeral TLS).
   * NeReSend Binary Frame Protocol Specification (Frame types, Reader/Writer).
   * Strict mental model separation: Nearby (Local only) vs. Remote (Internet only).

2. **[UX/UI Design Specification](./docs/UX_DESIGN.md):**
   * Complete 2-Tab information architecture and mobile/desktop wireframes.
   * Receiver readiness states (🟢/🟡/🔴).
   * Step-by-Step user flows (Nearby, Direct, Remote PIN/QR, Sparse Resumption).
   * Top 10 UX risks and mitigation matrix.

3. **[Implementation Plan & Roadmap](./docs/IMPLEMENTATION_PLAN.md):**
   * Technology stack and cross-platform matrix (Android, Linux, Windows).
   * Project directory and module organization.
   * Granular 6-phase development roadmap.
   * Verification and testing matrix.
   * Granular 6-phase development roadmap and test plan.

4. **[Phase-by-Phase Execution Blueprints (planning/)](./planning/00_MASTER_ROADMAP.md):**
   * Detailed, file-by-file blueprints for all 6 development phases.

---

## 🛠️ Tech Stack Summary

* **UI & Presentation:** Flutter & Dart, Riverpod State Management
* **Architecture:** Hexagonal Architecture (Ports & Adapters)
* **Identity & Security:** Ed25519 Keypairs + `flutter_secure_storage` (Hardware Keystores)
* **Local Streaming (LAN & Direct):** `dart:io` (`RawDatagramSocket`, `SecureServerSocket`, `SecureSocket` with TLS 1.3)
* **Integrity Engine:** Dynamic Chunking (1–8 MB) + Sparse Range Set Resumption + Whole-File SHA-256
* **Offline Signaling:** Bluetooth Low Energy (BLE GATT peripheral & central)
* **Internet Remote P2P:** `flutter_webrtc` (RFC 8831 Dual DataChannels over DTLS over UDP)
* **Supported Platforms:** Android (10+), Linux (x86_64 / arm64), Windows (10 / 11)
