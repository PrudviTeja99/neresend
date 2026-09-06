# Phase 3: Driver 1 — Same-LAN Discovery & Authenticated TLS Transport

This phase builds the high-speed local network transport: standard RFC 6762 mDNS discovery, the DropFlow UDP multicast beacon fallback, and the persistent TLS 1.3 `SecureSocket` transport authenticated via Ed25519 identity signatures.

---

## 🎯 Phase Goals & Objectives

1. Implement **RFC 6762 / 6763 mDNS Discovery** (`224.0.0.251:5353`, `_dropflow._tcp.local`).
2. Implement the **DropFlow UDP Multicast Discovery Beacon** (`224.0.0.167:53317` + subnet broadcast `255.255.255.255:53317`) for restrictive network fallback.
3. Build **LocalTlsServer** (`SecureServerSocket` generating ephemeral TLS certificates signed by the device's persistent Ed25519 identity key).
4. Build **LocalTlsClient** (`SecureSocket` connector verifying the server's TLS certificate signature against its advertised Ed25519 public key).
5. Wrap the raw socket stream in `DropFlowTransport` (`LocalTlsTransport`).
6. Perform end-to-end LAN file transfer tests using the Phase 2 `DropFlowProtocolEngine`.

---

## 📁 Directory Structure & File Map

```text
lib/
├── data/
│   ├── discovery/
│   │   ├── lan_discovery_driver.dart     # Implements PeerDiscoveryPort (aggregates mDNS + UDP Beacon)
│   │   ├── mdns_discovery.dart           # RFC 6762 mDNS advertiser & listener
│   │   └── udp_discovery_beacon.dart     # Multicast 224.0.0.167:53317 beacon
│   └── transports/
│       └── local_tls/
│           ├── local_tls_transport.dart  # Implements DropFlowTransport over SecureSocket
│           ├── local_tls_server.dart     # Implements TransportPort listening on port 53318
│           ├── local_tls_client.dart     # Connects to peer over TLS 1.3
│           └── auth_handshake_handler.dart # Mutual Ed25519 session signature verification (0x00)
```

---

## 🔒 Security & Cryptographic Handshake

### Ephemeral TLS 1.3 + Application-Layer Ed25519 Session Binding
```
Sender (Client)                                          Receiver (Server)
      │                                                         │
      │ ── 1. TCP Connect (Port 53318) ───────────────────────► │
      │                                                         │
      │ ◄─ 2. TLS 1.3 Handshake (Standard Ephemeral ECDSA P256)► │ (PFS Transport Pipe Open)
      │                                                         │
      │ ── 3. [0x00 AUTH_HANDSHAKE: PubKeyA, NonceA, SigA] ──► │
      │ ◄─ 4. [0x00 AUTH_HANDSHAKE: PubKeyB, NonceB, SigB] ───┤ (Each signs Peer TLS Cert Fingerprint + Nonce)
      │                                                         │
      │    [Both peers verify Ed25519 signatures against        │
      │     advertised public keys discovered via mDNS/UDP]     │
      │                                                         │
      │ ◄─ 5. Mutually Authenticated Secure Pipe Confirmed ────► │
```

* **MitM Immunity:** An active attacker intercepting the TCP/TLS connection can present an ephemeral cert, but cannot forge the Ed25519 signature binding the session to the peer's permanent identity key.
* **100% Platform Portability:** Avoids native X.509 Ed25519 parser bugs in platform BoringSSL/SChannel implementations.

---

## 📡 Discovery Implementation Details

### 1. Standard mDNS (`mdns_discovery.dart`)
* **Service:** `_dropflow._tcp.local.`
* **Multicast Endpoint:** `224.0.0.251:5353` (IPv4) / `[FF02::FB]:5353` (IPv6)
* **TXT Records:**
  - `alias`: URL-encoded device alias (e.g. `Rahul's Laptop`)
  - `id`: Unique device identifier
  - `fingerprint`: SHA-256 fingerprint in uppercase hex
  - `port`: Port `53318`
  - `pubkey`: Base64-encoded Ed25519 public key

### 2. DropFlow UDP Multicast Beacon (`udp_discovery_beacon.dart`)
* Broadcasts every 2.5 seconds when Nearby tab is active.
* JSON payload:
  ```json
  {
    "proto": "dropflow_udp_v1",
    "id": "a1b2c3d4",
    "alias": "Rahul's Laptop",
    "port": 53318,
    "fingerprint": "A3:8F:2B:...",
    "pubkey": "base64...",
    "os": "linux"
  }
  ```

---

## 🧪 Verification & Integration Tests

- [ ] `test/data/lan_discovery_test.dart`:
  - Advertises local mDNS service and verifies remote listener catches all TXT records.
  - Broadcasts UDP multicast beacon and confirms parsing on loopback.
- [ ] `test/data/local_tls_transport_test.dart`:
  - Connects client to server over TLS 1.3 loopback.
  - Verifies Ed25519 certificate signature successfully.
  - Fails connection immediately if certificate is signed by an unrecognized key.
- [ ] `test/integration/lan_file_transfer_test.dart`:
  - Full end-to-end file transfer (100 MB synthetic file) over `LocalTlsTransport` with MD5/SHA-256 verification.

