import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Manages Ed25519 identity keys for signing and X25519 key exchange.
///
/// Ed25519 provides the public identity (peer ID). X25519 is derived
/// from the same seed for Noise Protocol key exchange.
///
/// The key pair serves three purposes:
/// 1. **Identity**: Ed25519 public key → truncated to 8 bytes = PeerID
/// 2. **Signing**: Ed25519 signs packets to prove authenticity
/// 3. **Key exchange**: X25519 (converted from Ed25519) for Noise XX handshake
class IdentityKeyManager {
  IdentityKeyManager._({
    required this.ed25519KeyPair,
    required this.x25519KeyPair,
  });

  final SimpleKeyPair ed25519KeyPair;
  final SimpleKeyPair x25519KeyPair;

  static final _ed25519 = Ed25519();

  /// Generate a fresh random identity.
  static Future<IdentityKeyManager> generate() async {
    final edKP = await _ed25519.newKeyPair();
    final edSimple = await edKP.extract();

    // Derive X25519 from Ed25519 seed
    final x25519KP = await _deriveX25519(edSimple);

    return IdentityKeyManager._(
      ed25519KeyPair: edSimple,
      x25519KeyPair: x25519KP,
    );
  }

  /// Restore from a 32-byte seed.
  static Future<IdentityKeyManager> fromSeed(Uint8List seed) async {
    if (seed.length != 32) {
      throw ArgumentError('Seed must be 32 bytes, got ${seed.length}');
    }

    final edPrivKey = await _ed25519.newKeyPairFromSeed(seed.toList());
    final edSimple = await edPrivKey.extract();
    final x25519KP = await _deriveX25519(edSimple);

    return IdentityKeyManager._(
      ed25519KeyPair: edSimple,
      x25519KeyPair: x25519KP,
    );
  }

  /// Export the 32-byte seed for persistence.
  Future<Uint8List> exportSeed() async {
    final bytes = await ed25519KeyPair.extractPrivateKeyBytes();
    return Uint8List.fromList(bytes);
  }

  /// Get the Ed25519 public key (32 bytes).
  Future<Uint8List> getPublicKey() async {
    final pubKey = await ed25519KeyPair.extractPublicKey();
    return Uint8List.fromList(pubKey.bytes);
  }

  /// Get the X25519 public key (32 bytes) for Noise handshake.
  Future<Uint8List> getX25519PublicKey() async {
    final pubKey = await x25519KeyPair.extractPublicKey();
    return Uint8List.fromList(pubKey.bytes);
  }

  /// Get the 8-byte PeerID (first 8 bytes of Ed25519 public key).
  Future<Uint8List> getPeerIDBytes() async {
    final pub = await getPublicKey();
    return Uint8List.sublistView(pub, 0, 8);
  }

  /// Get the fingerprint (SHA-256 of Ed25519 public key, as hex).
  Future<String> getFingerprint() async {
    final pub = await getPublicKey();
    final hash = await Sha256().hash(pub);
    final hex = StringBuffer();
    for (var i = 0; i < hash.bytes.length; i++) {
      if (i > 0 && i % 2 == 0) hex.write(':');
      hex.write(hash.bytes[i].toRadixString(16).padLeft(2, '0').toUpperCase());
    }
    return hex.toString();
  }

  /// Sign data with Ed25519.
  Future<Uint8List> sign(Uint8List data) async {
    final sig = await _ed25519.sign(data.toList(), keyPair: ed25519KeyPair);
    return Uint8List.fromList(sig.bytes);
  }

  /// Verify an Ed25519 signature.
  static Future<bool> verify(
    Uint8List data,
    Uint8List signatureBytes,
    Uint8List publicKeyBytes,
  ) async {
    final pubKey = SimplePublicKey(
      publicKeyBytes.toList(),
      type: KeyPairType.ed25519,
    );
    final sig = Signature(signatureBytes.toList(), publicKey: pubKey);
    return Ed25519().verify(data.toList(), signature: sig);
  }

  // --- X25519 derivation ---

  /// Derive an X25519 key pair from Ed25519 private key seed.
  ///
  /// Uses the standard conversion: hash the Ed25519 seed with SHA-512,
  /// take the first 32 bytes, clamp for X25519.
  static Future<SimpleKeyPair> _deriveX25519(SimpleKeyPair edKeyPair) async {
    final seed = await edKeyPair.extractPrivateKeyBytes();
    // Hash the Ed25519 seed to get X25519-safe private key material
    final hash = await Sha512().hash(seed);
    final x25519Seed = List<int>.from(hash.bytes.sublist(0, 32));

    // X25519 clamping
    x25519Seed[0] &= 248;
    x25519Seed[31] &= 127;
    x25519Seed[31] |= 64;

    final x25519 = X25519();
    final kp = await x25519.newKeyPairFromSeed(x25519Seed);
    return kp.extract();
  }
}
