import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'identity_key_manager.dart';
import 'noise_handshake.dart';

/// Manages Noise Protocol sessions between peers.
///
/// Tracks active handshakes and established sessions, keyed by
/// remote peer ID. Handles session lifecycle: create → handshake → active → rekey → close.
class NoiseSessionManager {
  NoiseSessionManager({required this.identityManager});

  final IdentityKeyManager identityManager;

  /// Active sessions keyed by remote peer ID hex string.
  final Map<String, NoiseSession> _sessions = {};

  /// In-progress handshakes keyed by remote peer ID hex string.
  final Map<String, NoiseHandshakeState> _handshakes = {};

  /// Get an active session for a peer, or null if none exists.
  NoiseSession? getSession(String peerIdHex) => _sessions[peerIdHex];

  /// Check if there's an active session with a peer.
  bool hasSession(String peerIdHex) => _sessions.containsKey(peerIdHex);

  /// Check if there's an in-progress handshake with a peer.
  bool hasHandshake(String peerIdHex) => _handshakes.containsKey(peerIdHex);

  /// Start a new handshake as initiator.
  ///
  /// Returns the first message (→ e) to send to the remote peer.
  Future<Uint8List> initiateHandshake(String remotePeerIdHex) async {
    final state = await NoiseHandshake.initiate(
      localStaticKeyPair: identityManager.x25519KeyPair,
    );
    _handshakes[remotePeerIdHex] = state;
    return state.writeMessage();
  }

  /// Process a received handshake message.
  ///
  /// Returns (responseBytes, isComplete):
  /// - If not complete, send responseBytes to remote peer
  /// - If complete, the session is established (responseBytes may be the final message)
  Future<(Uint8List?, bool)> processHandshakeMessage(
    String remotePeerIdHex,
    Uint8List message,
  ) async {
    var state = _handshakes[remotePeerIdHex];

    if (state == null) {
      // This is a new handshake from a remote peer — we are the responder
      state = await NoiseHandshake.respond(
        localStaticKeyPair: identityManager.x25519KeyPair,
      );
      _handshakes[remotePeerIdHex] = state;
    }

    // Read the incoming message
    await state.readMessage(message);

    if (state.isComplete) {
      // Handshake done — create session
      final session = await state.toSession();
      _sessions[remotePeerIdHex] = session;
      _handshakes.remove(remotePeerIdHex);
      return (null, true);
    }

    // Write our response
    final response = await state.writeMessage();

    if (state.isComplete) {
      // Handshake done after our write
      final session = await state.toSession();
      _sessions[remotePeerIdHex] = session;
      _handshakes.remove(remotePeerIdHex);
      return (response, true);
    }

    return (response, false);
  }

  /// Encrypt a message for a peer with an established session.
  Future<Uint8List> encryptMessage(
    String remotePeerIdHex,
    Uint8List plaintext,
  ) async {
    final session = _sessions[remotePeerIdHex];
    if (session == null) {
      throw StateError(
        'No active session with peer $remotePeerIdHex. Handshake required.',
      );
    }
    return session.encrypt(plaintext);
  }

  /// Decrypt a message from a peer with an established session.
  Future<Uint8List> decryptMessage(
    String remotePeerIdHex,
    Uint8List ciphertext,
  ) async {
    final session = _sessions[remotePeerIdHex];
    if (session == null) {
      throw StateError('No active session with peer $remotePeerIdHex');
    }
    return session.decrypt(ciphertext);
  }

  /// Close a session with a peer.
  void closeSession(String remotePeerIdHex) {
    _sessions.remove(remotePeerIdHex);
    _handshakes.remove(remotePeerIdHex);
  }

  /// Close all sessions.
  void closeAll() {
    _sessions.clear();
    _handshakes.clear();
  }

  /// Number of active sessions.
  int get activeSessionCount => _sessions.length;

  /// List of peer IDs with active sessions.
  List<String> get activePeerIds => _sessions.keys.toList();
}

/// Persists identity keys securely using platform keychain/keystore.
class KeyStorageService {
  KeyStorageService._();

  static const _storage = FlutterSecureStorage();
  static const _seedKey = 'bitchat_identity_seed';
  static const _nicknameKey = 'bitchat_nickname';

  /// Save identity seed to secure storage.
  static Future<void> saveSeed(Uint8List seed) async {
    final encoded = base64Encode(seed);
    await _storage.write(key: _seedKey, value: encoded);
  }

  /// Load identity seed from secure storage.
  /// Returns null if no seed has been saved.
  static Future<Uint8List?> loadSeed() async {
    final encoded = await _storage.read(key: _seedKey);
    if (encoded == null) return null;
    return Uint8List.fromList(base64Decode(encoded));
  }

  /// Delete the stored identity seed (for emergency wipe).
  static Future<void> deleteSeed() async {
    await _storage.delete(key: _seedKey);
  }

  /// Save user nickname.
  static Future<void> saveNickname(String nickname) async {
    await _storage.write(key: _nicknameKey, value: nickname);
  }

  /// Load user nickname.
  static Future<String?> loadNickname() async {
    return _storage.read(key: _nicknameKey);
  }

  /// Restore or create an IdentityKeyManager.
  ///
  /// Loads the seed from secure storage if available,
  /// otherwise generates a new identity and persists it.
  static Future<IdentityKeyManager> restoreOrCreate() async {
    final seed = await loadSeed();
    if (seed != null) {
      return IdentityKeyManager.fromSeed(seed);
    }

    final manager = await IdentityKeyManager.generate();
    final newSeed = await manager.exportSeed();
    await saveSeed(newSeed);
    return manager;
  }
}
