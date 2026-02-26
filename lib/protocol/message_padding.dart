import 'dart:typed_data';

/// PKCS#7-style message padding for traffic analysis resistance.
///
/// Pads packets to the next standard block size (256, 512, 1024, or 2048)
/// so observers cannot infer message content from packet length.
class MessagePadding {
  MessagePadding._();

  static const List<int> _blockSizes = [256, 512, 1024, 2048];

  /// Returns the optimal block size for the given data length.
  static int optimalBlockSize(int dataLength) {
    for (final size in _blockSizes) {
      if (dataLength <= size - 1) return size; // -1 for the padding length byte
    }
    return _blockSizes.last;
  }

  /// Pad [data] to [targetSize] using PKCS#7 scheme.
  ///
  /// The last byte of the padded data indicates how many padding bytes
  /// were added (1–255).
  static Uint8List pad(Uint8List data, int targetSize) {
    if (data.length >= targetSize) {
      // Already at/over target — add minimal 1-byte padding
      final result = Uint8List(data.length + 1);
      result.setRange(0, data.length, data);
      result[data.length] = 1;
      return result;
    }

    final paddingLen = targetSize - data.length;
    final result = Uint8List(targetSize);
    result.setRange(0, data.length, data);
    // Fill padding bytes with the padding length value (PKCS#7)
    for (var i = data.length; i < targetSize; i++) {
      result[i] = paddingLen;
    }
    return result;
  }

  /// Remove PKCS#7 padding.
  static Uint8List unpad(Uint8List data) {
    if (data.isEmpty) return data;

    final paddingLen = data.last;
    if (paddingLen == 0 || paddingLen > data.length) return data;

    // Verify all padding bytes match
    for (var i = data.length - paddingLen; i < data.length; i++) {
      if (data[i] != paddingLen) return data; // Invalid padding
    }

    return Uint8List.sublistView(data, 0, data.length - paddingLen);
  }
}
