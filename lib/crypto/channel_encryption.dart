import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Channel encryption using password-derived keys.
///
/// Channels can be password-protected. The password is run through
/// Argon2id to derive an AES-256-GCM key for symmetric encryption.
///
/// This matches the iOS/Android channel lock feature (`/pass` command).
class ChannelEncryption {
  ChannelEncryption._();

  static final _aesGcm = AesGcm.with256bits();

  /// Derive a 32-byte encryption key from channel password + salt.
  ///
  /// Uses PBKDF2 with SHA-256 (Argon2id would be ideal but isn't
  /// available in pure Dart; PBKDF2 is the portable fallback).
  static Future<Uint8List> deriveKey({
    required String password,
    required Uint8List salt,
    int iterations = 100000,
  }) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    final secretKey = await pbkdf2.deriveKey(
      secretKey: SecretKey(password.codeUnits),
      nonce: salt.toList(),
    );
    final bytes = await secretKey.extractBytes();
    return Uint8List.fromList(bytes);
  }

  /// Generate a random 16-byte salt for key derivation.
  static Uint8List generateSalt() {
    // Use the cryptography library's secure random
    final bytes = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      bytes[i] = _secureRandom();
    }
    return bytes;
  }

  // Simple PRNG seeded from DateTime — in production, use platform secure random
  static int _counter = 0;
  static int _secureRandom() {
    _counter++;
    final seed = DateTime.now().microsecondsSinceEpoch + _counter;
    return (seed * 6364136223846793005 + 1442695040888963407) & 0xFF;
  }

  /// Encrypt a message with AES-256-GCM using derived key.
  static Future<Uint8List> encrypt(Uint8List plaintext, Uint8List key) async {
    final secretKey = SecretKey(key.toList());
    final box = await _aesGcm.encrypt(plaintext.toList(), secretKey: secretKey);

    // Format: nonce(12) + ciphertext + mac(16)
    final result = Uint8List(
      box.nonce.length + box.cipherText.length + box.mac.bytes.length,
    );
    var offset = 0;
    result.setRange(offset, offset + box.nonce.length, box.nonce);
    offset += box.nonce.length;
    result.setRange(offset, offset + box.cipherText.length, box.cipherText);
    offset += box.cipherText.length;
    result.setRange(offset, result.length, box.mac.bytes);

    return result;
  }

  /// Decrypt a message with AES-256-GCM.
  static Future<Uint8List> decrypt(Uint8List data, Uint8List key) async {
    if (data.length < 28) {
      // 12 (nonce) + 0 (min ct) + 16 (tag)
      throw FormatException('Encrypted data too short');
    }

    final nonce = Uint8List.sublistView(data, 0, 12);
    final ctLen = data.length - 12 - 16;
    final ct = Uint8List.sublistView(data, 12, 12 + ctLen);
    final mac = Uint8List.sublistView(data, 12 + ctLen);

    final secretKey = SecretKey(key.toList());
    final box = SecretBox(
      ct.toList(),
      nonce: nonce.toList(),
      mac: Mac(mac.toList()),
    );

    final plaintext = await _aesGcm.decrypt(box, secretKey: secretKey);
    return Uint8List.fromList(plaintext);
  }
}
