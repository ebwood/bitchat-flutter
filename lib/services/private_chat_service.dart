import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'package:bitchat/nostr/nostr_event.dart';
import 'package:bitchat/nostr/nostr_filter.dart';
import 'package:bitchat/nostr/nostr_relay_manager.dart';

/// NIP-04 encrypted Direct Message service.
///
/// Uses ECDH shared secret + AES-256-CBC encryption.
/// Each DM is a Nostr kind-4 event, tagged with the recipient's pubkey.
class PrivateChatService {
  PrivateChatService({
    required NostrRelayManager relayManager,
    required String privateKeyHex,
    required String publicKeyHex,
    String? nickname,
  }) : _relayManager = relayManager,
       _privateKeyHex = privateKeyHex,
       _publicKeyHex = publicKeyHex,
       _nickname = nickname;

  final NostrRelayManager _relayManager;
  final String _privateKeyHex;
  final String _publicKeyHex;
  String? _nickname;

  final _messageController = StreamController<DirectMessage>.broadcast();
  Stream<DirectMessage> get messages => _messageController.stream;

  /// Active DM conversations keyed by peer pubkey.
  final _conversations = <String, List<DirectMessage>>{};
  Map<String, List<DirectMessage>> get conversations =>
      Map.unmodifiable(_conversations);

  bool _subscribed = false;

  /// Start listening for DMs addressed to us.
  void subscribe() {
    if (_subscribed) return;
    _subscribed = true;

    final filter = NostrFilter(
      kinds: [NostrKind.encryptedDM],
      tagFilters: {
        'p': [_publicKeyHex],
      },
      limit: 100,
    );

    _relayManager.subscribe(filter, _handleIncomingDM, id: 'private-dms');
  }

  /// Send an encrypted DM to the specified recipient.
  void sendMessage(String recipientPubKey, String plaintext) {
    final encrypted = Nip04Crypto.encrypt(
      plaintext,
      _privateKeyHex,
      recipientPubKey,
    );

    final event = NostrEvent(
      pubkey: _publicKeyHex,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      kind: NostrKind.encryptedDM,
      tags: [
        ['p', recipientPubKey],
      ],
      content: encrypted,
    );
    event.sign(_privateKeyHex);

    _relayManager.sendEvent(event);

    // Record in conversation
    final dm = DirectMessage(
      senderPubKey: _publicKeyHex,
      recipientPubKey: recipientPubKey,
      plaintext: plaintext,
      timestamp: DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000),
      isOwnMessage: true,
      senderNickname: _nickname ?? _shortKey(_publicKeyHex),
    );
    _addToConversation(recipientPubKey, dm);
    _messageController.add(dm);
  }

  void _handleIncomingDM(NostrEvent event) {
    // Only handle kind 4
    if (event.kind != NostrKind.encryptedDM) return;
    // Skip our own messages
    if (event.pubkey == _publicKeyHex) return;

    try {
      final plaintext = Nip04Crypto.decrypt(
        event.content,
        _privateKeyHex,
        event.pubkey,
      );

      final dm = DirectMessage(
        senderPubKey: event.pubkey,
        recipientPubKey: _publicKeyHex,
        plaintext: plaintext,
        timestamp: DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000),
        isOwnMessage: false,
        senderNickname: _shortKey(event.pubkey),
      );

      _addToConversation(event.pubkey, dm);
      _messageController.add(dm);
    } catch (e) {
      // Ignore messages we can't decrypt (not for us, or corrupt)
    }
  }

  void _addToConversation(String peerPubKey, DirectMessage dm) {
    _conversations.putIfAbsent(peerPubKey, () => []);
    _conversations[peerPubKey]!.add(dm);
  }

  /// Get conversation with a specific peer.
  List<DirectMessage> getConversation(String peerPubKey) {
    return List.unmodifiable(_conversations[peerPubKey] ?? []);
  }

  /// Set nickname for display.
  void setNickname(String nick) {
    _nickname = nick;
  }

  String _shortKey(String pubkey) {
    if (pubkey.length >= 12) {
      return '${pubkey.substring(0, 6)}..${pubkey.substring(pubkey.length - 4)}';
    }
    return pubkey;
  }

  void dispose() {
    _relayManager.unsubscribe('private-dms');
    _messageController.close();
    _subscribed = false;
  }
}

/// A single direct message (decrypted).
class DirectMessage {
  const DirectMessage({
    required this.senderPubKey,
    required this.recipientPubKey,
    required this.plaintext,
    required this.timestamp,
    required this.isOwnMessage,
    required this.senderNickname,
  });

  final String senderPubKey;
  final String recipientPubKey;
  final String plaintext;
  final DateTime timestamp;
  final bool isOwnMessage;
  final String senderNickname;
}

// =============================================================================
// NIP-04 Crypto — ECDH + AES-256-CBC
// =============================================================================

/// NIP-04 encryption/decryption using ECDH shared secret + AES-256-CBC.
class Nip04Crypto {
  Nip04Crypto._();

  static final _secureRandom = FortunaRandom();
  static bool _randomInitialized = false;

  static void _ensureRandomInit() {
    if (_randomInitialized) return;
    final seed = Uint8List(32);
    final rng = Random.secure();
    for (var i = 0; i < 32; i++) {
      seed[i] = rng.nextInt(256);
    }
    _secureRandom.seed(KeyParameter(seed));
    _randomInitialized = true;
  }

  /// Compute the ECDH shared secret (x-coordinate of privKey * remotePubKey).
  static Uint8List computeSharedSecret(
    String ourPrivateKeyHex,
    String theirPublicKeyHex,
  ) {
    final ecDomainParams = ECDomainParameters('secp256k1');

    // Parse our private key
    final privKeyBigInt = BigInt.parse(ourPrivateKeyHex, radix: 16);

    // Parse their public key (x-only → reconstruct full point using even y)
    final x = BigInt.parse(theirPublicKeyHex, radix: 16);
    // decompressPoint(0, x) gives the point with even y
    final theirPoint = ecDomainParams.curve.decompressPoint(0, x);

    // ECDH: multiply their point by our scalar
    final sharedPoint = (theirPoint * privKeyBigInt)!;

    // Use x-coordinate of shared point as shared secret
    final xBytes = _bigIntToBytes(sharedPoint.x!.toBigInteger()!, 32);
    return xBytes;
  }

  /// Encrypt plaintext for a recipient (NIP-04 format: base64(ciphertext)?iv=base64(iv)).
  static String encrypt(
    String plaintext,
    String ourPrivateKeyHex,
    String theirPublicKeyHex,
  ) {
    _ensureRandomInit();

    final sharedSecret = computeSharedSecret(
      ourPrivateKeyHex,
      theirPublicKeyHex,
    );

    // Generate random IV (16 bytes)
    final iv = _secureRandom.nextBytes(16);

    // AES-256-CBC encrypt
    final cipher = PaddedBlockCipher('AES/CBC/PKCS7');
    cipher.init(
      true,
      PaddedBlockCipherParameters(
        ParametersWithIV(KeyParameter(sharedSecret), iv),
        null,
      ),
    );

    final plaintextBytes = Uint8List.fromList(utf8.encode(plaintext));

    Uint8List ciphertext;
    if (plaintextBytes.isEmpty) {
      // PKCS7 pad: full block of 0x10 for empty input
      final padded = Uint8List(16);
      for (var i = 0; i < 16; i++) padded[i] = 16;
      final rawCipher = CBCBlockCipher(AESEngine());
      rawCipher.init(true, ParametersWithIV(KeyParameter(sharedSecret), iv));
      ciphertext = Uint8List(16);
      rawCipher.processBlock(padded, 0, ciphertext, 0);
    } else {
      ciphertext = cipher.process(plaintextBytes);
    }

    // NIP-04 format: base64(ciphertext)?iv=base64(iv)
    return '${base64Encode(ciphertext)}?iv=${base64Encode(iv)}';
  }

  /// Decrypt NIP-04 formatted ciphertext.
  static String decrypt(
    String nip04Content,
    String ourPrivateKeyHex,
    String senderPublicKeyHex,
  ) {
    final sharedSecret = computeSharedSecret(
      ourPrivateKeyHex,
      senderPublicKeyHex,
    );

    // Parse NIP-04 format
    final parts = nip04Content.split('?iv=');
    if (parts.length != 2) {
      throw FormatException('Invalid NIP-04 format: missing ?iv=');
    }

    final ciphertext = base64Decode(parts[0]);
    final iv = base64Decode(parts[1]);

    // AES-256-CBC decrypt
    final cipher = PaddedBlockCipher('AES/CBC/PKCS7');
    cipher.init(
      false,
      PaddedBlockCipherParameters(
        ParametersWithIV(KeyParameter(sharedSecret), iv),
        null,
      ),
    );

    final decrypted = cipher.process(Uint8List.fromList(ciphertext));
    return utf8.decode(decrypted);
  }

  // --- Utility functions ---

  static Uint8List _bigIntToBytes(BigInt value, int length) {
    final bytes = Uint8List(length);
    var v = value;
    for (var i = length - 1; i >= 0; i--) {
      bytes[i] = (v & BigInt.from(0xFF)).toInt();
      v >>= 8;
    }
    return bytes;
  }
}
