/// MIME type detection utility.
///
/// Matches iOS `MimeType.swift` — detects file types from extension
/// and provides human-readable type names.
class MimeType {
  const MimeType._();

  /// Get MIME type from file name or extension.
  static String fromFileName(String fileName) {
    final ext = _extension(fileName);
    return _mimeTypes[ext] ?? 'application/octet-stream';
  }

  /// Get human-readable type label.
  static String labelForFileName(String fileName) {
    final ext = _extension(fileName);
    return _typeLabels[ext] ?? 'File';
  }

  /// Check if a file is an image.
  static bool isImage(String fileName) {
    return fromFileName(fileName).startsWith('image/');
  }

  /// Check if a file is audio.
  static bool isAudio(String fileName) {
    return fromFileName(fileName).startsWith('audio/');
  }

  /// Check if a file is video.
  static bool isVideo(String fileName) {
    return fromFileName(fileName).startsWith('video/');
  }

  /// Check if a file is a document (text, pdf, office).
  static bool isDocument(String fileName) {
    final mime = fromFileName(fileName);
    return mime.startsWith('text/') ||
        mime.startsWith('application/pdf') ||
        mime.contains('document') ||
        mime.contains('spreadsheet') ||
        mime.contains('presentation');
  }

  static String _extension(String name) {
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
  }

  static const _mimeTypes = <String, String>{
    // Images
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'svg': 'image/svg+xml',
    'bmp': 'image/bmp',
    'ico': 'image/x-icon',
    'heic': 'image/heic',
    'heif': 'image/heif',
    'tiff': 'image/tiff',
    'tif': 'image/tiff',
    // Audio
    'mp3': 'audio/mpeg',
    'wav': 'audio/wav',
    'aac': 'audio/aac',
    'm4a': 'audio/mp4',
    'ogg': 'audio/ogg',
    'flac': 'audio/flac',
    'wma': 'audio/x-ms-wma',
    // Video
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'avi': 'video/x-msvideo',
    'mkv': 'video/x-matroska',
    'webm': 'video/webm',
    'wmv': 'video/x-ms-wmv',
    'flv': 'video/x-flv',
    '3gp': 'video/3gpp',
    // Documents
    'pdf': 'application/pdf',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx':
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'txt': 'text/plain',
    'md': 'text/markdown',
    'csv': 'text/csv',
    'rtf': 'application/rtf',
    // Data
    'json': 'application/json',
    'xml': 'application/xml',
    'html': 'text/html',
    'css': 'text/css',
    'js': 'application/javascript',
    // Archives
    'zip': 'application/zip',
    'rar': 'application/x-rar-compressed',
    '7z': 'application/x-7z-compressed',
    'tar': 'application/x-tar',
    'gz': 'application/gzip',
    // Apps
    'apk': 'application/vnd.android.package-archive',
    'ipa': 'application/octet-stream',
    'dmg': 'application/x-apple-diskimage',
    'exe': 'application/x-msdownload',
  };

  static const _typeLabels = <String, String>{
    'jpg': 'JPEG Image',
    'jpeg': 'JPEG Image',
    'png': 'PNG Image',
    'gif': 'GIF Image',
    'webp': 'WebP Image',
    'svg': 'SVG Image',
    'heic': 'HEIC Image',
    'mp3': 'MP3 Audio',
    'wav': 'WAV Audio',
    'aac': 'AAC Audio',
    'm4a': 'M4A Audio',
    'flac': 'FLAC Audio',
    'mp4': 'MP4 Video',
    'mov': 'MOV Video',
    'avi': 'AVI Video',
    'mkv': 'MKV Video',
    'pdf': 'PDF Document',
    'doc': 'Word Document',
    'docx': 'Word Document',
    'xls': 'Excel Spreadsheet',
    'xlsx': 'Excel Spreadsheet',
    'ppt': 'PowerPoint',
    'pptx': 'PowerPoint',
    'txt': 'Text File',
    'md': 'Markdown',
    'csv': 'CSV Data',
    'json': 'JSON Data',
    'xml': 'XML Data',
    'zip': 'ZIP Archive',
    'rar': 'RAR Archive',
    '7z': '7-Zip Archive',
    'apk': 'Android App',
    'ipa': 'iOS App',
  };
}

/// Transfer progress manager.
///
/// Matches iOS `TransferProgressManager` — tracks file transfer progress
/// for multiple concurrent transfers.
class TransferProgressManager {
  final _transfers = <String, TransferProgress>{};
  final _listeners = <void Function()>[];

  /// Start tracking a transfer.
  TransferProgress startTransfer({
    required String transferId,
    required String fileName,
    required int totalBytes,
    bool isUpload = true,
  }) {
    final progress = TransferProgress(
      transferId: transferId,
      fileName: fileName,
      totalBytes: totalBytes,
      isUpload: isUpload,
    );
    _transfers[transferId] = progress;
    _notifyListeners();
    return progress;
  }

  /// Update transfer progress.
  void updateProgress(String transferId, int bytesTransferred) {
    final transfer = _transfers[transferId];
    if (transfer != null) {
      transfer.bytesTransferred = bytesTransferred;
      if (bytesTransferred >= transfer.totalBytes) {
        transfer.state = TransferState.completed;
      }
      _notifyListeners();
    }
  }

  /// Mark transfer as failed.
  void failTransfer(String transferId, [String? error]) {
    final transfer = _transfers[transferId];
    if (transfer != null) {
      transfer.state = TransferState.failed;
      transfer.error = error;
      _notifyListeners();
    }
  }

  /// Cancel a transfer.
  void cancelTransfer(String transferId) {
    final transfer = _transfers[transferId];
    if (transfer != null) {
      transfer.state = TransferState.cancelled;
      _notifyListeners();
    }
  }

  /// Get transfer progress.
  TransferProgress? getTransfer(String transferId) => _transfers[transferId];

  /// Get all active transfers.
  List<TransferProgress> get activeTransfers => _transfers.values
      .where((t) => t.state == TransferState.inProgress)
      .toList();

  /// Remove completed/cancelled transfers.
  void cleanup() {
    _transfers.removeWhere(
      (_, t) =>
          t.state == TransferState.completed ||
          t.state == TransferState.cancelled ||
          t.state == TransferState.failed,
    );
    _notifyListeners();
  }

  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);
  void _notifyListeners() {
    for (final l in _listeners) {
      l();
    }
  }

  int get totalTransfers => _transfers.length;
}

enum TransferState { inProgress, completed, failed, cancelled }

class TransferProgress {
  TransferProgress({
    required this.transferId,
    required this.fileName,
    required this.totalBytes,
    this.isUpload = true,
    this.bytesTransferred = 0,
    this.state = TransferState.inProgress,
    this.error,
  });

  final String transferId;
  final String fileName;
  final int totalBytes;
  final bool isUpload;
  int bytesTransferred;
  TransferState state;
  String? error;

  /// Progress as 0.0 – 1.0.
  double get progress =>
      totalBytes > 0 ? (bytesTransferred / totalBytes).clamp(0.0, 1.0) : 0.0;

  /// Formatted progress string.
  String get progressText {
    final pct = (progress * 100).toStringAsFixed(0);
    return '$pct% (${_formatSize(bytesTransferred)}/${_formatSize(totalBytes)})';
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
