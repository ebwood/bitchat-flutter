import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:bitchat/nostr/nostr_event.dart';
import 'package:bitchat/services/private_chat_service.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Nip04Crypto — shared secret, encrypt, decrypt
  // ---------------------------------------------------------------------------
  group('Nip04Crypto', () {
    late String privA, pubA, privB, pubB;

    setUp(() {
      final keysA = NostrCrypto.generateKeyPair();
      privA = keysA.$1;
      pubA = keysA.$2;
      final keysB = NostrCrypto.generateKeyPair();
      privB = keysB.$1;
      pubB = keysB.$2;
    });

    test('shared secret is symmetric', () {
      final secretAB = Nip04Crypto.computeSharedSecret(privA, pubB);
      final secretBA = Nip04Crypto.computeSharedSecret(privB, pubA);
      expect(secretAB, secretBA);
      expect(secretAB.length, 32);
    });

    test('encrypt/decrypt round-trip', () {
      const message = 'Hello, this is a secret message! 🔐';
      final encrypted = Nip04Crypto.encrypt(message, privA, pubB);

      // Should contain ?iv=
      expect(encrypted.contains('?iv='), true);

      // Decrypt with B's key
      final decrypted = Nip04Crypto.decrypt(encrypted, privB, pubA);
      expect(decrypted, message);
    });

    test('decrypt with wrong key fails', () {
      const message = 'Secret';
      final encrypted = Nip04Crypto.encrypt(message, privA, pubB);

      // Generate a third key pair
      final keysC = NostrCrypto.generateKeyPair();
      expect(
        () => Nip04Crypto.decrypt(encrypted, keysC.$1, pubA),
        throwsA(isA<Object>()), // Bad padding or garbage
      );
    });

    test('each encryption produces different ciphertext (random IV)', () {
      const message = 'Same message';
      final enc1 = Nip04Crypto.encrypt(message, privA, pubB);
      final enc2 = Nip04Crypto.encrypt(message, privA, pubB);
      expect(enc1, isNot(equals(enc2))); // Different IV → different output
    });

    test('invalid format throws FormatException', () {
      expect(
        () => Nip04Crypto.decrypt('no-iv-here', privA, pubB),
        throwsA(isA<FormatException>()),
      );
    });

    test('empty message round-trips', () {
      final encrypted = Nip04Crypto.encrypt('', privA, pubB);
      final decrypted = Nip04Crypto.decrypt(encrypted, privB, pubA);
      expect(decrypted, '');
    });

    test('unicode message round-trips', () {
      const unicode = '你好世界 🌍 مرحبا 日本語';
      final encrypted = Nip04Crypto.encrypt(unicode, privA, pubB);
      final decrypted = Nip04Crypto.decrypt(encrypted, privB, pubA);
      expect(decrypted, unicode);
    });

    test('long message round-trips', () {
      final longMsg = 'A' * 10000;
      final encrypted = Nip04Crypto.encrypt(longMsg, privA, pubB);
      final decrypted = Nip04Crypto.decrypt(encrypted, privB, pubA);
      expect(decrypted, longMsg);
    });
  });

  // ---------------------------------------------------------------------------
  // DirectMessage model
  // ---------------------------------------------------------------------------
  group('DirectMessage', () {
    test('stores all fields', () {
      final dm = DirectMessage(
        senderPubKey: 'abc123',
        recipientPubKey: 'def456',
        plaintext: 'Hello!',
        timestamp: DateTime(2024, 1, 1),
        isOwnMessage: true,
        senderNickname: 'alice',
      );
      expect(dm.senderPubKey, 'abc123');
      expect(dm.recipientPubKey, 'def456');
      expect(dm.plaintext, 'Hello!');
      expect(dm.isOwnMessage, true);
      expect(dm.senderNickname, 'alice');
    });
  });

  // ---------------------------------------------------------------------------
  // NostrKind — encryptedDM
  // ---------------------------------------------------------------------------
  group('NostrKind', () {
    test('encryptedDM has kind 4', () {
      expect(NostrKind.encryptedDM, 4);
    });
  });
}
