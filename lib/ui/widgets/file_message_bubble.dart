import 'package:flutter/material.dart';

/// File message bubble — displays file name, size, type icon in chat.
///
/// Matches Android `FileMessageItem.kt` behavior:
/// - File type icon based on extension
/// - File name + formatted size
/// - Progress indicator during transfer
/// - Tap to open/download
class FileMessageBubble extends StatelessWidget {
  const FileMessageBubble({
    super.key,
    required this.fileName,
    required this.fileSize,
    this.progress,
    this.onTap,
    this.isOutgoing = false,
  });

  /// File name with extension.
  final String fileName;

  /// File size in bytes.
  final int fileSize;

  /// Transfer progress 0.0–1.0, null if complete.
  final double? progress;

  /// Called when file bubble is tapped.
  final VoidCallback? onTap;

  /// Whether this file was sent by the current user.
  final bool isOutgoing;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final ext = _extension(fileName);
    final iconData = _iconForExtension(ext);
    final iconColor = _colorForExtension(ext);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // File type icon with progress overlay
            SizedBox(
              width: 40,
              height: 40,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (progress != null)
                    CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 2,
                      color: iconColor,
                    ),
                  Icon(iconData, color: iconColor, size: 24),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // File name + size
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatSize(fileSize),
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            // Download/open indicator
            if (progress == null)
              Icon(
                isOutgoing ? Icons.check_circle_outline : Icons.download,
                size: 16,
                color: colorScheme.onSurface.withValues(alpha: 0.3),
              ),
          ],
        ),
      ),
    );
  }

  static String _extension(String name) {
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
  }

  static IconData _iconForExtension(String ext) {
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return Icons.folder_zip;
      case 'mp3':
      case 'wav':
      case 'aac':
      case 'm4a':
      case 'flac':
        return Icons.audiotrack;
      case 'mp4':
      case 'mov':
      case 'avi':
      case 'mkv':
        return Icons.videocam;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'svg':
        return Icons.image;
      case 'txt':
      case 'md':
      case 'log':
        return Icons.text_snippet;
      case 'json':
      case 'xml':
      case 'csv':
        return Icons.data_object;
      case 'apk':
      case 'ipa':
        return Icons.android;
      default:
        return Icons.insert_drive_file;
    }
  }

  static Color _colorForExtension(String ext) {
    switch (ext) {
      case 'pdf':
        return const Color(0xFFE53935);
      case 'doc':
      case 'docx':
        return const Color(0xFF1565C0);
      case 'xls':
      case 'xlsx':
        return const Color(0xFF2E7D32);
      case 'ppt':
      case 'pptx':
        return const Color(0xFFFF6F00);
      case 'zip':
      case 'rar':
      case '7z':
        return const Color(0xFF6D4C41);
      case 'mp3':
      case 'wav':
      case 'aac':
      case 'm4a':
        return const Color(0xFF7B1FA2);
      case 'mp4':
      case 'mov':
      case 'avi':
        return const Color(0xFFD32F2F);
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return const Color(0xFF00796B);
      default:
        return const Color(0xFF757575);
    }
  }

  /// Format file size to human-readable string.
  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

/// Unified media picker bottom sheet — image, file, voice.
///
/// Matches Android `MediaPickerOptions.kt`.
class MediaPickerSheet extends StatelessWidget {
  const MediaPickerSheet({
    super.key,
    this.onImagePick,
    this.onFilePick,
    this.onVoiceRecord,
  });

  final VoidCallback? onImagePick;
  final VoidCallback? onFilePick;
  final VoidCallback? onVoiceRecord;

  /// Show the bottom sheet.
  static Future<void> show(
    BuildContext context, {
    VoidCallback? onImagePick,
    VoidCallback? onFilePick,
    VoidCallback? onVoiceRecord,
  }) {
    return showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => MediaPickerSheet(
        onImagePick: onImagePick,
        onFilePick: onFilePick,
        onVoiceRecord: onVoiceRecord,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: colorScheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              'Share',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _PickerOption(
                  icon: Icons.image,
                  label: 'Photo',
                  color: const Color(0xFF00796B),
                  onTap: () {
                    Navigator.pop(context);
                    onImagePick?.call();
                  },
                ),
                _PickerOption(
                  icon: Icons.insert_drive_file,
                  label: 'File',
                  color: const Color(0xFF1565C0),
                  onTap: () {
                    Navigator.pop(context);
                    onFilePick?.call();
                  },
                ),
                _PickerOption(
                  icon: Icons.mic,
                  label: 'Voice',
                  color: const Color(0xFFE53935),
                  onTap: () {
                    Navigator.pop(context);
                    onVoiceRecord?.call();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _PickerOption extends StatelessWidget {
  const _PickerOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.15 : 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}
