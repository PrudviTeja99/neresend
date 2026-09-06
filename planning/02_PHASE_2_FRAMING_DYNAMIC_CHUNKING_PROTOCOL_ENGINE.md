# Phase 2: Binary Framing, Dynamic Chunking & Network-Agnostic Protocol Engine

This phase builds the core data plane of DropFlow: binary framing, the invariant dynamic chunk sizer, multi-part manifest segmentation, sparse interval range set resumption, `.dropflow.part` sidecar disk manager, and the pure network-agnostic `DropFlowProtocolEngine`.

---

## 🎯 Phase Goals & Objectives

1. Implement the **DropFlow 5-Byte Binary Framing Codec** (`FrameReader`, `FrameWriter`, `DropFlowFrame`).
2. Build the **DynamicChunkSizer** enforcing the $\text{MAX\_MANIFEST\_SIZE} = 512\text{ KB}$ budget.
3. Implement **Multi-Frame Manifest Segmentation** (`MANIFEST_PART` / `MANIFEST_END`) for transfers with thousands of files.
4. Implement **Sparse Range Set Arithmetic** (`ChunkRange` interval union, difference, and serialization).
5. Implement the **PartFileManager** for sidecar `.dropflow.part` metadata tracking and sparse disk writes via `RandomAccessFile`.
6. Implement the **DropFlowProtocolEngine** (Pure sender and receiver transfer state machine).
7. Build a comprehensive **In-Memory Transport Test Harness** validating 100% of the protocol logic without any real network sockets.

---

## 📁 Directory Structure & File Map

```text
lib/
├── core/
│   └── protocol/
│       ├── frame_types.dart            # Enum / byte constants (0x01..0xFF)
│       ├── dropflow_frame.dart         # Data class (type, payload length, payload bytes)
│       ├── frame_reader.dart           # Stream transformer parsing continuous byte stream into frames
│       └── frame_writer.dart           # Encodes frames with 5-byte header into Uint8List
├── domain/
│   └── integrity/
│       ├── chunk_range.dart            # Interval math: [[0, 500], [502, 2600]]
│       ├── dynamic_chunk_sizer.dart    # Calculates optimal chunk size (1, 2, 4, 8 MB)
│       ├── chunk_hasher.dart           # Streamed SHA-256 chunk hash table builder
│       └── part_file_manager.dart      # Manages .dropflow.part sidecars & RandomAccessFile
└── data/
    └── protocol/
        ├── dropflow_protocol_engine.dart # Core network-agnostic transfer state machine
        ├── sender_session.dart           # Handles manifest push, chunk streaming, pause/cancel
        └── receiver_session.dart         # Handles manifest parse, range check, hole filling, hash validation
```

---

## 🧩 Protocol & Component Specifications

### 1. 5-Byte Binary Frame Layout
```text
┌─────────────────────────┬─────────────────────────┬─────────────────────────────────┐
│ Frame Type (1 Byte)     │ Payload Length (4 B)    │ Payload Bytes (N Bytes)         │
│ Uint8                   │ Uint32 Big-Endian       │ Raw Byte Data                   │
└─────────────────────────┴─────────────────────────┴─────────────────────────────────┘
```

* **Frame Boundary Guard:** $\text{MAX\_FRAME\_PAYLOAD\_SIZE} = 9,437,184\text{ bytes}\ (9\text{ MB})$. If `Payload Length > MAX_FRAME_PAYLOAD_SIZE`, `FrameReader` immediately drops the socket to prevent memory exhaustion attacks.

| Type Byte | Frame Name | Direction | Payload Description |
| :---: | :--- | :---: | :--- |
| `0x00` | `AUTH_HANDSHAKE` | Full-Duplex | `[32B Ed25519_PubKey] [16B Nonce] [64B Sig(Peer_TLS_Fingerprint + Nonce)]` |
| `0x01` | `MANIFEST_REQUEST` | Sender $\rightarrow$ Receiver | Single-frame JSON manifest (total size $\le 512\text{ KB}$) |
| `0x04` | `MANIFEST_PART` | Sender $\rightarrow$ Receiver | Paginated manifest segment: `[16B TransferId] [2B PartIdx] [2B TotalParts] [JSON]` |
| `0x05` | `MANIFEST_END` | Sender $\rightarrow$ Receiver | Terminal marker concluding multi-part manifest |
| `0x02` | `ACCEPT_RESPONSE` | Receiver $\rightarrow$ Sender | JSON with `verifiedRanges: [[start, end], ...]` |
| `0x03` | `DECLINE_RESPONSE` | Receiver $\rightarrow$ Sender | Transfer declined (carries reason code e.g. `USER_DECLINED`, `INSUFFICIENT_STORAGE`) |
| `0x10` | `FILE_DATA_CHUNK` | Sender $\rightarrow$ Receiver | `[4B FileIdx] [4B ChunkIdx] [Raw Chunk Bytes]` |
| `0x20` | `PAUSE_COMMAND` | Full-Duplex | Suspends disk reads/writes |
| `0x21` | `RESUME_COMMAND` | Full-Duplex | Resumes streaming |
| `0x22` | `RETRY_CHUNK` | Receiver $\rightarrow$ Sender | `[4B FileIdx] [4B ChunkIdx]` (Corrupted RAM hash) |
| `0x30` | `CANCEL_COMMAND` | Full-Duplex | Aborts transfer and triggers cleanup |
| `0xFF` | `TRANSFER_COMPLETE` | Sender $\rightarrow$ Receiver | All chunks sent; triggers whole-file verification |

### 2. Invariant-Driven Dynamic Chunk Sizer
```dart
class DynamicChunkSizer {
  static const int maxManifestBytes = 512 * 1024; // 524,288 bytes

  static int calculateChunkSize({
    required int totalFileSizeBytes,
    required int metadataSizeBytes,
    required bool isRemote,
  }) {
    final candidateSizes = isRemote
        ? [1024 * 1024, 2 * 1024 * 1024, 4 * 1024 * 1024]
        : [1024 * 1024, 2 * 1024 * 1024, 4 * 1024 * 1024, 8 * 1024 * 1024];

    for (final size in candidateSizes) {
      final chunkCount = (totalFileSizeBytes / size).ceil();
      final estimatedHashBytes = chunkCount * 32;
      if (metadataSizeBytes + estimatedHashBytes <= maxManifestBytes) {
        return size;
      }
    }
    return candidateSizes.last;
  }
}
```

### 3. Sparse Range Arithmetic (`ChunkRange`)
```dart
class ChunkRange {
  final int start;
  final int end; // Inclusive
  const ChunkRange(this.start, this.end);

  static List<ChunkRange> merge(List<ChunkRange> ranges) {
    if (ranges.isEmpty) return [];
    final sorted = List<ChunkRange>.from(ranges)..sort((a, b) => a.start.compareTo(b.start));
    final merged = <ChunkRange>[sorted.first];

    for (int i = 1; i < sorted.length; i++) {
      final current = sorted[i];
      final last = merged.last;
      if (current.start <= last.end + 1) {
        merged[merged.length - 1] = ChunkRange(last.start, math.max(last.end, current.end));
      } else {
        merged.add(current);
      }
    }
    return merged;
  }
}
```

### 4. PartFileManager & Sidecar `.dropflow.part`
* When receiving a file `video.mp4`, receiver writes to temporary target `video.mp4.dropflow.part`.
* Accompanying metadata sidecar: `video.mp4.dropflow.meta` stores JSON with `verifiedRanges`, `wholeFileSha256`, and `chunkSize`.
* When a chunk arrives:
  1. Compute SHA-256 in RAM; compare against manifest's expected hash.
  2. If matching, write chunk at offset `chunkIndex * chunkSize` via `RandomAccessFile.setPosition()` and `writeFrom()`.
  3. Add `ChunkRange(chunkIndex, chunkIndex)` and merge with existing verified ranges.
  4. Once `verifiedRanges == [[0, totalChunks - 1]]`, verify entire file SHA-256 and atomically rename `video.mp4.dropflow.part` $\rightarrow$ `video.mp4`.

### 5. Storage Safety & Path Traversal Sanitization
* **Path Traversal Defense:** All incoming filenames from manifests are passed through `sanitizeFilename()`, which strips directory traversal tokens (`..`, `/`, `\`), null bytes, and Windows reserved characters (`:`, `*`, `?`, `"`, `<`, `>`, `|`), resolving strictly inside the designated download directory.
* **Storage Space Pre-Check:** Prior to sending `ACCEPT_RESPONSE`, the receiver checks available disk space against `manifest.totalBytes`. If insufficient, receiver returns `DECLINE_RESPONSE` with `INSUFFICIENT_STORAGE`.

---

## 🧪 Unit Tests & In-Memory Test Suite

- [ ] `test/protocol/frame_codec_test.dart`:
  - Complete 5-byte header encoding and decoding.
  - Stream fragmentation handling (half-frame delivery, multi-frame concatenation).
- [ ] `test/integrity/dynamic_chunk_sizer_test.dart`:
  - 100 MB file selects 1 MB chunks.
  - 10 GB file selects 2 MB or 4 MB chunks.
  - 100 GB file selects 8 MB chunks.
  - Remote transfers bound to max 4 MB.
- [ ] `test/integrity/chunk_range_test.dart`:
  - Interval merging (`[[0, 100], [101, 200]]` $\rightarrow$ `[[0, 200]]`).
  - Gaps preservation (`[[0, 500], [502, 2600]]`).
- [ ] `test/integrity/part_file_manager_test.dart`:
  - Sparse random-access disk write and verifiedRanges tracking.
  - Atomic rename upon 100% completion.
- [ ] `test/protocol/dropflow_protocol_engine_test.dart`:
  - In-memory sender $\leftrightarrow$ receiver end-to-end file exchange over `MockDuplexTransport`.
  - Mid-transfer interruption and sparse resumption (hole filling missing chunk 501).
  - Instant cancellation halting disk writes.

