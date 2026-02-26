import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/digests/sha256.dart';

/// Trust level for a known peer.
enum TrustLevel {
  /// New or unverified peer.
  unknown,

  /// Basic interaction history established.
  casual,

  /// User has explicitly trusted this peer.
  trusted,

  /// Cryptographic fingerprint verification completed.
  verified,
}

/// A known peer's identity.
class PeerIdentity {
  PeerIdentity({
    required this.publicKeyHex,
    required this.fingerprint,
    this.nickname,
    this.petname,
    this.trustLevel = TrustLevel.unknown,
    this.isFavorite = false,
    this.isBlocked = false,
    this.notes,
    DateTime? firstSeen,
    DateTime? lastSeen,
  }) : firstSeen = firstSeen ?? DateTime.now(),
       lastSeen = lastSeen ?? DateTime.now();

  /// Nostr public key (hex string).
  final String publicKeyHex;

  /// SHA-256 fingerprint of the public key (formatted as groups of 4 hex chars).
  final String fingerprint;

  /// The nickname claimed by this peer.
  String? nickname;

  /// User-assigned name (local-only, never sent over network).
  String? petname;

  /// Trust level.
  TrustLevel trustLevel;

  /// Whether this peer is favorited.
  bool isFavorite;

  /// Whether this peer is blocked.
  bool isBlocked;

  /// User's notes about this peer.
  String? notes;

  /// When this peer was first seen.
  final DateTime firstSeen;

  /// When this peer was last seen.
  DateTime lastSeen;

  /// Display name: petname → nickname → short pubkey.
  String get displayName =>
      petname ?? nickname ?? '${publicKeyHex.substring(0, 8)}…';

  /// Fingerprint formatted as groups for easy comparison.
  /// Example: "a1b2 c3d4 e5f6 7890 ..."
  String get formattedFingerprint {
    final clean = fingerprint.replaceAll(' ', '');
    final groups = <String>[];
    for (var i = 0; i < clean.length; i += 4) {
      final end = (i + 4 > clean.length) ? clean.length : i + 4;
      groups.add(clean.substring(i, end));
    }
    return groups.join(' ');
  }

  /// Short fingerprint for compact display.
  String get shortFingerprint {
    final clean = fingerprint.replaceAll(' ', '');
    if (clean.length >= 16) {
      return '${clean.substring(0, 8)}…${clean.substring(clean.length - 8)}';
    }
    return clean;
  }

  Map<String, dynamic> toJson() => {
    'publicKeyHex': publicKeyHex,
    'fingerprint': fingerprint,
    'nickname': nickname,
    'petname': petname,
    'trustLevel': trustLevel.name,
    'isFavorite': isFavorite,
    'isBlocked': isBlocked,
    'notes': notes,
    'firstSeen': firstSeen.toIso8601String(),
    'lastSeen': lastSeen.toIso8601String(),
  };

  factory PeerIdentity.fromJson(Map<String, dynamic> json) {
    return PeerIdentity(
      publicKeyHex: json['publicKeyHex'] as String,
      fingerprint: json['fingerprint'] as String,
      nickname: json['nickname'] as String?,
      petname: json['petname'] as String?,
      trustLevel: TrustLevel.values.firstWhere(
        (t) => t.name == json['trustLevel'],
        orElse: () => TrustLevel.unknown,
      ),
      isFavorite: json['isFavorite'] as bool? ?? false,
      isBlocked: json['isBlocked'] as bool? ?? false,
      notes: json['notes'] as String?,
      firstSeen: json['firstSeen'] != null
          ? DateTime.parse(json['firstSeen'] as String)
          : null,
      lastSeen: json['lastSeen'] != null
          ? DateTime.parse(json['lastSeen'] as String)
          : null,
    );
  }
}

/// Identity service — manages peer identities and trust relationships.
class IdentityService {
  IdentityService();

  /// In-memory identity cache (fingerprint → PeerIdentity).
  final Map<String, PeerIdentity> _identities = {};

  /// Get all known identities.
  List<PeerIdentity> get identities => _identities.values.toList();

  /// Get all non-blocked identities, sorted by trust level (verified first).
  List<PeerIdentity> get contacts =>
      _identities.values.where((p) => !p.isBlocked).toList()..sort((a, b) {
        final trustOrder = b.trustLevel.index.compareTo(a.trustLevel.index);
        if (trustOrder != 0) return trustOrder;
        return a.displayName.compareTo(b.displayName);
      });

  /// Get blocked identities.
  List<PeerIdentity> get blockedPeers =>
      _identities.values.where((p) => p.isBlocked).toList();

  /// Compute SHA-256 fingerprint from a hex public key.
  static String computeFingerprint(String publicKeyHex) {
    final keyBytes = _hexToBytes(publicKeyHex);
    final digest = SHA256Digest();
    final hash = digest.process(Uint8List.fromList(keyBytes));
    return hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Get or create an identity for a public key.
  PeerIdentity getOrCreate(String publicKeyHex, {String? nickname}) {
    final fingerprint = computeFingerprint(publicKeyHex);
    if (_identities.containsKey(fingerprint)) {
      final existing = _identities[fingerprint]!;
      existing.lastSeen = DateTime.now();
      if (nickname != null && nickname != existing.nickname) {
        existing.nickname = nickname;
      }
      return existing;
    }

    final identity = PeerIdentity(
      publicKeyHex: publicKeyHex,
      fingerprint: fingerprint,
      nickname: nickname,
    );
    _identities[fingerprint] = identity;
    return identity;
  }

  /// Look up identity by fingerprint.
  PeerIdentity? byFingerprint(String fingerprint) => _identities[fingerprint];

  /// Look up identity by public key.
  PeerIdentity? byPubKey(String publicKeyHex) {
    final fp = computeFingerprint(publicKeyHex);
    return _identities[fp];
  }

  /// Set trust level for a peer.
  void setTrustLevel(String fingerprint, TrustLevel level) {
    _identities[fingerprint]?.trustLevel = level;
  }

  /// Verify a peer (set to verified trust level).
  void verify(String fingerprint) {
    setTrustLevel(fingerprint, TrustLevel.verified);
  }

  /// Unverify a peer (reset to casual).
  void unverify(String fingerprint) {
    setTrustLevel(fingerprint, TrustLevel.casual);
  }

  /// Block a peer.
  void block(String fingerprint) {
    _identities[fingerprint]?.isBlocked = true;
  }

  /// Unblock a peer.
  void unblock(String fingerprint) {
    _identities[fingerprint]?.isBlocked = false;
  }

  /// Set a user-assigned petname.
  void setPetname(String fingerprint, String? petname) {
    _identities[fingerprint]?.petname = petname;
  }

  /// Toggle favorite.
  void toggleFavorite(String fingerprint) {
    final id = _identities[fingerprint];
    if (id != null) id.isFavorite = !id.isFavorite;
  }

  /// Remove an identity.
  void remove(String fingerprint) {
    _identities.remove(fingerprint);
  }

  /// Export all identities as JSON.
  String exportJson() {
    final list = _identities.values.map((p) => p.toJson()).toList();
    return jsonEncode(list);
  }

  /// Import identities from JSON.
  void importJson(String json) {
    final list = jsonDecode(json) as List<dynamic>;
    for (final item in list) {
      final identity = PeerIdentity.fromJson(item as Map<String, dynamic>);
      _identities[identity.fingerprint] = identity;
    }
  }

  /// Get the fingerprint for the local identity.
  static String myFingerprint(String myPublicKeyHex) {
    return computeFingerprint(myPublicKeyHex);
  }

  static List<int> _hexToBytes(String hex) {
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      final end = (i + 2 > hex.length) ? hex.length : i + 2;
      bytes.add(int.parse(hex.substring(i, end), radix: 16));
    }
    return bytes;
  }
}
