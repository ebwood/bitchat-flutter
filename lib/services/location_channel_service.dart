import 'dart:math';

/// Geohash encoding/decoding for location-based channels.
///
/// Matches iOS `GeohashPresenceService.swift` and Android geohash logic.
/// Uses standard geohash algorithm (base32) to map lat/lng to grid cells.
class Geohash {
  const Geohash._();

  static const _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

  /// Encode lat/lng to geohash string of given precision (1–12).
  static String encode(double latitude, double longitude, {int precision = 6}) {
    var latMin = -90.0, latMax = 90.0;
    var lngMin = -180.0, lngMax = 180.0;
    var isLng = true;
    var bit = 0;
    var charIndex = 0;
    final hash = StringBuffer();

    while (hash.length < precision) {
      if (isLng) {
        final mid = (lngMin + lngMax) / 2;
        if (longitude >= mid) {
          charIndex = charIndex * 2 + 1;
          lngMin = mid;
        } else {
          charIndex = charIndex * 2;
          lngMax = mid;
        }
      } else {
        final mid = (latMin + latMax) / 2;
        if (latitude >= mid) {
          charIndex = charIndex * 2 + 1;
          latMin = mid;
        } else {
          charIndex = charIndex * 2;
          latMax = mid;
        }
      }
      isLng = !isLng;
      bit++;

      if (bit == 5) {
        hash.write(_base32[charIndex]);
        bit = 0;
        charIndex = 0;
      }
    }

    return hash.toString();
  }

  /// Decode geohash to approximate center lat/lng.
  static ({double latitude, double longitude}) decode(String geohash) {
    var latMin = -90.0, latMax = 90.0;
    var lngMin = -180.0, lngMax = 180.0;
    var isLng = true;

    for (final char in geohash.split('')) {
      final idx = _base32.indexOf(char.toLowerCase());
      if (idx < 0) continue;

      for (var bit = 4; bit >= 0; bit--) {
        final mask = 1 << bit;
        if (isLng) {
          final mid = (lngMin + lngMax) / 2;
          if ((idx & mask) != 0) {
            lngMin = mid;
          } else {
            lngMax = mid;
          }
        } else {
          final mid = (latMin + latMax) / 2;
          if ((idx & mask) != 0) {
            latMin = mid;
          } else {
            latMax = mid;
          }
        }
        isLng = !isLng;
      }
    }

    return (latitude: (latMin + latMax) / 2, longitude: (lngMin + lngMax) / 2);
  }

  /// Get 8 neighboring geohashes.
  static List<String> neighbors(String geohash) {
    final center = decode(geohash);
    final precision = geohash.length;

    // Approximate cell size in degrees
    final latBits = (precision * 5) ~/ 2;
    final lngBits = (precision * 5 + 1) ~/ 2;
    final latDelta = 180.0 / pow(2, latBits);
    final lngDelta = 360.0 / pow(2, lngBits);

    final offsets = [
      (-1, -1),
      (-1, 0),
      (-1, 1),
      (0, -1),
      (0, 1),
      (1, -1),
      (1, 0),
      (1, 1),
    ];

    return offsets.map((o) {
      final lat = (center.latitude + o.$1 * latDelta).clamp(-90.0, 90.0);
      final lng = center.longitude + o.$2 * lngDelta;
      final wrappedLng = lng > 180 ? lng - 360 : (lng < -180 ? lng + 360 : lng);
      return encode(lat, wrappedLng, precision: precision);
    }).toList();
  }

  /// Approximate size of a geohash cell at given precision.
  static ({double latDeg, double lngDeg}) cellSize(int precision) {
    final latBits = (precision * 5) ~/ 2;
    final lngBits = (precision * 5 + 1) ~/ 2;
    return (latDeg: 180.0 / pow(2, latBits), lngDeg: 360.0 / pow(2, lngBits));
  }
}

/// A geohash-based chat channel.
class GeohashChannel {
  GeohashChannel({
    required this.geohash,
    this.name,
    this.participants = const [],
    this.isBookmarked = false,
  });

  final String geohash;
  String? name;
  List<String> participants;
  bool isBookmarked;

  /// Human-readable label.
  String get displayName => name ?? '#geo:$geohash';

  /// Center coordinates.
  ({double latitude, double longitude}) get center => Geohash.decode(geohash);
}

/// Presence announcement for a geohash area.
class GeohashPresence {
  const GeohashPresence({
    required this.peerId,
    required this.geohash,
    required this.timestamp,
    this.nickname,
  });

  final String peerId;
  final String geohash;
  final DateTime timestamp;
  final String? nickname;

  /// Check if presence is still fresh (within 5 minutes).
  bool get isFresh => DateTime.now().difference(timestamp).inMinutes < 5;
}

/// Location note pinned to a geographic location.
class LocationNote {
  const LocationNote({
    required this.id,
    required this.geohash,
    required this.content,
    required this.authorPeerId,
    required this.timestamp,
    this.authorNickname,
  });

  final String id;
  final String geohash;
  final String content;
  final String authorPeerId;
  final DateTime timestamp;
  final String? authorNickname;
}

/// Manages geohash channels, presence, participants, notes, and bookmarks.
class LocationChannelManager {
  final _channels = <String, GeohashChannel>{};
  final _presences = <String, GeohashPresence>{}; // peerId → presence
  final _notes = <String, LocationNote>{}; // noteId → note
  final _bookmarks = <String>{}; // geohash set

  /// Get or create a channel for a geohash.
  GeohashChannel getChannel(String geohash) {
    return _channels.putIfAbsent(
      geohash,
      () => GeohashChannel(geohash: geohash),
    );
  }

  /// Get all known channels.
  List<GeohashChannel> get channels => _channels.values.toList();

  /// Get bookmarked channels.
  List<GeohashChannel> get bookmarkedChannels =>
      _channels.values.where((c) => c.isBookmarked).toList();

  // --- Presence ---

  /// Broadcast presence in a geohash area.
  GeohashPresence announcePresence(
    String peerId,
    String geohash, {
    String? nickname,
  }) {
    final presence = GeohashPresence(
      peerId: peerId,
      geohash: geohash,
      timestamp: DateTime.now(),
      nickname: nickname,
    );
    _presences[peerId] = presence;

    // Add to channel participants
    final channel = getChannel(geohash);
    if (!channel.participants.contains(peerId)) {
      channel.participants = [...channel.participants, peerId];
    }

    return presence;
  }

  /// Get participants in a geohash area.
  List<GeohashPresence> getParticipants(String geohash) {
    return _presences.values
        .where((p) => p.geohash == geohash && p.isFresh)
        .toList();
  }

  /// Get all fresh presences.
  List<GeohashPresence> get allPresences =>
      _presences.values.where((p) => p.isFresh).toList();

  /// Clean up stale presences.
  void cleanupStalePresences() {
    _presences.removeWhere((_, p) => !p.isFresh);
    for (final channel in _channels.values) {
      channel.participants = channel.participants
          .where((id) => _presences.containsKey(id))
          .toList();
    }
  }

  // --- Notes ---

  /// Pin a note to a location.
  LocationNote addNote({
    required String id,
    required String geohash,
    required String content,
    required String authorPeerId,
    String? authorNickname,
  }) {
    final note = LocationNote(
      id: id,
      geohash: geohash,
      content: content,
      authorPeerId: authorPeerId,
      timestamp: DateTime.now(),
      authorNickname: authorNickname,
    );
    _notes[id] = note;
    return note;
  }

  /// Get notes for a geohash area.
  List<LocationNote> getNotesForGeohash(String geohash) {
    return _notes.values.where((n) => n.geohash == geohash).toList();
  }

  /// Get all notes.
  List<LocationNote> get allNotes => _notes.values.toList();

  // --- Bookmarks ---

  /// Bookmark a geohash channel.
  void bookmarkChannel(String geohash) {
    _bookmarks.add(geohash);
    getChannel(geohash).isBookmarked = true;
  }

  /// Remove a bookmark.
  void unbookmarkChannel(String geohash) {
    _bookmarks.remove(geohash);
    _channels[geohash]?.isBookmarked = false;
  }

  /// Check if a channel is bookmarked.
  bool isBookmarked(String geohash) => _bookmarks.contains(geohash);

  /// Clear all data.
  void reset() {
    _channels.clear();
    _presences.clear();
    _notes.clear();
    _bookmarks.clear();
  }
}
