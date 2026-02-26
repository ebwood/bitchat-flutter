import 'dart:io';
import 'dart:typed_data';

/// Message compression using zlib (dart:io built-in).
///
/// Compresses message payloads before BLE transmission to reduce
/// fragment count and bandwidth usage. Falls back to raw data if
/// compressed output is larger than input.
class MessageCompressor {
  MessageCompressor({this.level = 6});

  /// Compression level: 1 (fastest) to 9 (best), default 6.
  final int level;

  /// Compression header byte to identify compressed data.
  static const int _compressedMarker = 0xCC;
  static const int _uncompressedMarker = 0x00;

  /// Compress data. Returns compressed bytes with a 1-byte header.
  /// If compression doesn't reduce size, returns original with uncompressed marker.
  Uint8List compress(Uint8List data) {
    if (data.isEmpty) return data;

    try {
      final compressed = ZLibCodec(level: level).encode(data);

      // Only use compression if it actually saves space
      if (compressed.length < data.length) {
        final result = Uint8List(1 + compressed.length);
        result[0] = _compressedMarker;
        result.setRange(1, result.length, compressed);
        return result;
      }
    } catch (_) {
      // Compression failed, return uncompressed
    }

    // Return with uncompressed marker
    final result = Uint8List(1 + data.length);
    result[0] = _uncompressedMarker;
    result.setRange(1, result.length, data);
    return result;
  }

  /// Decompress data. Reads the 1-byte header to determine format.
  Uint8List decompress(Uint8List data) {
    if (data.isEmpty) return data;

    final marker = data[0];
    final payload = data.sublist(1);

    if (marker == _compressedMarker) {
      try {
        final decompressed = ZLibCodec().decode(payload);
        return Uint8List.fromList(decompressed);
      } catch (_) {
        // Decompression failed, return raw payload
        return payload;
      }
    }

    // Uncompressed — return payload as-is
    return payload;
  }

  /// Calculate the compression ratio for given data.
  double compressionRatio(Uint8List data) {
    if (data.isEmpty) return 1.0;
    final compressed = compress(data);
    return compressed.length / (data.length + 1); // +1 for marker
  }
}
