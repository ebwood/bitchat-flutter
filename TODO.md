# BitChat Flutter — Feature Roadmap & Architecture

> Decentralized P2P encrypted messaging over Bluetooth mesh + Nostr protocol.
> Single Flutter codebase targeting iOS, Android, and macOS.

---

## Architecture

```
lib/
├── models/           # Data models (BitchatPacket, BitchatMessage, PeerID, etc.)
├── protocol/         # Binary protocol codec, message padding, fragmentation
├── crypto/           # Noise Protocol (XX pattern), Ed25519, X25519
├── mesh/             # BLE central + peripheral, peer discovery, store & forward
├── nostr/            # Nostr WebSocket client, relay manager, geohash channels
├── sync/             # Gossip sync, GCS/Bloom filter deduplication
├── services/         # Message routing, command processor, notification, persistence
└── ui/               # Terminal-style chat UI, channel list, settings
```

### Protocol Stack
```
┌─────────────────────────────────────┐
│  Application Layer (BitchatMessage) │
├─────────────────────────────────────┤
│  Session Layer (BitchatPacket)      │  ← Binary codec, TTL routing, fragmentation
├─────────────────────────────────────┤
│  Encryption Layer (Noise XX)        │  ← X25519 + ChaCha20-Poly1305 + SHA256
├─────────────────────────────────────┤
│  Transport Layer (BLE / Nostr)      │  ← Platform channels for BLE, WebSocket for Nostr
└─────────────────────────────────────┘
```

---

## Phase 1 — Core Protocol (Pure Dart) ✅ DONE

- [x] Binary protocol encode/decode (`BitchatPacket` ↔ bytes)
  - 14-byte v1 header (version, type, ttl, timestamp, flags, payloadLen)
  - 8-byte sender ID, optional 8-byte recipient ID
  - PKCS#7 padding to 256/512/1024/2048 block sizes
  - Big-endian byte order
- [x] `BitchatMessage` binary codec (flags, timestamp, id, sender, content, optional fields)
- [x] Message types: announce(0x01), message(0x02), leave(0x03), noiseHandshake(0x10), noiseEncrypted(0x11), fragment(0x20), requestSync(0x21), fileTransfer(0x22)
- [x] PeerID (8-byte truncated, hex string representation)
- [x] IRC command parser (/j, /msg, /w, /block, /clear, /pass, /transfer, /save)
- [x] Terminal-style dark theme chat screen + app shell
- [x] Unit tests — 19 passing (protocol round-trip, padding, commands)
- [ ] Message deduplication (Bloom filter) — deferred to Phase 4

## Phase 2 — Crypto Layer ✅ DONE

- [x] Ed25519/X25519 key generation
- [x] Noise Protocol XX handshake (3-message pattern)
  - `Noise_XX_25519_ChaChaPoly_SHA256`
  - Message pattern: → e, ← e ee s es, → s se
- [x] Noise session manager (create, rekey, cleanup)
- [x] Noise transport message encrypt/decrypt
- [x] Channel encryption (PBKDF2 key derivation + AES-256-GCM)
- [x] Secure key storage (flutter_secure_storage)
- [x] Fingerprint verification (hash of static public key)
- [x] Unit tests for crypto round-trip — 11 passing

## Phase 3 — Nostr Protocol ✅ DONE

- [x] Nostr event model (NIP-01) with BIP-340 Schnorr signing (secp256k1/pointycastle)
- [x] Subscription filter with tag support
- [x] WebSocket relay manager (connect, reconnect, subscribe, dedup, geohash routing)
- [x] Geohash channel events (kind 20000/20001)
- [x] NIP-17 gift wrap filter support
- [x] Unit tests — 20 passing

## Phase 4 — BLE Mesh Networking ✅

- [x] BLE scanning — Central mode (flutter_blue_plus)
- [x] Peer discovery and connection lifecycle (BLEPeerManager)
- [x] Message relay with TTL decrement
- [x] Fragmentation / reassembly (182-byte default fragments)
- [x] Message deduplication (time-bounded seen-set)
- [x] Connection budget, exponential backoff, RSSI-based priority
- [x] Unit tests — 14 passing
- [ ] BLE advertising — Peripheral mode (platform channel to native) — future
- [ ] Store & forward for offline peers — future
- [ ] Background service (Android foreground service, iOS background BLE) — future

## Phase 5 — UI ✅

- [x] Channel list / sidebar navigation (drawer)
- [x] IRC command input with autocomplete (suggestion chips)
- [x] Peer list with RSSI signal indicators
- [x] Settings / profile screen (nickname, fingerprint, peer ID)
- [x] Dark / light theme toggle
- [ ] Fingerprint verification view — future
- [ ] Location channels sheet (geohash map) — future

## Phase 6 — Polish & Platform ✅

- [x] Adaptive battery management (4 power modes: performance/balanced/lowPower/ultraLow)
- [x] Emergency wipe (triple-tap trigger, secure storage clear)
- [x] Zlib message compression (auto-fallback, 1-byte header marker)
- [x] Cover traffic (cryptographically random dummy packets)
- [x] Protocol version negotiation (8-byte handshake, feature flags)
- [x] Tor integration — stub (Arti FFI required for full implementation)
- [x] Push notifications — stub (flutter_local_notifications required)
- [x] Nostr relay live communication (3 public relays, send/receive via chat UI)
- [x] Unit tests — 27 passing

---

## Phase 7 — iOS Feature Parity (Missing Features)

> Features present in the original iOS `bitchat` but missing from the Flutter version.

### 7A — Media Messaging (High Priority)
_iOS files: `ImageUtils.swift`, `BlockRevealImageView.swift`, `VoiceRecorder.swift`, `VoiceNotePlaybackController.swift`, `VoiceNoteView.swift`, `WaveformView.swift`, `Waveform.swift`_

- [x] **Image sending** — pick/camera → compress to ~45KB JPEG → strip EXIF → send ✅ Sprint 1
- [x] **Image display** — block-reveal animation, blur/privacy mode ✅ Sprint 1
- [x] **Voice notes** — record audio, waveform visualization, playback controls ✅ Sprint 4
- [x] **Voice note encoding** — AAC codec (M4A), 16kHz mono, base64 transfer ✅ Sprint 4
- [x] **File transfer progress** — TransferProgressManager with state machine + progress UI ✅ Sprint 13
- [x] **MIME type detection** — 60+ extensions, category checks (image/audio/video/doc) ✅ Sprint 13

### 7B — Private Messaging (High Priority)
_iOS files: `PrivateChatManager.swift`, `NoiseEncryptionService.swift`_

- [x] **1:1 encrypted DM** — NIP-04 (ECDH + AES-256-CBC) encrypted DMs ✅ Sprint 3
- [x] **DM UI** — separate private message thread view ✅ Sprint 3
- [x] **Read receipts** — ReadReceipt model with JSON serialization ✅ Sprint 13
- [x] **Delivery status UI** — DeliveryTracker with pending/sent/delivered/read/failed states ✅ Sprint 13

### 7C — Identity & Verification (Medium Priority)
_iOS files: `SecureIdentityStateManager.swift`, `IdentityModels.swift`, `VerificationService.swift`, `VerificationViews.swift`, `FingerprintView.swift`_

- [x] **Secure identity manager** — SHA-256 fingerprints, trust levels, JSON export ✅ Sprint 6
- [x] **Fingerprint verification** — side-by-side comparison, verify/unverify ✅ Sprint 6
- [x] **QR code verification** — deterministic QR grid from fingerprint, match comparison ✅ Sprint 13
- [x] **Trust levels** — unknown/casual/trusted/verified peer states ✅ Sprint 6

### 7D — Location & Geohash Channels (Medium Priority)
_iOS files: `LocationChannelsSheet.swift`, `LocationStateManager.swift`, `GeohashPresenceService.swift`, `GeohashParticipantTracker.swift`, `GeohashPeopleList.swift`, `LocationNotesView.swift`, `LocationNotesManager.swift`, `GeoChannelCoordinator.swift`_

- [x] **Geohash-based channels** — Geohash encode/decode/neighbors, auto-discover local rooms ✅ Sprint 14
- [x] **Location channel map** — GeohashChannel with center coordinates ✅ Sprint 14
- [x] **Presence broadcasting** — GeohashPresence with 5min freshness, announce API ✅ Sprint 14
- [x] **Participant tracker** — per-channel participant list from presence data ✅ Sprint 14
- [x] **Location notes** — LocationNote pinned to geohash, CRUD operations ✅ Sprint 14
- [x] **Channel bookmarks** — bookmark/unbookmark geohash channels ✅ Sprint 14

### 7E — Gossip Sync (Medium Priority)
_iOS files: `GossipSyncManager.swift`, `GCSFilter.swift`, `RequestSyncManager.swift`, `SyncTypeFlags.swift`, `PacketIdUtil.swift`_

- [x] **GCS Bloom filter** — Golomb-coded set for message deduplication sync ✅ Sprint 10
- [x] **Gossip protocol** — GossipSyncManager with filter exchange and missing message detection ✅ Sprint 12
- [x] **Request sync** — SyncRequest + MessageRequest for explicit message requests ✅ Sprint 12
- [x] **Sync type flags** — bitmask for messages/presence/files/channels ✅ Sprint 12

### 7F — BLE Peripheral & Mesh (High Priority)
_iOS: `BLEService.swift` (210KB), Android: `MeshForegroundService.kt`, `MeshGraph.kt`, `MeshDelegateHandler.kt`_

- [x] **BLE Peripheral advertising** — Platform Channel + Swift CBPeripheralManager + Kotlin BluetoothLeAdvertiser ✅ Sprint 18
- [x] **Android foreground service** — MeshForegroundService with sticky notification + stop action ✅ Sprint 18
- [x] **Unified peer service** — UnifiedPeerService merges BLE+Nostr peers, transport/quality tracking ✅ Sprint 15
- [ ] **Mesh topology graph** — `MeshGraph.kt` (14KB) visual network graph of multi-hop peers
- [x] **Network activation** — NetworkMode (all/bleOnly/nostrOnly/auto) smart toggle ✅ Sprint 15
- [x] **Boot receiver** — BootCompletedReceiver with SharedPreferences + component toggle ✅ Sprint 18

### 7G — Chat UI Enhancements (Medium Priority)
_iOS: `ContentView.swift` (91KB), Android: `ChatViewModel.kt` (48KB), `MessageComponents.kt`, `LinkPreviewPill.kt`, `MatrixEncryptionAnimation.kt`, `PoWStatusIndicator.kt`_

- [x] **Message formatting engine** — bold, italic, code inline formatting ✅ Sprint 5
- [x] **Link detection** — URLs detected and styled with underline + blue color ✅ Sprint 7
- [x] **Peer-color palette** — deterministic unique color per peer (DJB2 hash) ✅ Sprint 5
- [x] **Rate limiter** — token bucket algorithm (burst 5, refill 1/sec, 3s cooldown) ✅ Sprint 7
- [x] **Matrix encryption animation** — per-char cycling with staggered reveal, continuous loop ✅ Sprint 9
- [x] **PoW status indicator** — compact/detailed modes, spinning shield icon during mining ✅ Sprint 9
- [x] **Payment chip** — LightningPayment model + PaymentChip widget (BTC orange, status badges) ✅ Sprint 16
- [x] **Input validation** — message ≤2000 chars, nickname 1–24 chars ✅ Sprint 7
- [x] **Favorites/bookmarks** — contacts screen with favorites, petnames, trust badges ✅ Sprint 8
- [x] **Public timeline store** — SQLite persistent message history ✅ Sprint 2
- [x] **Full-screen image viewer** — tap to view full-screen ✅ Sprint 1

### 7H — Onboarding & Permissions (Android-only, High Priority)
_Android: 14 files in `onboarding/` — permission flow, status checks_

- [x] **Onboarding coordinator** — 4-step welcome flow (intro, nickname, permissions, ready) ✅ Sprint 10
- [x] **Bluetooth check screen** — PermissionService with BLE/Location/Mic status tracking ✅ Sprint 15
- [x] **Location check screen** — permission explanations and status checks ✅ Sprint 15
- [x] **Battery optimization** — permission check (actual request needs native Android API) ✅ Sprint 16
- [x] **Permission explanations** — user-friendly screens explaining why each permission is needed ✅ Sprint 10

### 7I — Tor Integration (Android has real implementation)
_Android: `ArtiTorManager.kt` (20KB), `OkHttpProvider.kt`, `TorMode.kt`, `TorPreferenceManager.kt`_

- [ ] **Arti Tor client** — real Tor integration via Arti Rust FFI (Android has working impl)
- [x] **Tor mode preference** — TorPreferenceManager with off/whenAvailable/always modes ✅ Sprint 16
- [x] **SOCKS proxy routing** — SOCKS5 proxy config, shouldRouteThrough logic ✅ Sprint 16

### 7J — File Transfer (Android-only features)
_Android: `FileMessageItem.kt`, `FilePickerButton.kt`, `FileSendingAnimation.kt`, `FileViewerDialog.kt`, `MediaPickerOptions.kt`, `MediaSendingManager.kt`_

- [x] **File picker** — FilePickerService with pick modes, validation, size limits ✅ Sprint 16
- [x] **File message display** — file name, size, type icon in chat bubble ✅ Sprint 11
- [x] **File sending animation** — progress indicator during transfer ✅ Sprint 11
- [x] **File viewer dialog** — FileViewerService with in-app preview detection ✅ Sprint 16
- [x] **Media picker options** — unified image/file picker bottom sheet ✅ Sprint 11

### 7K — Debug Tools (Android-only)
_Android: `DebugSettingsSheet.kt` (51KB), `DebugSettingsManager.kt` (29KB), `DebugPreferenceManager.kt`, `MeshGraph.kt`_

- [x] **Debug settings panel** — network stats, encryption info, experimental toggles ✅ Sprint 11
- [x] **Mesh graph visualization** — force-directed layout with physics simulation ✅ Sprint 12
- [x] **Debug preferences** — toggle experimental features (PoW, cover traffic, compression) ✅ Sprint 11

### 7L — Localization
_iOS: `Localizable.xcstrings` (996KB — massive multi-language file)_

- [x] **i18n/l10n** — L10n manager with 10 locales, 50+ keys, EN/ZH/JA/KO translations ✅ Sprint 15

---

## Phase 8 — Remaining Native Platform Features

> These features require Swift/Kotlin/Rust native code and cannot be implemented in pure Dart.

### 8A — BLE Peripheral & Background (Native Required)
- [x] **BLE Peripheral advertising** — Platform Channel + Swift CBPeripheralManager + Kotlin BluetoothLeAdvertiser ✅ Sprint 18
- [x] **Android foreground service** — MeshForegroundService with sticky notification + stop action ✅ Sprint 18
- [x] **Boot receiver** — BootCompletedReceiver with SharedPreferences + component toggle ✅ Sprint 18

### 8B — Tor Native Integration (Rust FFI Required)
- [x] **Arti Tor client** — ArtiTorManager FFI stubs with bootstrap/shutdown lifecycle, SOCKS proxy ✅ Sprint 18

---

## Phase 9 — Mesh BLE Chat Integration 🔜

> Wire `BLEMeshService` into the Mesh mode chat UI for real BLE peer-to-peer messaging.

### 9A — Mesh Mode Chat Integration (High Priority)
- [ ] **Start BLE on Mesh mode** — Start `BLEMeshService` scanning/connecting when user selects Mesh mode
- [ ] **Receive BLE messages** — Display received `BitchatPacket` messages in Mesh chat UI
- [ ] **Send via BLE** — Broadcast outgoing chat messages via `BLEMeshService.broadcastPacket()`
- [ ] **BLE permissions** — Request Bluetooth permissions per platform (Android/iOS/macOS)
- [ ] **Peer list integration** — Wire `PeerListScreen` to actual `BLEMeshService` connected peers
- [ ] **Connection status** — Show BLE mesh peer count and connection status in UI

### 9B — Known Limitations
- macOS `flutter_blue_plus` only supports Central role (scan), not Peripheral (advertise)
- BLE range ~10-30m, requires both devices to have Bluetooth enabled
- iOS background BLE requires specific entitlements and background modes

---

## Cross-Platform Protocol Compatibility

All binary formats MUST match iOS/Android exactly:
- Packet header: 14 bytes (v1) / 16 bytes (v2)
- Byte order: big-endian throughout
- Padding: PKCS#7 to nearest 256/512/1024/2048
- BLE UUIDs: identical service + characteristic IDs
- Noise: `Noise_XX_25519_ChaChaPoly_SHA256`
- Nostr: standard NIP event format
