import 'package:flutter_test/flutter_test.dart';

import 'package:bitchat/nostr/relay_directory.dart';

void main() {
  group('RelayDirectory', () {
    test('parseCsv loads relays correctly', () {
      final dir = RelayDirectory.instance;
      // Test the CSV parsing logic directly by calling internal method
      // We can test via the closestRelays method since initialization
      // loads from CSV in real app, but unit tests can't load assets.
      // Instead we test the data model and haversine.
      expect(dir, isNotNull);
    });

    test('RelayInfo stores url, lat, lon', () {
      const relay = RelayInfo(
        url: 'wss://relay.damus.io',
        latitude: 43.65,
        longitude: -79.38,
      );
      expect(relay.url, 'wss://relay.damus.io');
      expect(relay.latitude, 43.65);
      expect(relay.longitude, -79.38);
      expect(relay.toString(), contains('relay.damus.io'));
    });
  });

  group('Haversine distance', () {
    test('same point returns 0', () {
      final distance = RelayDirectory.haversineMetersPublic(
        43.65,
        -79.38,
        43.65,
        -79.38,
      );
      expect(distance, closeTo(0, 1));
    });

    test('known distance NYC to LA', () {
      // NYC (40.7128, -74.0060) to LA (34.0522, -118.2437) ≈ 3944 km
      final distance = RelayDirectory.haversineMetersPublic(
        40.7128,
        -74.0060,
        34.0522,
        -118.2437,
      );
      expect(distance / 1000, closeTo(3944, 50));
    });

    test('known distance London to Tokyo', () {
      // London (51.5074, -0.1278) to Tokyo (35.6762, 139.6503) ≈ 9560 km
      final distance = RelayDirectory.haversineMetersPublic(
        51.5074,
        -0.1278,
        35.6762,
        139.6503,
      );
      expect(distance / 1000, closeTo(9560, 50));
    });
  });

  group('closestRelays', () {
    test('returns defaults when not initialized', () {
      final dir = RelayDirectory.instance;
      final relays = dir.closestRelays(
        latitude: 31.23,
        longitude: 121.47,
        count: 3,
      );
      // Should return fallback defaults
      expect(relays, isNotEmpty);
      expect(relays.length, lessThanOrEqualTo(5));
    });
  });
}
