/// File picker and viewer service — manages file selection and opening.
///
/// Matches Android `FilePickerButton.kt`, `FileViewerDialog.kt`.
///
/// NOTE: This is the abstraction layer. Actual platform file picking
/// requires the `file_picker` package, and opening files requires
/// `open_file` or `url_launcher`. This service provides the logic.

/// Supported file pick modes.
enum FilePickMode {
  /// Any file type.
  any,

  /// Images only (jpg, png, gif, webp, heic).
  image,

  /// Audio files only.
  audio,

  /// Video files only.
  video,

  /// Documents only (pdf, doc, xls, etc).
  document,
}

/// Result of a file pick operation.
class PickedFile {
  const PickedFile({
    required this.name,
    required this.path,
    required this.size,
    this.mimeType,
    this.bytes,
  });

  /// File name with extension.
  final String name;

  /// Absolute file path on device.
  final String path;

  /// File size in bytes.
  final int size;

  /// MIME type if available.
  final String? mimeType;

  /// File bytes if loaded into memory.
  final List<int>? bytes;

  /// File extension.
  String get extension {
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
  }

  /// Human-readable size.
  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

/// File picker service — abstraction over platform file selection.
class FilePickerService {
  /// Maximum file size for transfer (10 MB default).
  static const int maxFileSize = 10 * 1024 * 1024;

  /// Allowed extensions per pick mode.
  static List<String>? allowedExtensions(FilePickMode mode) {
    switch (mode) {
      case FilePickMode.any:
        return null;
      case FilePickMode.image:
        return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'bmp', 'svg'];
      case FilePickMode.audio:
        return ['mp3', 'wav', 'aac', 'm4a', 'ogg', 'flac'];
      case FilePickMode.video:
        return ['mp4', 'mov', 'avi', 'mkv', 'webm'];
      case FilePickMode.document:
        return [
          'pdf',
          'doc',
          'docx',
          'xls',
          'xlsx',
          'ppt',
          'pptx',
          'txt',
          'md',
          'csv',
        ];
    }
  }

  /// Validate a picked file.
  static FileValidation validate(PickedFile file) {
    if (file.size > maxFileSize) {
      return FileValidation(
        isValid: false,
        error:
            'File too large (${file.formattedSize}). Maximum is ${_formatSize(maxFileSize)}.',
      );
    }
    if (file.name.isEmpty) {
      return FileValidation(isValid: false, error: 'Invalid file name.');
    }
    return const FileValidation(isValid: true);
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }
}

/// File validation result.
class FileValidation {
  const FileValidation({required this.isValid, this.error});
  final bool isValid;
  final String? error;
}

/// File viewer service — handles opening files with system handler.
class FileViewerService {
  /// Check if a file type can be previewed in-app.
  static bool canPreviewInApp(String fileName) {
    final ext = _extension(fileName);
    // Images and text files can be previewed in-app
    return _previewableExtensions.contains(ext);
  }

  /// Get the action label for a file.
  static String actionLabel(String fileName) {
    if (canPreviewInApp(fileName)) return 'Preview';
    return 'Open With...';
  }

  static String _extension(String name) {
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
  }

  static const _previewableExtensions = {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'bmp',
    'txt',
    'md',
    'json',
    'csv',
    'xml',
    'log',
  };
}
