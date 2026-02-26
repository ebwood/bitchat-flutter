import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// Handles image picking, compression, EXIF stripping, and encoding
/// for chat transmission.
///
/// Matches iOS `ImageUtils.swift` behavior:
/// - Max dimension: 448px
/// - Target size: ~45KB JPEG
/// - EXIF metadata stripped for privacy
class ImageMessageService {
  ImageMessageService();

  final ImagePicker _picker = ImagePicker();

  /// Maximum pixel dimension (width or height).
  static const int maxDimension = 448;

  /// Target file size in bytes (~45KB).
  static const int targetBytes = 45000;

  /// Initial JPEG quality.
  static const int initialQuality = 82;

  /// Pick an image from gallery, compress, and return base64.
  Future<ImagePayload?> pickFromGallery() async {
    final xFile = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: maxDimension.toDouble(),
      maxHeight: maxDimension.toDouble(),
    );
    if (xFile == null) return null;
    return _processFile(xFile);
  }

  /// Pick an image from camera, compress, and return base64.
  Future<ImagePayload?> pickFromCamera() async {
    final xFile = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: maxDimension.toDouble(),
      maxHeight: maxDimension.toDouble(),
    );
    if (xFile == null) return null;
    return _processFile(xFile);
  }

  /// Process an XFile: decode, strip EXIF, scale, compress to target size.
  Future<ImagePayload?> _processFile(XFile xFile) async {
    try {
      final bytes = await xFile.readAsBytes();
      final processed = processImageBytes(bytes);
      if (processed == null) return null;

      return ImagePayload(
        base64Data: base64Encode(processed),
        width: _lastWidth,
        height: _lastHeight,
        sizeBytes: processed.length,
      );
    } catch (_) {
      return null;
    }
  }

  // Cache dimensions from last processing
  int _lastWidth = 0;
  int _lastHeight = 0;

  /// Process raw image bytes: decode → scale → strip EXIF → compress.
  /// Returns JPEG bytes or null on failure.
  Uint8List? processImageBytes(Uint8List rawBytes) {
    try {
      // Decode image (handles JPEG, PNG, WebP, etc.)
      final decoded = img.decodeImage(rawBytes);
      if (decoded == null) return null;

      // Scale to fit within maxDimension
      img.Image scaled;
      final maxSide = decoded.width > decoded.height
          ? decoded.width
          : decoded.height;

      if (maxSide > maxDimension) {
        if (decoded.width > decoded.height) {
          scaled = img.copyResize(decoded, width: maxDimension);
        } else {
          scaled = img.copyResize(decoded, height: maxDimension);
        }
      } else {
        scaled = decoded;
      }

      _lastWidth = scaled.width;
      _lastHeight = scaled.height;

      // Encode as JPEG, iteratively reducing quality to hit target size
      int quality = initialQuality;
      var jpegBytes = Uint8List.fromList(
        img.encodeJpg(scaled, quality: quality),
      );

      while (jpegBytes.length > targetBytes && quality > 30) {
        quality -= 10;
        jpegBytes = Uint8List.fromList(img.encodeJpg(scaled, quality: quality));
      }

      return jpegBytes;
    } catch (_) {
      return null;
    }
  }

  /// Decode a base64 image string to bytes for display.
  static Uint8List? decodeBase64Image(String base64String) {
    try {
      return base64Decode(base64String);
    } catch (_) {
      return null;
    }
  }
}

/// Payload for a processed image ready for transmission.
class ImagePayload {
  const ImagePayload({
    required this.base64Data,
    required this.width,
    required this.height,
    required this.sizeBytes,
  });

  /// Base64-encoded JPEG data.
  final String base64Data;

  /// Image dimensions after scaling.
  final int width;
  final int height;

  /// Compressed size in bytes.
  final int sizeBytes;
}
