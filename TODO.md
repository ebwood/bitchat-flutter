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
- [x] Unit tests — 27 passing
- [ ] Share extension (iOS) — future platform channel

---

## Cross-Platform Protocol Compatibility

All binary formats MUST match iOS/Android exactly:
- Packet header: 14 bytes (v1) / 16 bytes (v2)
- Byte order: big-endian throughout
- Padding: PKCS#7 to nearest 256/512/1024/2048
- BLE UUIDs: identical service + characteristic IDs
- Noise: `Noise_XX_25519_ChaChaPoly_SHA256`
- Nostr: standard NIP event format
