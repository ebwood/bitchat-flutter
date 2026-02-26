import 'dart:math';
import 'package:flutter/services.dart';

/// Relay directory — loads relay list from CSV and selects
/// closest relays based on geohash location.
///
/// Matches Android RelayDirectory.kt behavior:
/// - Loads 305 relays from bundled CSV (with lat/lon)
/// - Selects N closest relays to a geohash center using haversine distance
/// - Auto-prefixes relay URLs with wss://
class RelayDirectory {
  RelayDirectory._();
  static final instance = RelayDirectory._();

  final List<RelayInfo> _relays = [];
  bool _initialized = false;

  bool get isInitialized => _initialized;
  int get relayCount => _relays.length;

  /// All known relay URLs.
  List<String> get allRelayUrls =>
      _relays.map((r) => r.url).toList(growable: false);

  /// Initialize by loading relays from the bundled CSV asset.
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final csvData = await rootBundle.loadString('assets/nostr_relays.csv');
      _parseCsv(csvData);
      _initialized = true;
    } catch (e) {
      // Fallback to hardcoded defaults if CSV loading fails
      _relays.addAll(_defaultRelays);
      _initialized = true;
    }
  }

  /// Return up to [count] closest relay URLs to the given geohash center.
  ///
  /// If geohash decoding fails or relays aren't loaded, returns defaults.
  List<String> closestRelays({
    required double latitude,
    required double longitude,
    int count = 5,
  }) {
    if (_relays.isEmpty) return _defaultRelays.map((r) => r.url).toList();

    final sorted = List<RelayInfo>.from(_relays)
      ..sort((a, b) {
        final distA = _haversineMeters(
          latitude,
          longitude,
          a.latitude,
          a.longitude,
        );
        final distB = _haversineMeters(
          latitude,
          longitude,
          b.latitude,
          b.longitude,
        );
        return distA.compareTo(distB);
      });

    return sorted
        .take(count.clamp(1, _relays.length))
        .map((r) => r.url)
        .toList();
  }

  /// Parse the CSV data (format: "Relay URL,Latitude,Longitude").
  void _parseCsv(String csvData) {
    _relays.clear();
    final lines = csvData.split('\n');

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim().replaceAll('\r', '');
      if (line.isEmpty) continue;

      // Skip header
      if (i == 0 && line.toLowerCase().contains('relay url')) continue;

      final parts = line.split(',');
      if (parts.length < 3) continue;

      final rawUrl = parts[0].trim();
      if (rawUrl.isEmpty) continue;

      final lat = double.tryParse(parts[1].trim());
      final lon = double.tryParse(parts[2].trim());
      if (lat == null || lon == null) continue;

      // Normalize URL — add wss:// if no scheme present
      final url = rawUrl.contains('://') ? rawUrl : 'wss://$rawUrl';

      _relays.add(RelayInfo(url: url, latitude: lat, longitude: lon));
    }
  }

  /// Haversine distance in meters between two lat/lon points.
  /// Public for testing.
  static double haversineMetersPublic(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) => _haversineMeters(lat1, lon1, lat2, lon2);

  static double _haversineMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0; // meters
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  static double _toRadians(double degrees) => degrees * pi / 180;

  /// Default relay list — fallback when CSV is unavailable.
  static final _defaultRelays = [
    RelayInfo(url: 'wss://relay.damus.io', latitude: 43.65, longitude: -79.38),
    RelayInfo(url: 'wss://nos.lol', latitude: 50.48, longitude: 12.37),
    RelayInfo(
      url: 'wss://relay.primal.net',
      latitude: 43.65,
      longitude: -79.38,
    ),
    RelayInfo(url: 'wss://offchain.pub', latitude: 43.65, longitude: -79.38),
    RelayInfo(url: 'wss://nostr21.com', latitude: 43.65, longitude: -79.38),
  ];
}

/// A relay with its geographic coordinates.
class RelayInfo {
  const RelayInfo({
    required this.url,
    required this.latitude,
    required this.longitude,
  });

  final String url;
  final double latitude;
  final double longitude;

  @override
  String toString() => 'RelayInfo($url, $latitude, $longitude)';
}
