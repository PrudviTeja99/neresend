# DropFlow — UX/UI Architecture & Design Specification

*Comprehensive design specification for mobile (Android) and desktop (Linux / Windows).*

---

## 1. Core Philosophy & Strict Mental Model Separation

DropFlow is built on two distinct, non-overlapping operational contexts:

1. **Nearby is Purely Local (Physical Proximity):**
   * Scope: Devices in the same room / on same Wi-Fi / within Bluetooth range ($\le 10$ meters).
   * Transports: **Same-LAN** or **Direct Local SoftAP** via a single persistent TLS 1.3 duplex stream.
   * **Absolute Rule:** Nearby transfers **NEVER silently switch to the internet**. If local connectivity is impossible or the device moves out of range, the app fails cleanly and asks:  
     *`"Device out of range nearby. Would you like to create a Remote Code to send over the internet? [ 🌐 Send Remotely ]"`*
2. **Remote is Explicitly Deliberate (Cryptographic Intent):**
   * Scope: Devices in different locations / networks across the WAN.
   * Transports: **WebRTC RTCDataChannels (SCTP over DTLS over UDP, using the DTLS version negotiated by the WebRTC implementation)** with ICE / STUN / TURN.
   * Initiated **only** when a user explicitly shares or enters a 10-minute session PIN or scans a QR code.
3. **Invisible Local Networking:**
   * Within the Nearby tab, the user never configures LAN vs. Direct Hotspot. The app picks the fastest local physical route automatically.
4. **Sparse Chunk Integrity & Zero-Waste Resumption:**
   * Transfers are verified at 1 MB chunk boundaries in RAM and written sparsely to disk.
4. **Dynamic Chunk Integrity & Zero-Waste Resumption:**
   * Transfers use **Invariant-Driven Dynamic Chunk Sizing** ($1\text{ MB} - 8\text{ MB}$) to keep handshakes under 512 KB while retaining fine-grained resumption.
   * Interrupted transfers use **Sparse Range Sets** (`verifiedRanges: [[0, 500], [502, 2600]]`) to fill missing holes with zero wasted re-downloads.

---

## 2. Primary Information Architecture (2-Tab Model)

The primary navigation consists strictly of **two action contexts**:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                             PRIMARY NAVIGATION                              │
├──────────────────────────────────────┬──────────────────────────────────────┤
│              📡 NEARBY               │               🌐 REMOTE              │
│     (Local Wi-Fi / Router-Free BLE)  │         (Cross-Internet P2P)         │
└──────────────────────────────────────┴──────────────────────────────────────┘
                                       │
┌──────────────────────────────────────▼──────────────────────────────────────┐
│                            SECONDARY LOCATIONS                              │
├─────────────────────────────────────────────────────────────────────────────┤
│ • 🕒 History: Header icon [ 🕒 ] on Mobile  | Sidebar item on Desktop       │
│ • ⚙️ Settings: Header icon [ ⚙️ ] on Mobile | Sidebar bottom on Desktop     │
│ • ⚡ Active Transfers: Persistent Docked Mini-Player across all screens      │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Screen 1: Nearby (Hero Discovery Experience)

### Layout & Elements
* **Top Header:** App Title `DropFlow`, Grid/List View Toggle `[ ☷ ]`, History `[ 🕒 ]`, Settings `[ ⚙️ ]`.
* **Center Canvas (Radar):**
  * Soft concentric pulsating radar rings.
  * **Center Avatar (Your Device):** Device icon + alias + **Traffic-Light Readiness Badge**.
  * **Surrounding Floating Bubbles:** Discovered devices with OS icon, alias, and live connection progress ring.
* **Bottom Action:** Prominent **`[ ➕ Send Files / Photos ]`** button supporting the *Files-First* flow.

### Receiver Readiness Traffic-Light System
```
┌─────────────────────────────────────────────────────────────┐
│  🟢 Ready to receive                                        │
│     Subtle ambient breathing halo around avatar.            │
│     Everything is listening and operational.                │
├─────────────────────────────────────────────────────────────┤
│  🟡 Getting ready…                                          │
│     Subtle spinning ring during Wi-Fi/BLE startup (< 2s).   │
├─────────────────────────────────────────────────────────────┤
│  🔴 Can't receive nearby files                              │
│     Actionable banner: "Wi-Fi is off • [ Turn On Wi-Fi ]"   │
└─────────────────────────────────────────────────────────────┘
```

### Mobile Nearby Wireframe
```
┌─────────────────────────────────────────────────────────────┐
│ 🌐 DropFlow                       [ ☷ List ] [ 🕒 ] [ ⚙️ ]   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│                      ( Animated Radar )                     │
│                                                             │
│             📱 [Rahul's Phone]                              │
│                (Android)             💻 [Office PC]         │
│                                         (Windows)           │
│                                                             │
│                         🐧                                  │
│                   [Teja's Laptop]                           │
│                 ((((( 🟢 Ready )))))                        │
│                                                             │
│                                      🎧 [Alex's Tablet]     │
│                                         (Linux)             │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                 [ ➕  Send Files / Photos ]                  │
├─────────────────────────────────────────────────────────────┤
│          [ 📡 Nearby (Active) ]         [ 🌐 Remote ]       │
└─────────────────────────────────────────────────────────────┘
```

---

## 4. Screen 2: Remote (Internet P2P via PIN / QR)

Housed in a dedicated tab with clear separation between **Receiving** and **Sending**:

```
┌─────────────────────────────────────────────────────────────┐
│ 🌐 DropFlow                                  [ 🕒 ] [ ⚙️ ]   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─ 📥 TO RECEIVE FILES ──────────────────────────────────┐ │
│  │ Share your code with the sender:                       │ │
│  │                                                        │ │
│  │                 ┌─────────────────────┐                │ │
│  │                 │ █▀▀▀▀▀█ ▄ █ █▀▀▀▀▀█ │                │ │
│  │                 │ █ ███ █ █▀▄ █ ███ █ │  [ 📷 Big QR ] │ │
│  │                 │ █▀▀▀▀▀█ ▀▄▀ █▀▀▀▀▀█ │                │ │
│  │                 │ ▀▀▀▀▀▀▀ █▄█ ▀▀▀▀▀▀▀ │                │ │
│  │                 └─────────────────────┘                │ │
│  │                                                        │ │
│  │              ┌────────────────────────┐                │ │
│  │              │     7 4 9   3 1 2      │                │ │
│  │              └────────────────────────┘                │ │
│  │              ⏱️ Valid for 09:42 • [ 🔄 ]                 │ │
│  │                                                        │ │
│  │         [ 📋 Copy Code ]     [ 📤 Share Link ]         │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                             │
│  ┌─ 📤 TO SEND FILES ─────────────────────────────────────┐ │
│  │ Enter the recipient's code:                            │ │
│  │                                                        │ │
│  │     [  _ _ _   _ _ _  ]         [ 📷 Scan QR ]         │ │
│  │                                                        │ │
│  │                 [ 📁 Select Files & Send → ]           │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                             │
│         🔒 End-to-end encrypted direct WebRTC transfer       │
├─────────────────────────────────────────────────────────────┤
│          [ 📡 Nearby ]         [ 🌐 Remote (Active) ]       │
└─────────────────────────────────────────────────────────────┘
```

### Remote Conceptual Stack & Security Rules
```text
Remote
│
├── Signaling
│     └── WebSocket (10-minute session PIN matching & SDP exchange)
│
├── Connectivity
│     └── ICE (Interactive Connectivity Establishment)
│          ├── Host candidates (Direct LAN IP)
│          ├── STUN server-reflexive candidates (Public IP via stun.l.google.com)
│          └── TURN relay candidates (Fallback if ICE cannot establish a viable direct candidate pair)
│
└── Data
      └── WebRTC DataChannel
           └── SCTP
                └── DTLS (Negotiated by WebRTC implementation)
                     └── UDP
```

* **5-Minute Pairing Window:** The 6-digit PIN and dynamic QR code expire after 5 minutes (`Expires in 05:00`) if unused. Senders can tap `[ New PIN ]` to sequentially allocate a new session. Once paired, the transfer session has **no time limit**.
* **1-Tap QR Scanner Flow (`QrScannerDialog`):**
  * Senders tap the **`[ 📷 Scan QR ]`** icon inside the Remote PIN input field.
  * **Live Viewfinder (Mobile / macOS):** Launches an instant camera preview with torch/flash toggle, camera switcher, and scan viewfinder cutout.
  * **Scan Image Fallback:** Senders can tap `[ Scan Image ]` to select a saved screenshot or photo from their device gallery/file manager.
  * **Desktop Paste Fallback:** Desktop users without camera hardware tap `[ Paste ]` to populate clipboard content immediately.
* **3-Strike Auto-Destruction:** 3 failed connection attempts invalidate the code immediately.
* **SAS Verification:** During transfer approval, both screens display a 3-emoji verification code (`🌟 🚀 🎸`) to guarantee against man-in-the-middle attacks.

---

## 5. Active Transfer Feedback (Docked Mini-Player)

### A. Collapsed Docked Mini-Player (Persistent across all tabs)
```
┌─────────────────────────────────────────────────────────────┐
│ 📥 Receiving from Rahul's Galaxy • 45 MB/s • 68%       [ ⌃ ]│
│ ████████████████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
├─────────────────────────────────────────────────────────────┤
│          [ 📡 Nearby ]                  [ 🌐 Remote ]       │
└─────────────────────────────────────────────────────────────┘
```

### B. Expanded Transfer Sheet (Modal Bottom Sheet)
```
┌─────────────────────────────────────────────────────────────┐
│ 📥 Active Transfer                             [ ⌄ Minimize ]│
│ Rahul's Galaxy S24  •  45.2 MB/s  •  ETA: 4s                │
├─────────────────────────────────────────────────────────────┤
│ ✅ 1. Document_Notes.pdf     (24 MB)     [ Complete ]       │
│ ⏳ 2. Video_2026_Final.mp4   (312 MB)    [ 68% - Streaming ]│
│ ⏸️ 3. Presentation.key       (4 MB)      [ Queued ]         │
├─────────────────────────────────────────────────────────────┤
│ Saving to: Downloads/DropFlow                               │
│                                    [ ⏸️ Pause ]  [ ❌ Cancel ]│
└─────────────────────────────────────────────────────────────┘
```

---

## 6. Desktop Information Architecture (Linux & Windows)

```
┌──────────────┬──────────────────────────────────────────────────────────────┐
│ 🌐 DropFlow  │ 📡 Nearby Devices                              [ 🕒 ] [ ⚙️ ]  │
│              ├──────────────────────────────────────────────────────────────┤
│ 📡 Nearby    │                                                              │
│ 🌐 Remote    │             📱 [Rahul's Phone]                               │
│              │                (Android)             💻 [Office PC]          │
│ ──────────── │                                         (Windows)            │
│ 🕒 History   │                         🐧                                   │
│ ⚙️ Settings  │                   [Teja's Laptop]                            │
│              │                 ((((( 🟢 Ready )))))                         │
│              │                                                              │
│              │  ┌────────────────────────────────────────────────────────┐  │
│              │  │                                                        │  │
│              │  │            📂 Drag & Drop files here to send           │  │
│              │  │                   OR [ Choose Files ]                  │  │
│              │  │                                                        │  │
│              │  └────────────────────────────────────────────────────────┘  │
│              ├──────────────────────────────────────────────────────────────┤
│              │ 📥 Receiving: 2 files from Rahul • 48 MB/s • 74% [ Details ] │
└──────────────┴──────────────────────────────────────────────────────────────┘
```

---

## 7. Step-by-Step User Flows

### Flow 1: Nearby Recipient-First Transfer
1. Sender opens DropFlow $\rightarrow$ sees nearby `Rahul's Phone` on the radar.
2. Sender taps `Rahul's Phone` $\rightarrow$ native file picker opens.
3. Sender selects 2 photos and taps Send.
4. Receiver's screen shows incoming bottom sheet: *"Sender wants to send 2 photos (12 MB) [Decline] [Accept]"*.
5. Receiver taps `[ Accept ]` $\rightarrow$ docked mini-player tracks real-time progress.

### Flow 2: Offline Router-Free Direct Transfer
1. Devices are outdoors without Wi-Fi. Both open DropFlow.
2. Discovered via BLE advertising in $< 2$ seconds.
3. Sender taps peer bubble and chooses files.
4. Engine automatically establishes temporary Wi-Fi Direct / Local Hotspot AP in background.
5. High-speed direct TCP stream delivers files at 30+ MB/s. Hotspot disconnects upon completion.

### Flow 3: Nearby Out-of-Range Handling (Explicit Bridge to Remote)
1. Sender selects a nearby device, but the receiver walks out of Wi-Fi / Bluetooth range before transfer initiates.
2. Local negotiation fails.
3. **DropFlow DOES NOT secretly switch to the internet.**
4. A clean dialog appears:  
   *`"Cannot reach Rahul's Phone nearby."`*  
   *`"Would you like to generate a Remote Code to send over the internet?"`*  
   *`[ ❌ Cancel ]   [ 🌐 Create Remote Code ]`*
5. If the user clicks `[ Create Remote Code ]`, DropFlow transitions to the Remote tab with the selected files staged for transfer.

### Flow 4: Remote Internet P2P Transfer (Deliberate PIN / QR)
1. Receiver opens `[ 🌐 Remote ]` tab $\rightarrow$ reads 6-digit PIN `749 312` to sender.
2. Sender opens `[ 🌐 Remote ]` tab $\rightarrow$ enters `749 312` and selects files.
3. WebRTC ICE agent resolves connectivity (Host $\rightarrow$ STUN $\rightarrow$ TURN) and opens the `RTCDataChannel`.
4. Receiver confirms SAS emojis (`🚀 🌟 🎸`) and accepts transfer.
5. Transfer streams over SCTP/DTLS/UDP with asynchronous backpressure flow control.

### Flow 5: Sparse Resumption & Hole-Filling on Interruption
1. Connection drops mid-transfer at Chunk 2600, with a missing gap at Chunk 501.
2. Receiver writes `.dropflow.part` sidecar storing `verifiedRanges: [[0, 500], [502, 2600]]`.
3. Once reconnected, receiver sends verified ranges in `[0x02 ACCEPT_RESPONSE]`.
4. Sender calculates missing intervals and streams **only Chunk 501 and Chunks 2601..4095**.
5. Zero existing verified bytes are re-transferred.

---

## 8. UX Risk Mitigation Matrix

| Rank | UX Risk | Severity | Solution |
| :---: | :--- | :---: | :--- |
| **1** | **Closed App / Background Sleep on Android** | **CRITICAL** | Run an Android Foreground Service during active transfers with ongoing progress notification. |
| **2** | **Remote Code Confusion (Sender vs Receiver)** | **HIGH** | Explicit green card for "To Receive Files" vs blue card for "To Send Files". |
| **3** | **AP Isolation on Public Wi-Fi** | **HIGH** | Auto-failover strictly to BLE + Direct Hotspot after 1.5s LAN ping timeout (never to internet). |
| **4** | **Radar Overcrowding ($\ge 6$ devices)** | **HIGH** | Automatic fallback toggle to a 2-column Grid/List view. |
| **5** | **Android Permission Shock on Cold Start** | **MEDIUM** | Progressive in-app permission sheet explaining *why* before triggering OS prompt. |
| **6** | **Code Expiry Confusion (10-min pairing vs transfer duration)** | **MEDIUM** | Clear UI copy: "Code expires in 09:42 • Active transfers are never time-limited". |
| **7** | **Accidental Cellular Data Transfers** | **MEDIUM** | Strict boundary: Nearby never uses internet; Remote requires explicit PIN pairing + payload size alert. |
| **8** | **Screen Reader Inaccessibility** | **LOW** | Semantic DOM list behind radar canvas + accessible `[ ☷ List View ]` toggle. |
