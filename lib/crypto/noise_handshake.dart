import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Noise Protocol XX pattern handshake state machine.
///
/// Implements the `Noise_XX_25519_ChaChaPoly_SHA256` cipher suite,
/// matching the iOS and Android implementations exactly.
///
/// XX handshake pattern (3 messages):
/// ```
///   → e                          (initiator sends ephemeral pub key)
///   ← e, ee, s, es               (responder sends ephemeral + static)
///   → s, se                      (initiator sends static, establishes session)
/// ```
///
/// After handshake: both parties have a shared pair of cipher states
/// for encrypted bidirectional communication.
class NoiseHandshake {
  NoiseHandshake._();

  static final _x25519 = X25519();
  static final _chacha = Chacha20.poly1305Aead();
  static final _sha256 = Sha256();

  /// Protocol name for Noise_XX_25519_ChaChaPoly_SHA256
  static const protocolName = 'Noise_XX_25519_ChaChaPoly_SHA256';

  /// Hash of protocol name — used as initial handshake hash `h`
  static Uint8List? _protocolHash;

  static Future<Uint8List> _getProtocolHash() async {
    if (_protocolHash != null) return _protocolHash!;
    // If protocolName > 32 bytes, hash it; otherwise pad to 32
    final nameBytes = Uint8List.fromList(protocolName.codeUnits);
    if (nameBytes.length <= 32) {
      final padded = Uint8List(32);
      padded.setRange(0, nameBytes.length, nameBytes);
      _protocolHash = padded;
    } else {
      final hash = await _sha256.hash(nameBytes);
      _protocolHash = Uint8List.fromList(hash.bytes);
    }
    return _protocolHash!;
  }

  /// Create a new handshake as initiator.
  static Future<NoiseHandshakeState> initiate({
    required SimpleKeyPair localStaticKeyPair,
  }) async {
    final ephemeral = await _x25519.newKeyPair();
    final ephSimple = await ephemeral.extract();

    final h = Uint8List.fromList(await _getProtocolHash());
    final ck = Uint8List.fromList(h); // Chaining key starts same as h

    return NoiseHandshakeState._(
      isInitiator: true,
      localStatic: localStaticKeyPair,
      localEphemeral: ephSimple,
      h: h,
      ck: ck,
      step: 0,
    );
  }

  /// Create a new handshake as responder.
  static Future<NoiseHandshakeState> respond({
    required SimpleKeyPair localStaticKeyPair,
  }) async {
    final ephemeral = await _x25519.newKeyPair();
    final ephSimple = await ephemeral.extract();

    final h = Uint8List.fromList(await _getProtocolHash());
    final ck = Uint8List.fromList(h);

    return NoiseHandshakeState._(
      isInitiator: false,
      localStatic: localStaticKeyPair,
      localEphemeral: ephSimple,
      h: h,
      ck: ck,
      step: 0,
    );
  }
}

/// Mutable handshake state for tracking multi-message exchange.
class NoiseHandshakeState {
  NoiseHandshakeState._({
    required this.isInitiator,
    required this.localStatic,
    required this.localEphemeral,
    required this.h,
    required this.ck,
    required this.step,
  });

  final bool isInitiator;
  final SimpleKeyPair localStatic;
  final SimpleKeyPair localEphemeral;
  SimplePublicKey? remoteEphemeral;
  SimplePublicKey? remoteStatic;

  Uint8List h;  // Handshake hash
  Uint8List ck; // Chaining key
  int step;

  static final _x25519 = X25519();
  static final _sha256 = Sha256();
  static final _chacha = Chacha20.poly1305Aead();

  /// Whether the handshake is complete (3 messages exchanged).
  bool get isComplete => step >= 3;

  /// Write the next handshake message.
  ///
  /// Returns the message bytes to send to the remote peer.
  Future<Uint8List> writeMessage({Uint8List? payload}) async {
    payload ??= Uint8List(0);

    if (isInitiator && step == 0) {
      // → e
      return _writeMessage1(payload);
    } else if (!isInitiator && step == 1) {
      // ← e, ee, s, es
      return _writeMessage2(payload);
    } else if (isInitiator && step == 2) {
      // → s, se
      return _writeMessage3(payload);
    }
    throw StateError('Invalid handshake step $step for '
        '${isInitiator ? "initiator" : "responder"}');
  }

  /// Read a received handshake message.
  ///
  /// Returns decrypted payload (if any).
  Future<Uint8List> readMessage(Uint8List message) async {
    if (!isInitiator && step == 0) {
      // ← e
      return _readMessage1(message);
    } else if (isInitiator && step == 1) {
      // → e, ee, s, es
      return _readMessage2(message);
    } else if (!isInitiator && step == 2) {
      // ← s, se
      return _readMessage3(message);
    }
    throw StateError('Invalid handshake step $step for '
        '${isInitiator ? "initiator" : "responder"}');
  }

  /// After handshake completes, derive the session cipher states.
  Future<NoiseSession> toSession() async {
    if (!isComplete) {
      throw StateError('Handshake not complete');
    }

    // Split chaining key into two encryption keys
    final (k1, k2) = await _hkdfSplit(ck);

    // Initiator encrypts with k1, responder encrypts with k1
    // Initiator decrypts with k2, responder decrypts with k2
    if (isInitiator) {
      return NoiseSession(
        sendKey: k1,
        receiveKey: k2,
        handshakeHash: Uint8List.fromList(h),
        remoteStaticKey: remoteStatic!,
      );
    } else {
      return NoiseSession(
        sendKey: k2,
        receiveKey: k1,
        handshakeHash: Uint8List.fromList(h),
        remoteStaticKey: remoteStatic!,
      );
    }
  }

  // -----------------------------------------------------------------------
  // Message 1: → e
  // -----------------------------------------------------------------------

  Future<Uint8List> _writeMessage1(Uint8List payload) async {
    final localEphPub = await localEphemeral.extractPublicKey();
    final ephBytes = Uint8List.fromList(localEphPub.bytes);

    // Mix ephemeral into hash
    h = await _mixHash(h, ephBytes);

    // Message = ephemeral public key (32 bytes) + payload
    final msg = BytesBuilder(copy: false);
    msg.add(ephBytes);
    if (payload.isNotEmpty) {
      msg.add(payload);
    }

    step = 1;
    return msg.toBytes();
  }

  Future<Uint8List> _readMessage1(Uint8List message) async {
    if (message.length < 32) throw FormatException('Message 1 too short');

    final remoteEphBytes = Uint8List.sublistView(message, 0, 32);
    remoteEphemeral = SimplePublicKey(
      remoteEphBytes.toList(),
      type: KeyPairType.x25519,
    );

    h = await _mixHash(h, remoteEphBytes);
    step = 1;

    return message.length > 32
        ? Uint8List.sublistView(message, 32)
        : Uint8List(0);
  }

  // -----------------------------------------------------------------------
  // Message 2: ← e, ee, s, es
  // -----------------------------------------------------------------------

  Future<Uint8List> _writeMessage2(Uint8List payload) async {
    final localEphPub = await localEphemeral.extractPublicKey();
    final ephBytes = Uint8List.fromList(localEphPub.bytes);

    // Mix our ephemeral
    h = await _mixHash(h, ephBytes);

    // DH: ee = DH(localEph, remoteEph)
    final ee = await _dh(localEphemeral, remoteEphemeral!);
    ck = await _mixKey(ck, ee);

    // Encrypt our static key
    final localStaticPub = await localStatic.extractPublicKey();
    final staticBytes = Uint8List.fromList(localStaticPub.bytes);
    final encryptedStatic = await _encryptAndHash(staticBytes);

    // DH: es = DH(localStatic, remoteEph)
    final es = await _dh(localStatic, remoteEphemeral!);
    ck = await _mixKey(ck, es);

    // Encrypt payload
    final encryptedPayload = await _encryptAndHash(payload);

    // Assemble: ephemeral(32) + encStatic(48) + encPayload
    final msg = BytesBuilder(copy: false);
    msg.add(ephBytes);
    msg.add(encryptedStatic);
    msg.add(encryptedPayload);

    step = 2;
    return msg.toBytes();
  }

  Future<Uint8List> _readMessage2(Uint8List message) async {
    if (message.length < 80) throw FormatException('Message 2 too short');
    var offset = 0;

    // Read remote ephemeral (32 bytes)
    final remoteEphBytes = Uint8List.sublistView(message, 0, 32);
    remoteEphemeral = SimplePublicKey(
      remoteEphBytes.toList(),
      type: KeyPairType.x25519,
    );
    h = await _mixHash(h, remoteEphBytes);
    offset += 32;

    // DH: ee
    final ee = await _dh(localEphemeral, remoteEphemeral!);
    ck = await _mixKey(ck, ee);

    // Decrypt remote static key (32 bytes + 16 tag = 48 bytes)
    final encryptedStatic =
        Uint8List.sublistView(message, offset, offset + 48);
    final staticBytes = await _decryptAndHash(encryptedStatic);
    remoteStatic = SimplePublicKey(
      staticBytes.toList(),
      type: KeyPairType.x25519,
    );
    offset += 48;

    // DH: es = DH(localEph, remoteStatic)
    final es = await _dh(localEphemeral, remoteStatic!);
    ck = await _mixKey(ck, es);

    // Decrypt payload
    final encryptedPayload = Uint8List.sublistView(message, offset);
    final payload = await _decryptAndHash(encryptedPayload);

    step = 2;
    return payload;
  }

  // -----------------------------------------------------------------------
  // Message 3: → s, se
  // -----------------------------------------------------------------------

  Future<Uint8List> _writeMessage3(Uint8List payload) async {
    // Encrypt our static key
    final localStaticPub = await localStatic.extractPublicKey();
    final staticBytes = Uint8List.fromList(localStaticPub.bytes);
    final encryptedStatic = await _encryptAndHash(staticBytes);

    // DH: se = DH(localStatic, remoteEph)
    final se = await _dh(localStatic, remoteEphemeral!);
    ck = await _mixKey(ck, se);

    // Encrypt payload
    final encryptedPayload = await _encryptAndHash(payload);

    final msg = BytesBuilder(copy: false);
    msg.add(encryptedStatic);
    msg.add(encryptedPayload);

    step = 3;
    return msg.toBytes();
  }

  Future<Uint8List> _readMessage3(Uint8List message) async {
    if (message.length < 48) throw FormatException('Message 3 too short');
    var offset = 0;

    // Decrypt remote static key
    final encryptedStatic =
        Uint8List.sublistView(message, offset, offset + 48);
    final staticBytes = await _decryptAndHash(encryptedStatic);
    remoteStatic = SimplePublicKey(
      staticBytes.toList(),
      type: KeyPairType.x25519,
    );
    offset += 48;

    // DH: se = DH(localEph, remoteStatic)
    final se = await _dh(localEphemeral, remoteStatic!);
    ck = await _mixKey(ck, se);

    // Decrypt payload
    final encryptedPayload = Uint8List.sublistView(message, offset);
    final payload = await _decryptAndHash(encryptedPayload);

    step = 3;
    return payload;
  }

  // -----------------------------------------------------------------------
  // Crypto primitives
  // -----------------------------------------------------------------------

  int _encryptCounter = 0;

  Future<Uint8List> _encryptAndHash(Uint8List plaintext) async {
    // Derive key from chaining key
    final (k, newCk) = await _hkdfSplit(ck);
    // Don't update ck here — this is within-message encryption

    // Use 8-byte counter as nonce (padded to 12 bytes)
    final nonce = Uint8List(12);
    final counter = _encryptCounter++;
    for (var i = 7; i >= 0; i--) {
      nonce[4 + i] = (counter >> ((7 - i) * 8)) & 0xFF;
    }

    final secretKey = SecretKey(k.toList());
    final box = await _chacha.encrypt(
      plaintext.toList(),
      secretKey: secretKey,
      nonce: nonce.toList(),
      aad: h.toList(), // handshake hash as AAD
    );

    final result = Uint8List(box.cipherText.length + box.mac.bytes.length);
    result.setRange(0, box.cipherText.length, box.cipherText);
    result.setRange(
        box.cipherText.length, result.length, box.mac.bytes);

    // Mix ciphertext into hash
    h = await _mixHash(h, result);

    return result;
  }

  int _decryptCounter = 0;

  Future<Uint8List> _decryptAndHash(Uint8List ciphertext) async {
    if (ciphertext.length < 16) throw FormatException('Ciphertext too short');

    final (k, _) = await _hkdfSplit(ck);

    final nonce = Uint8List(12);
    final counter = _decryptCounter++;
    for (var i = 7; i >= 0; i--) {
      nonce[4 + i] = (counter >> ((7 - i) * 8)) & 0xFF;
    }

    final ctLen = ciphertext.length - 16;
    final ct = Uint8List.sublistView(ciphertext, 0, ctLen);
    final tag = Uint8List.sublistView(ciphertext, ctLen);

    final secretKey = SecretKey(k.toList());
    final box = SecretBox(
      ct.toList(),
      nonce: nonce.toList(),
      mac: Mac(tag.toList()),
    );

    final plaintext = await _chacha.decrypt(
      box,
      secretKey: secretKey,
      aad: h.toList(),
    );

    // Mix ciphertext into hash AFTER decrypt
    h = await _mixHash(h, ciphertext);

    return Uint8List.fromList(plaintext);
  }

  /// X25519 Diffie-Hellman
  Future<Uint8List> _dh(
      SimpleKeyPair localKey, SimplePublicKey remoteKey) async {
    final result = await _x25519.sharedSecretKey(
      keyPair: localKey,
      remotePublicKey: remoteKey,
    );
    final bytes = await result.extractBytes();
    return Uint8List.fromList(bytes);
  }

  /// Mix data into handshake hash: h = SHA-256(h || data)
  Future<Uint8List> _mixHash(Uint8List h, Uint8List data) async {
    final combined = Uint8List(h.length + data.length);
    combined.setRange(0, h.length, h);
    combined.setRange(h.length, combined.length, data);
    final hash = await _sha256.hash(combined);
    return Uint8List.fromList(hash.bytes);
  }

  /// Mix key material: HKDF(ck, ikm) → new ck
  Future<Uint8List> _mixKey(Uint8List ck, Uint8List ikm) async {
    final (newCk, _) = await _hkdfSplit(ck, ikm: ikm);
    return newCk;
  }

  /// HKDF-SHA256 split: derive two 32-byte keys from ck + optional ikm.
  Future<(Uint8List, Uint8List)> _hkdfSplit(
    Uint8List ck, {
    Uint8List? ikm,
  }) async {
    // HMAC-SHA256(ck, ikm) → temp key
    final hmac1 = Hmac.sha256();
    final tempMac = await hmac1.calculateMac(
      ikm ?? Uint8List(0),
      secretKey: SecretKey(ck.toList()),
    );
    final tempKey = Uint8List.fromList(tempMac.bytes);

    // HMAC-SHA256(tempKey, 0x01) → output1
    final hmac2 = Hmac.sha256();
    final out1Mac = await hmac2.calculateMac(
      [0x01],
      secretKey: SecretKey(tempKey.toList()),
    );
    final out1 = Uint8List.fromList(out1Mac.bytes);

    // HMAC-SHA256(tempKey, out1 || 0x02) → output2
    final hmac3 = Hmac.sha256();
    final combined2 = Uint8List(out1.length + 1);
    combined2.setRange(0, out1.length, out1);
    combined2[out1.length] = 0x02;
    final out2Mac = await hmac3.calculateMac(
      combined2,
      secretKey: SecretKey(tempKey.toList()),
    );
    final out2 = Uint8List.fromList(out2Mac.bytes);

    return (out1, out2);
  }
}

/// An established Noise session for encrypted communication.
///
/// After a successful XX handshake, this object provides
/// encrypt/decrypt for application messages.
class NoiseSession {
  NoiseSession({
    required this.sendKey,
    required this.receiveKey,
    required this.handshakeHash,
    required this.remoteStaticKey,
  });

  final Uint8List sendKey;
  final Uint8List receiveKey;
  final Uint8List handshakeHash;
  final SimplePublicKey remoteStaticKey;

  int _sendNonce = 0;
  int _receiveNonce = 0;

  static final _chacha = Chacha20.poly1305Aead();

  /// Encrypt a message for the remote peer.
  Future<Uint8List> encrypt(Uint8List plaintext) async {
    final nonce = _makeNonce(_sendNonce++);
    final box = await _chacha.encrypt(
      plaintext.toList(),
      secretKey: SecretKey(sendKey.toList()),
      nonce: nonce.toList(),
    );

    // Prepend nonce counter (8 bytes) + ciphertext + mac
    final result = Uint8List(8 + box.cipherText.length + box.mac.bytes.length);
    for (var i = 7; i >= 0; i--) {
      result[i] = ((_sendNonce - 1) >> ((7 - i) * 8)) & 0xFF;
    }
    result.setRange(8, 8 + box.cipherText.length, box.cipherText);
    result.setRange(8 + box.cipherText.length, result.length, box.mac.bytes);

    return result;
  }

  /// Decrypt a message from the remote peer.
  Future<Uint8List> decrypt(Uint8List ciphertext) async {
    if (ciphertext.length < 24) {
      throw FormatException('Ciphertext too short');
    }

    // Read nonce counter (8 bytes)
    int nonceVal = 0;
    for (var i = 0; i < 8; i++) {
      nonceVal = (nonceVal << 8) | ciphertext[i];
    }

    final nonce = _makeNonce(nonceVal);
    final ctLen = ciphertext.length - 8 - 16; // minus nonce and tag
    final ct = Uint8List.sublistView(ciphertext, 8, 8 + ctLen);
    final mac = Uint8List.sublistView(ciphertext, 8 + ctLen);

    final box = SecretBox(
      ct.toList(),
      nonce: nonce.toList(),
      mac: Mac(mac.toList()),
    );

    final plaintext = await _chacha.decrypt(
      box,
      secretKey: SecretKey(receiveKey.toList()),
    );

    _receiveNonce = nonceVal + 1;
    return Uint8List.fromList(plaintext);
  }

  /// Whether this session needs rekeying (after 2^32 messages).
  bool get needsRekey => _sendNonce > (1 << 32) || _receiveNonce > (1 << 32);

  Uint8List _makeNonce(int counter) {
    final nonce = Uint8List(12);
    for (var i = 7; i >= 0; i--) {
      nonce[4 + i] = (counter >> ((7 - i) * 8)) & 0xFF;
    }
    return nonce;
  }
}
