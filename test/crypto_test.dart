import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

import 'package:bitchat/crypto/identity_key_manager.dart';
import 'package:bitchat/crypto/noise_handshake.dart';
import 'package:bitchat/crypto/noise_session_manager.dart';
import 'package:bitchat/crypto/channel_encryption.dart';

void main() {
  group('IdentityKeyManager', () {
    test('generate creates valid keys', () async {
      final mgr = await IdentityKeyManager.generate();

      final pubKey = await mgr.getPublicKey();
      expect(pubKey.length, 32);

      final x25519Pub = await mgr.getX25519PublicKey();
      expect(x25519Pub.length, 32);

      final peerID = await mgr.getPeerIDBytes();
      expect(peerID.length, 8);
    });

    test('seed round-trip preserves identity', () async {
      final mgr1 = await IdentityKeyManager.generate();
      final seed = await mgr1.exportSeed();
      expect(seed.length, 32);

      final mgr2 = await IdentityKeyManager.fromSeed(seed);
      final pub1 = await mgr1.getPublicKey();
      final pub2 = await mgr2.getPublicKey();
      expect(pub2, pub1);

      final pid1 = await mgr1.getPeerIDBytes();
      final pid2 = await mgr2.getPeerIDBytes();
      expect(pid2, pid1);
    });

    test('sign and verify', () async {
      final mgr = await IdentityKeyManager.generate();
      final data = Uint8List.fromList('Hello BitChat'.codeUnits);

      final sig = await mgr.sign(data);
      expect(sig.length, 64); // Ed25519 sig is 64 bytes

      final pubKey = await mgr.getPublicKey();
      final valid = await IdentityKeyManager.verify(data, sig, pubKey);
      expect(valid, true);

      // Tampered data should fail
      data[0] ^= 0xFF;
      final invalid = await IdentityKeyManager.verify(data, sig, pubKey);
      expect(invalid, false);
    });

    test('fingerprint is consistent', () async {
      final mgr = await IdentityKeyManager.generate();
      final fp1 = await mgr.getFingerprint();
      final fp2 = await mgr.getFingerprint();
      expect(fp1, fp2);
      expect(fp1.contains(':'), true); // formatted with colons
    });

    test('different keys produce different identities', () async {
      final mgr1 = await IdentityKeyManager.generate();
      final mgr2 = await IdentityKeyManager.generate();

      final pub1 = await mgr1.getPublicKey();
      final pub2 = await mgr2.getPublicKey();
      expect(pub1, isNot(equals(pub2)));
    });
  });

  group('NoiseHandshake XX', () {
    test('full handshake and session encrypt/decrypt', () async {
      // Generate two identities
      final alice = await IdentityKeyManager.generate();
      final bob = await IdentityKeyManager.generate();

      // Alice initiates
      final aliceState = await NoiseHandshake.initiate(
        localStaticKeyPair: alice.x25519KeyPair,
      );

      // Bob prepares to respond
      final bobState = await NoiseHandshake.respond(
        localStaticKeyPair: bob.x25519KeyPair,
      );

      // Message 1: Alice → Bob (→ e)
      final msg1 = await aliceState.writeMessage();
      expect(msg1.length, greaterThanOrEqualTo(32)); // at least ephemeral key

      // Bob reads message 1
      await bobState.readMessage(msg1);
      expect(bobState.isComplete, false);

      // Message 2: Bob → Alice (← e, ee, s, es)
      final msg2 = await bobState.writeMessage();
      expect(
        msg2.length,
        greaterThan(80),
      ); // eph(32) + encStatic(48) + encPayload

      // Alice reads message 2
      await aliceState.readMessage(msg2);
      expect(aliceState.isComplete, false);

      // Message 3: Alice → Bob (→ s, se)
      final msg3 = await aliceState.writeMessage();
      expect(
        msg3.length,
        greaterThanOrEqualTo(48),
      ); // encStatic(48) + encPayload

      expect(aliceState.isComplete, true);

      // Bob reads message 3
      await bobState.readMessage(msg3);
      expect(bobState.isComplete, true);

      // Create sessions
      final aliceSession = await aliceState.toSession();
      final bobSession = await bobState.toSession();

      // Verify handshake hashes match
      expect(aliceSession.handshakeHash, bobSession.handshakeHash);

      // Test encrypted communication
      final plaintext = Uint8List.fromList('Secret message!'.codeUnits);

      // Alice → Bob
      final encrypted = await aliceSession.encrypt(plaintext);
      final decrypted = await bobSession.decrypt(encrypted);
      expect(decrypted, plaintext);

      // Bob → Alice
      final plaintext2 = Uint8List.fromList('Reply from Bob'.codeUnits);
      final encrypted2 = await bobSession.encrypt(plaintext2);
      final decrypted2 = await aliceSession.decrypt(encrypted2);
      expect(decrypted2, plaintext2);
    });

    test('multiple messages after handshake', () async {
      final alice = await IdentityKeyManager.generate();
      final bob = await IdentityKeyManager.generate();

      // Quick handshake
      final aState = await NoiseHandshake.initiate(
        localStaticKeyPair: alice.x25519KeyPair,
      );
      final bState = await NoiseHandshake.respond(
        localStaticKeyPair: bob.x25519KeyPair,
      );

      final m1 = await aState.writeMessage();
      await bState.readMessage(m1);
      final m2 = await bState.writeMessage();
      await aState.readMessage(m2);
      final m3 = await aState.writeMessage();
      await bState.readMessage(m3);

      final aSess = await aState.toSession();
      final bSess = await bState.toSession();

      // Send 10 messages back and forth
      for (var i = 0; i < 10; i++) {
        final msg = Uint8List.fromList('Message #$i'.codeUnits);
        final enc = await aSess.encrypt(msg);
        final dec = await bSess.decrypt(enc);
        expect(dec, msg);

        final reply = Uint8List.fromList('Reply #$i'.codeUnits);
        final enc2 = await bSess.encrypt(reply);
        final dec2 = await aSess.decrypt(enc2);
        expect(dec2, reply);
      }
    });
  });

  group('NoiseSessionManager', () {
    test('initiateHandshake and processHandshakeMessage', () async {
      final alice = await IdentityKeyManager.generate();
      final bob = await IdentityKeyManager.generate();

      final aliceMgr = NoiseSessionManager(identityManager: alice);
      final bobMgr = NoiseSessionManager(identityManager: bob);

      // Alice initiates
      final msg1 = await aliceMgr.initiateHandshake('bob_peer_id');
      expect(aliceMgr.hasHandshake('bob_peer_id'), true);
      expect(aliceMgr.hasSession('bob_peer_id'), false);

      // Bob processes msg1 (auto-creates responder state)
      final (msg2, done1) = await bobMgr.processHandshakeMessage(
        'alice_peer_id',
        msg1,
      );
      expect(done1, false);
      expect(msg2, isNotNull);

      // Alice processes msg2
      final (msg3, done2) = await aliceMgr.processHandshakeMessage(
        'bob_peer_id',
        msg2!,
      );
      expect(msg3, isNotNull);

      // Bob processes msg3
      final (msg4, done3) = await bobMgr.processHandshakeMessage(
        'alice_peer_id',
        msg3!,
      );
      expect(done3, true);
      expect(msg4, isNull);
      expect(bobMgr.hasSession('alice_peer_id'), true);

      // Alice should also have session after msg3 write
      expect(aliceMgr.hasSession('bob_peer_id'), true);

      // Test encrypt/decrypt through managers
      final plaintext = Uint8List.fromList('Manager test'.codeUnits);
      final enc = await aliceMgr.encryptMessage('bob_peer_id', plaintext);
      final dec = await bobMgr.decryptMessage('alice_peer_id', enc);
      expect(dec, plaintext);
    });
  });

  group('ChannelEncryption', () {
    test('derive key from password', () async {
      final salt = Uint8List.fromList(List.generate(16, (i) => i));
      final key = await ChannelEncryption.deriveKey(
        password: 'test_password',
        salt: salt,
        iterations: 1000, // reduced for test speed
      );
      expect(key.length, 32);

      // Same password + salt → same key
      final key2 = await ChannelEncryption.deriveKey(
        password: 'test_password',
        salt: salt,
        iterations: 1000,
      );
      expect(key2, key);

      // Different password → different key
      final key3 = await ChannelEncryption.deriveKey(
        password: 'different_password',
        salt: salt,
        iterations: 1000,
      );
      expect(key3, isNot(equals(key)));
    });

    test('encrypt and decrypt round-trip', () async {
      final salt = Uint8List.fromList(List.generate(16, (i) => i));
      final key = await ChannelEncryption.deriveKey(
        password: 'my_channel_pass',
        salt: salt,
        iterations: 1000,
      );

      final plaintext = Uint8List.fromList('Channel message content'.codeUnits);
      final encrypted = await ChannelEncryption.encrypt(plaintext, key);
      expect(encrypted.length, greaterThan(plaintext.length));

      final decrypted = await ChannelEncryption.decrypt(encrypted, key);
      expect(decrypted, plaintext);
    });

    test('wrong key fails decryption', () async {
      final salt = Uint8List.fromList(List.generate(16, (i) => i));
      final key1 = await ChannelEncryption.deriveKey(
        password: 'correct_pass',
        salt: salt,
        iterations: 1000,
      );
      final key2 = await ChannelEncryption.deriveKey(
        password: 'wrong_pass',
        salt: salt,
        iterations: 1000,
      );

      final plaintext = Uint8List.fromList('Secret'.codeUnits);
      final encrypted = await ChannelEncryption.encrypt(plaintext, key1);

      expect(
        () => ChannelEncryption.decrypt(encrypted, key2),
        throwsA(anything),
      );
    });
  });
}
