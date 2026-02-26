<p align="center">
    <img src="https://github.com/user-attachments/assets/188c42f8-d249-4a72-b27a-e2b4f10a00a8" alt="Bitchat Logo" width="480">
</p>

<p align="center">
    <b>🔗 Flutter implementation of <a href="https://github.com/permissionlesstech/bitchat">permissionlesstech/bitchat</a></b><br>
    <i>One codebase. iOS, Android, macOS. Full feature parity.</i>
</p>

> [!WARNING]
> This software has not received external security review and may contain vulnerabilities. Do not use it for sensitive use cases until it has been reviewed. Work in progress.

# bitchat for Flutter

A secure, decentralized, peer-to-peer messaging app that works over Bluetooth mesh networks and Nostr relays. No servers, no phone numbers — just pure encrypted communication across **iOS, Android, and macOS** from a single codebase.

This is the **Flutter (cross-platform) implementation** of the original [bitchat](https://github.com/permissionlesstech/bitchat) project, combining features from the [iOS](https://github.com/nickshouse/bitchat) and [Android](https://github.com/nickshouse/bitchat-android) native apps into one unified application.

## Features

- **✅ Cross-Platform**: Single codebase for iOS, Android, and macOS
- **✅ Nostr Relay Communication**: Real-time messaging via public Nostr relays (no proximity required)
- **✅ BLE Mesh Networking**: Peer discovery and multi-hop message relay over Bluetooth LE
- **✅ End-to-End Encryption**: Noise Protocol (`XX_25519_ChaChaPoly_SHA256`) for private channels
- **✅ Channel-Based Chats**: Topic-based group messaging with channel tags
- **✅ IRC-Style Commands**: `/join`, `/nick`, `/msg`, `/who`, `/clear` and more
- **✅ Emergency Wipe**: Triple-tap to instantly clear all data
- **✅ Adaptive Battery Management**: 4 power modes (performance / balanced / lowPower / ultraLow)
- **✅ Message Compression**: Zlib compression with auto-fallback
- **✅ Cover Traffic**: Cryptographically random dummy packets to prevent traffic analysis
- **✅ Protocol Compatibility**: Binary formats match iOS/Android exactly

## Getting Started

### Prerequisites

- **Flutter**: 3.0+ with Dart 3.0+
- **Xcode**: 15+ (for iOS/macOS builds)
- **Android Studio**: Arctic Fox+ (for Android builds)

### Build & Run

```bash
# Clone the repository
git clone https://github.com/nicklauszhangdev/bitchat-flutter.git
cd bitchat-flutter

# Install dependencies
flutter pub get

# Run on connected device
flutter run

# Run tests
flutter test
```

### Platform-Specific Setup

**iOS/macOS**: Open `ios/Runner.xcworkspace` in Xcode to configure signing and capabilities (Bluetooth LE, Network).

**Android**: Ensure `minSdkVersion 21` in `android/app/build.gradle`. Bluetooth and location permissions are configured in `AndroidManifest.xml`.

## Architecture

```
lib/
├── ble/                  # Bluetooth LE mesh networking
│   ├── ble_mesh_service.dart    # BLE scanner, connection manager, mesh relay
│   └── ble_types.dart           # Packet types, peer models
├── nostr/                # Nostr protocol implementation
│   ├── nostr_event.dart         # NIP-01 event model
│   ├── nostr_relay_manager.dart # WebSocket relay connections
│   └── nostr_filter.dart        # Subscription filters
├── services/             # Application services
│   └── nostr_chat_service.dart  # Chat over Nostr relays
├── protocol/             # Binary protocol & crypto
│   ├── binary_codec.dart        # Packet encoding/decoding
│   ├── noise_handshake.dart     # Noise XX handshake
│   └── identity_key_manager.dart
├── ui/                   # User interface
│   ├── home_screen.dart         # Main screen with tabs
│   ├── chat_screen.dart         # Chat message view
│   └── settings_screen.dart     # App settings
└── main.dart
```

## Communication Channels

| Channel | Protocol | Range | Internet Required |
|---------|----------|-------|-------------------|
| **BLE Mesh** | Bluetooth Low Energy | ~30m per hop, multi-hop relay | ❌ No |
| **Nostr Relay** | WebSocket (NIP-01) | Global | ✅ Yes |

Messages are routed through whichever channel is available. BLE mesh enables offline, proximity-based chat; Nostr relays extend reach across the internet.

## Commands

| Command | Description |
|---------|-------------|
| `/join #channel` | Join or create a channel |
| `/nick name` | Set your nickname |
| `/msg @name text` | Send a private message |
| `/who` | List online users |
| `/clear` | Clear chat messages |
| `/channels` | Show discovered channels |
| `/help` | Show all commands |

## Security & Privacy

- **No Registration**: No accounts, emails, or phone numbers
- **Noise Protocol**: `Noise_XX_25519_ChaChaPoly_SHA256` for encrypted channels
- **Nostr Keys**: secp256k1 keypair for identity and message signing
- **Ephemeral by Default**: Messages exist only in device memory
- **Cover Traffic**: Random dummy packets prevent traffic analysis
- **Emergency Wipe**: Triple-tap to clear all data instantly

## Protocol Compatibility

All binary formats match the original iOS/Android implementations exactly:

- Packet header: 14 bytes (v1) / 16 bytes (v2)
- Byte order: big-endian throughout
- Padding: PKCS#7 to nearest 256/512/1024/2048
- BLE UUIDs: identical service + characteristic IDs
- Noise: `Noise_XX_25519_ChaChaPoly_SHA256`
- Nostr: standard NIP event format

## Related Projects

- **iOS**: [bitchat (original)](https://github.com/jackjackbits/bitchat) — Swift + SwiftUI
- **Android**: [bitchat-android](https://github.com/permissionlesstech/bitchat-android) — Kotlin + Jetpack Compose

## License

This project is released into the public domain. See the [LICENSE](LICENSE.md) file for details.
