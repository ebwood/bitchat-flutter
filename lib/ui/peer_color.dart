import 'dart:convert';

import 'package:flutter/material.dart';

/// Deterministic peer color assignment using DJB2 hash.
///
/// Matches the iOS/Android `colorForPeerSeed` algorithm exactly:
/// - DJB2 hash of the peer identifier
/// - Map to HSV hue (0–360°)
/// - Avoid orange (~30°) reserved for self messages
/// - Saturation/brightness tuned for dark/light themes
class PeerColor {
  PeerColor._();

  /// Self message color (orange).
  static const selfColor = Color(0xFFFF9500);

  /// Get a unique color for a peer based on their public key.
  static Color forPubKey(String pubKey, {bool isDark = true}) {
    final seed = 'nostr:${pubKey.toLowerCase()}';
    return _colorForSeed(seed, isDark: isDark);
  }

  /// Get a unique color for a peer based on their nickname (fallback).
  static Color forNickname(String nickname, {bool isDark = true}) {
    return _colorForSeed(nickname.toLowerCase(), isDark: isDark);
  }

  /// Core algorithm — DJB2 hash → HSV color, avoiding self-orange.
  static Color _colorForSeed(String seed, {bool isDark = true}) {
    // DJB2 hash algorithm (matches iOS/Android exactly)
    var hash = 5381;
    final bytes = utf8.encode(seed);
    for (final byte in bytes) {
      hash = ((hash << 5) + hash) + byte; // hash * 33 + byte
      hash &= 0x7FFFFFFFFFFFFFFF; // keep positive
    }

    var hue = (hash % 360).toDouble() / 360.0;

    // Avoid orange (~30°) reserved for self messages
    const orange = 30.0 / 360.0;
    if ((hue - orange).abs() < 0.05) {
      hue = (hue + 0.12) % 1.0;
    }

    final saturation = isDark ? 0.50 : 0.70;
    final brightness = isDark ? 0.85 : 0.35;

    return HSVColor.fromAHSV(1.0, hue * 360, saturation, brightness).toColor();
  }
}
