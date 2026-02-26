import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Nostr event kinds matching the iOS/Android protocol.
class NostrKind {
  NostrKind._();

  static const int metadata = 0;
  static const int textNote = 1;
  static const int encryptedDM = 4; // NIP-04 encrypted direct message
  static const int directMessage = 14; // NIP-17 direct message
  static const int fileMessage = 15; // NIP-17 file message
  static const int seal = 13; // NIP-17 sealed event
  static const int giftWrap = 1059; // NIP-17 gift wrap
  static const int ephemeralEvent = 20000; // Geohash channels
  static const int geohashPresence = 20001; // Geohash presence heartbeat
}

/// A Nostr event following NIP-01.
///
/// Events are the fundamental message type in Nostr. Each event has:
/// - `id`: SHA-256 hash of the serialized event
/// - `pubkey`: x-only 32-byte secp256k1 public key (hex)
/// - `created_at`: unix timestamp
/// - `kind`: event type
/// - `tags`: arbitrary tag arrays
/// - `content`: event content string
/// - `sig`: BIP-340 Schnorr signature (hex)
class NostrEvent {
  NostrEvent({
    this.id = '',
    required this.pubkey,
    required this.createdAt,
    required this.kind,
    required this.tags,
    required this.content,
    this.sig,
  });

  String id;
  final String pubkey;
  final int createdAt;
  final int kind;
  final List<List<String>> tags;
  final String content;
  String? sig;

  /// Create from JSON map.
  static NostrEvent? fromJson(Map<String, dynamic> json) {
    try {
      return NostrEvent(
        id: json['id'] as String? ?? '',
        pubkey: json['pubkey'] as String,
        createdAt: json['created_at'] as int,
        kind: json['kind'] as int,
        tags: (json['tags'] as List)
            .map((t) => (t as List).map((e) => e.toString()).toList())
            .toList(),
        content: json['content'] as String,
        sig: json['sig'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  /// Create from JSON string.
  static NostrEvent? fromJsonString(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      return fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Create a text note event (kind 1).
  static NostrEvent createTextNote({
    required String content,
    required String publicKeyHex,
    required String privateKeyHex,
    List<List<String>> tags = const [],
    int? createdAt,
  }) {
    final event = NostrEvent(
      pubkey: publicKeyHex,
      createdAt: createdAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      kind: NostrKind.textNote,
      tags: tags,
      content: content,
    );
    return event.sign(privateKeyHex);
  }

  /// Create a geohash ephemeral event (kind 20000).
  static NostrEvent createGeohashEvent({
    required String content,
    required String geohash,
    required String publicKeyHex,
    required String privateKeyHex,
    String? nickname,
    int? createdAt,
  }) {
    final tags = <List<String>>[
      ['g', geohash],
      if (nickname != null) ['n', nickname],
    ];
    final event = NostrEvent(
      pubkey: publicKeyHex,
      createdAt: createdAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      kind: NostrKind.ephemeralEvent,
      tags: tags,
      content: content,
    );
    return event.sign(privateKeyHex);
  }

  /// Sign this event in place and return it.
  NostrEvent sign(String privateKeyHex) {
    final (eventId, eventIdHash) = calculateEventId();
    id = eventId;
    sig = NostrCrypto.schnorrSign(eventIdHash, privateKeyHex);
    return this;
  }

  /// Calculate event ID per NIP-01: SHA-256([0,pubkey,created_at,kind,tags,content])
  (String, Uint8List) calculateEventId() {
    final serializedArray = [0, pubkey, createdAt, kind, tags, content];
    final jsonString = jsonEncode(serializedArray);
    final jsonBytes = utf8.encode(jsonString);
    final hash = SHA256Digest().process(Uint8List.fromList(jsonBytes));
    final hexId = _bytesToHex(hash);
    return (hexId, hash);
  }

  /// Compute event ID hex without signing.
  String computeEventIdHex() {
    final (eventId, _) = calculateEventId();
    return eventId;
  }

  /// Validate event signature using BIP-340 Schnorr verification.
  bool isValidSignature() {
    try {
      if (sig == null || id.isEmpty || pubkey.isEmpty) return false;
      final (calculatedId, messageHash) = calculateEventId();
      if (calculatedId != id) return false;
      return NostrCrypto.schnorrVerify(messageHash, sig!, pubkey);
    } catch (_) {
      return false;
    }
  }

  /// Validate event structure and signature.
  bool isValid() {
    try {
      if (pubkey.isEmpty || pubkey.length != 64) return false;
      if (createdAt <= 0 || kind < 0) return false;
      return isValidSignature();
    } catch (_) {
      return false;
    }
  }

  /// Convert to JSON map.
  Map<String, dynamic> toJson() => {
    'id': id,
    'pubkey': pubkey,
    'created_at': createdAt,
    'kind': kind,
    'tags': tags,
    'content': content,
    if (sig != null) 'sig': sig,
  };

  /// Convert to JSON string.
  String toJsonString() => jsonEncode(toJson());

  /// Get tag value by name (first match).
  String? getTagValue(String tagName) {
    for (final tag in tags) {
      if (tag.isNotEmpty && tag[0] == tagName && tag.length > 1) {
        return tag[1];
      }
    }
    return null;
  }
}

// =============================================================================
// Secp256k1 / BIP-340 Schnorr Crypto
// =============================================================================

/// Nostr cryptographic utilities: secp256k1, BIP-340 Schnorr signatures.
class NostrCrypto {
  NostrCrypto._();

  static final ECDomainParameters _params = ECDomainParameters('secp256k1');
  static final _secureRandom = FortunaRandom();
  static bool _randomInitialized = false;

  static void _ensureRandomInitialized() {
    if (_randomInitialized) return;
    final seed = Uint8List(32);
    final rng = Random.secure();
    for (var i = 0; i < 32; i++) {
      seed[i] = rng.nextInt(256);
    }
    _secureRandom.seed(KeyParameter(seed));
    _randomInitialized = true;
  }

  /// Generate a secp256k1 key pair.
  /// Returns (privateKeyHex, publicKeyHex) where publicKeyHex is x-only (32 bytes).
  static (String, String) generateKeyPair() {
    _ensureRandomInitialized();

    final keyGen = ECKeyGenerator()
      ..init(
        ParametersWithRandom(ECKeyGeneratorParameters(_params), _secureRandom),
      );

    final pair = keyGen.generateKeyPair();
    final privKey = pair.privateKey as ECPrivateKey;
    final pubKey = pair.publicKey as ECPublicKey;

    final privBytes = _bigIntToBytes(privKey.d!, 32);
    final pubPoint = pubKey.Q!;
    final xBytes = _bigIntToBytes(pubPoint.x!.toBigInteger()!, 32);

    return (_bytesToHex(privBytes), _bytesToHex(xBytes));
  }

  /// Derive x-only public key from private key.
  static String derivePublicKey(String privateKeyHex) {
    final privBytes = _hexToBytes(privateKeyHex);
    final d = _bytesToBigInt(privBytes);
    final point = (_params.G * d)!;
    return _bytesToHex(_bigIntToBytes(point.x!.toBigInteger()!, 32));
  }

  /// BIP-340 Schnorr signature.
  /// Returns 64-byte hex signature (r || s).
  static String schnorrSign(Uint8List messageHash, String privateKeyHex) {
    assert(messageHash.length == 32);
    _ensureRandomInitialized();

    final privBytes = _hexToBytes(privateKeyHex);
    var d = _bytesToBigInt(privBytes);

    // P = d * G
    final pPoint = (_params.G * d)!;

    // If P has odd y, negate d
    if (!_hasEvenY(pPoint)) {
      d = _params.n - d;
    }
    final pubBytes = _bigIntToBytes(pPoint.x!.toBigInteger()!, 32);

    // Generate nonce k
    final auxRand = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      auxRand[i] = _secureRandom.nextUint8();
    }

    // k = H("BIP0340/nonce", d || msg || pubkey || aux)
    final nonceInput = BytesBuilder(copy: false);
    nonceInput.add(_bigIntToBytes(d, 32));
    nonceInput.add(messageHash);
    nonceInput.add(pubBytes);
    nonceInput.add(auxRand);

    final nonceHash = _taggedHash('BIP0340/nonce', nonceInput.toBytes());
    var k = _bytesToBigInt(nonceHash) % _params.n;
    if (k == BigInt.zero) throw StateError('Invalid nonce');

    // R = k * G
    final rPoint = (_params.G * k)!;
    if (!_hasEvenY(rPoint)) {
      k = _params.n - k;
    }
    final rBytes = _bigIntToBytes(rPoint.x!.toBigInteger()!, 32);

    // e = H("BIP0340/challenge", r || pubkey || msg)
    final challengeInput = Uint8List(96);
    challengeInput.setRange(0, 32, rBytes);
    challengeInput.setRange(32, 64, pubBytes);
    challengeInput.setRange(64, 96, messageHash);
    final eHash = _taggedHash('BIP0340/challenge', challengeInput);
    final e = _bytesToBigInt(eHash) % _params.n;

    // s = (k + e * d) mod n
    final s = (k + e * d) % _params.n;

    final sig = Uint8List(64);
    sig.setRange(0, 32, rBytes);
    sig.setRange(32, 64, _bigIntToBytes(s, 32));
    return _bytesToHex(sig);
  }

  /// BIP-340 Schnorr signature verification.
  static bool schnorrVerify(
    Uint8List messageHash,
    String signatureHex,
    String publicKeyHex,
  ) {
    try {
      if (messageHash.length != 32) return false;

      final sigBytes = _hexToBytes(signatureHex);
      if (sigBytes.length != 64) return false;

      final pubBytes = _hexToBytes(publicKeyHex);
      if (pubBytes.length != 32) return false;

      final rBytes = sigBytes.sublist(0, 32);
      final sBytes = sigBytes.sublist(32, 64);
      final s = _bytesToBigInt(sBytes);
      final rX = _bytesToBigInt(rBytes);

      if (s >= _params.n) return false;

      // Lift x to point with even y
      final pPoint = _liftX(pubBytes);
      if (pPoint == null) return false;

      // e = H("BIP0340/challenge", r || pubkey || msg)
      final challengeInput = Uint8List(96);
      challengeInput.setRange(0, 32, rBytes);
      challengeInput.setRange(32, 64, pubBytes);
      challengeInput.setRange(64, 96, messageHash);
      final eHash = _taggedHash('BIP0340/challenge', challengeInput);
      final e = _bytesToBigInt(eHash) % _params.n;

      // R = s*G - e*P
      final sG = _params.G * s;
      final eP = pPoint * e;
      final rPoint = (sG! + (-eP!))!;

      if (rPoint.isInfinity) return false;
      if (!_hasEvenY(rPoint)) return false;

      final computedRx = rPoint.x!.toBigInteger()!;
      return computedRx == rX;
    } catch (_) {
      return false;
    }
  }

  /// Randomize timestamp (±15 minutes) for privacy.
  static int randomizeTimestamp({int? base}) {
    _ensureRandomInitialized();
    final now = base ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final offset = _secureRandom.nextUint32() % 1800 - 900;
    return now + offset;
  }

  // --- Internal helpers ---

  static bool _hasEvenY(ECPoint point) {
    final y = point.y!.toBigInteger()!;
    return y.isEven;
  }

  static ECPoint? _liftX(Uint8List xBytes) {
    try {
      // Try even y (02 prefix)
      final compressed = Uint8List(33);
      compressed[0] = 0x02;
      compressed.setRange(1, 33, xBytes);
      final point = _params.curve.decodePoint(compressed);
      if (point == null) return null;
      return _hasEvenY(point) ? point : (-point)!;
    } catch (_) {
      return null;
    }
  }

  static Uint8List _taggedHash(String tag, Uint8List data) {
    final tagBytes = utf8.encode(tag);
    final tagHash = SHA256Digest().process(Uint8List.fromList(tagBytes));

    final digest = SHA256Digest();
    digest.update(tagHash, 0, tagHash.length);
    digest.update(tagHash, 0, tagHash.length);
    digest.update(data, 0, data.length);
    final out = Uint8List(32);
    digest.doFinal(out, 0);
    return out;
  }
}

// =============================================================================
// Hex / BigInt utilities
// =============================================================================

String _bytesToHex(Uint8List bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

Uint8List _hexToBytes(String hex) {
  final result = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < result.length; i++) {
    result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return result;
}

BigInt _bytesToBigInt(Uint8List bytes) {
  var result = BigInt.zero;
  for (final b in bytes) {
    result = (result << 8) | BigInt.from(b);
  }
  return result;
}

Uint8List _bigIntToBytes(BigInt value, int length) {
  final result = Uint8List(length);
  var v = value;
  for (var i = length - 1; i >= 0; i--) {
    result[i] = (v & BigInt.from(0xFF)).toInt();
    v >>= 8;
  }
  return result;
}
