import 'dart:math';

/// Geohash encoding/decoding utilities.
///
/// Matches the geohash implementation used in the original
/// bitchat iOS/Android apps for channel routing.
class Geohash {
  Geohash._();

  static const _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

  /// Encode latitude/longitude to a geohash string.
  ///
  /// [precision] controls the length of the geohash (default 5).
  /// Precision 5 ≈ ±2.4km accuracy, matching original bitchat.
  static String encode(double latitude, double longitude, {int precision = 5}) {
    double minLat = -90, maxLat = 90;
    double minLon = -180, maxLon = 180;
    var isEven = true;
    var bit = 0;
    var ch = 0;
    final result = StringBuffer();

    while (result.length < precision) {
      if (isEven) {
        // longitude
        final mid = (minLon + maxLon) / 2;
        if (longitude >= mid) {
          ch |= (1 << (4 - bit));
          minLon = mid;
        } else {
          maxLon = mid;
        }
      } else {
        // latitude
        final mid = (minLat + maxLat) / 2;
        if (latitude >= mid) {
          ch |= (1 << (4 - bit));
          minLat = mid;
        } else {
          maxLat = mid;
        }
      }

      isEven = !isEven;
      bit++;

      if (bit == 5) {
        result.write(_base32[ch]);
        bit = 0;
        ch = 0;
      }
    }

    return result.toString();
  }

  /// Decode a geohash string to a (latitude, longitude) center point.
  static (double, double) decodeToCenter(String geohash) {
    double minLat = -90, maxLat = 90;
    double minLon = -180, maxLon = 180;
    var isEven = true;

    for (var i = 0; i < geohash.length; i++) {
      final ch = _base32.indexOf(geohash[i].toLowerCase());
      if (ch < 0) continue;

      for (var bit = 4; bit >= 0; bit--) {
        if (isEven) {
          final mid = (minLon + maxLon) / 2;
          if ((ch >> bit) & 1 == 1) {
            minLon = mid;
          } else {
            maxLon = mid;
          }
        } else {
          final mid = (minLat + maxLat) / 2;
          if ((ch >> bit) & 1 == 1) {
            minLat = mid;
          } else {
            maxLat = mid;
          }
        }
        isEven = !isEven;
      }
    }

    return ((minLat + maxLat) / 2, (minLon + maxLon) / 2);
  }

  /// Get neighboring geohash cells (8 surrounding cells).
  static List<String> neighbors(String geohash) {
    final (lat, lon) = decodeToCenter(geohash);
    final precision = geohash.length;

    // Approximate cell size for the given precision
    final latErr = 90.0 / pow(2, (precision * 5 / 2).floor());
    final lonErr = 180.0 / pow(2, (precision * 5 / 2).ceil());

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
      return encode(
        lat + o.$1 * latErr * 2,
        lon + o.$2 * lonErr * 2,
        precision: precision,
      );
    }).toList();
  }
}
