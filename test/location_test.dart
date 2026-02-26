import 'package:flutter_test/flutter_test.dart';

import 'package:bitchat/services/location_channel_service.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Geohash
  // ---------------------------------------------------------------------------
  group('Geohash', () {
    test('encode known location', () {
      // San Francisco: 37.7749, -122.4194
      final hash = Geohash.encode(37.7749, -122.4194, precision: 6);
      expect(hash.length, 6);
      expect(hash, startsWith('9q8y')); // Known prefix for SF
    });

    test('decode round-trips approximately', () {
      const lat = 48.8566;
      const lng = 2.3522;
      final hash = Geohash.encode(lat, lng, precision: 8);
      final decoded = Geohash.decode(hash);
      expect(decoded.latitude, closeTo(lat, 0.01));
      expect(decoded.longitude, closeTo(lng, 0.01));
    });

    test('precision affects accuracy', () {
      const lat = 40.7128;
      const lng = -74.0060;
      final short = Geohash.encode(lat, lng, precision: 3);
      final long = Geohash.encode(lat, lng, precision: 8);
      expect(short.length, 3);
      expect(long.length, 8);
      expect(long, startsWith(short));
    });

    test('neighbors returns 8 hashes', () {
      final hash = Geohash.encode(0, 0, precision: 4);
      final nbrs = Geohash.neighbors(hash);
      expect(nbrs.length, 8);
      // All should be same precision
      for (final n in nbrs) {
        expect(n.length, hash.length);
      }
    });

    test('cellSize decreases with precision', () {
      final size3 = Geohash.cellSize(3);
      final size6 = Geohash.cellSize(6);
      expect(size6.latDeg, lessThan(size3.latDeg));
      expect(size6.lngDeg, lessThan(size3.lngDeg));
    });
  });

  // ---------------------------------------------------------------------------
  // GeohashChannel
  // ---------------------------------------------------------------------------
  group('GeohashChannel', () {
    test('displayName uses name or geohash', () {
      final named = GeohashChannel(geohash: 'abc123', name: 'Downtown');
      expect(named.displayName, 'Downtown');

      final unnamed = GeohashChannel(geohash: 'abc123');
      expect(unnamed.displayName, '#geo:abc123');
    });

    test('center returns decoded coordinates', () {
      final ch = GeohashChannel(geohash: Geohash.encode(35.0, 139.0));
      final center = ch.center;
      expect(center.latitude, closeTo(35.0, 1.0));
      expect(center.longitude, closeTo(139.0, 1.0));
    });
  });

  // ---------------------------------------------------------------------------
  // LocationChannelManager
  // ---------------------------------------------------------------------------
  group('LocationChannelManager', () {
    late LocationChannelManager mgr;

    setUp(() {
      mgr = LocationChannelManager();
    });

    // Presence
    test('announce and get participants', () {
      mgr.announcePresence('peer1', 'abc123', nickname: 'Alice');
      mgr.announcePresence('peer2', 'abc123', nickname: 'Bob');
      mgr.announcePresence('peer3', 'def456');

      final participants = mgr.getParticipants('abc123');
      expect(participants.length, 2);
      expect(mgr.allPresences.length, 3);
    });

    test('channel created on presence', () {
      mgr.announcePresence('peer1', 'abc123');
      expect(mgr.channels.length, 1);
      expect(mgr.getChannel('abc123').participants, contains('peer1'));
    });

    // Notes
    test('add and get notes', () {
      mgr.addNote(
        id: 'n1',
        geohash: 'abc123',
        content: 'Free wifi here!',
        authorPeerId: 'peer1',
      );
      mgr.addNote(
        id: 'n2',
        geohash: 'abc123',
        content: 'Good coffee',
        authorPeerId: 'peer2',
      );
      mgr.addNote(
        id: 'n3',
        geohash: 'def456',
        content: 'Nice park',
        authorPeerId: 'peer1',
      );

      expect(mgr.getNotesForGeohash('abc123').length, 2);
      expect(mgr.allNotes.length, 3);
    });

    // Bookmarks
    test('bookmark and unbookmark channels', () {
      mgr.getChannel('abc123');
      mgr.bookmarkChannel('abc123');
      expect(mgr.isBookmarked('abc123'), true);
      expect(mgr.bookmarkedChannels.length, 1);

      mgr.unbookmarkChannel('abc123');
      expect(mgr.isBookmarked('abc123'), false);
    });

    // Reset
    test('reset clears everything', () {
      mgr.announcePresence('p1', 'abc');
      mgr.addNote(id: 'n1', geohash: 'abc', content: 'hi', authorPeerId: 'p1');
      mgr.bookmarkChannel('abc');
      mgr.reset();
      expect(mgr.channels, isEmpty);
      expect(mgr.allPresences, isEmpty);
      expect(mgr.allNotes, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // GeohashPresence
  // ---------------------------------------------------------------------------
  group('GeohashPresence', () {
    test('isFresh for recent presence', () {
      final p = GeohashPresence(
        peerId: 'p1',
        geohash: 'abc',
        timestamp: DateTime.now(),
      );
      expect(p.isFresh, true);
    });

    test('not fresh for old presence', () {
      final p = GeohashPresence(
        peerId: 'p1',
        geohash: 'abc',
        timestamp: DateTime.now().subtract(const Duration(minutes: 10)),
      );
      expect(p.isFresh, false);
    });
  });
}
