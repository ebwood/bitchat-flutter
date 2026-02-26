import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import 'package:bitchat/services/voice_note_service.dart';

/// Voice note playback widget with waveform visualization.
///
/// Displays a compact player with play/pause, progress bar, and duration.
/// Matches the iOS `VoiceNoteView.swift` design language.
class VoiceNoteBubble extends StatefulWidget {
  const VoiceNoteBubble({
    super.key,
    required this.base64Data,
    required this.durationSeconds,
    this.isOwn = false,
  });

  final String base64Data;
  final double durationSeconds;
  final bool isOwn;

  @override
  State<VoiceNoteBubble> createState() => _VoiceNoteBubbleState();
}

class _VoiceNoteBubbleState extends State<VoiceNoteBubble> {
  final AudioPlayer _player = AudioPlayer();

  bool _isPlaying = false;
  double _progress = 0.0;
  Duration _currentPos = Duration.zero;
  Duration _totalDuration = Duration.zero;
  String? _tempFilePath;
  bool _prepared = false;

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<PlayerState>? _stateSub;

  @override
  void initState() {
    super.initState();
    _totalDuration = Duration(
      milliseconds: (widget.durationSeconds * 1000).round(),
    );
    _prepareAudio();
  }

  Future<void> _prepareAudio() async {
    // Write base64 to temp file
    final path = await VoiceNoteService.writeToTempFile(widget.base64Data);
    if (path == null || !mounted) return;

    _tempFilePath = path;

    // Listen for player events
    _posSub = _player.onPositionChanged.listen((pos) {
      if (mounted) {
        setState(() {
          _currentPos = pos;
          if (_totalDuration.inMilliseconds > 0) {
            _progress = pos.inMilliseconds / _totalDuration.inMilliseconds;
          }
        });
      }
    });

    _durSub = _player.onDurationChanged.listen((dur) {
      if (mounted && dur.inMilliseconds > 0) {
        setState(() => _totalDuration = dur);
      }
    });

    _stateSub = _player.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
          if (state == PlayerState.completed) {
            _progress = 0;
            _currentPos = Duration.zero;
          }
        });
      }
    });

    _prepared = true;
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    // Clean up temp file
    if (_tempFilePath != null) {
      try {
        File(_tempFilePath!).deleteSync();
      } catch (_) {}
    }
    super.dispose();
  }

  void _togglePlayback() async {
    if (!_prepared || _tempFilePath == null) return;

    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play(DeviceFileSource(_tempFilePath!));
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = widget.isOwn
        ? colorScheme.primary
        : colorScheme.secondary;

    return Container(
      width: 220,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: widget.isOwn
            ? accentColor.withValues(alpha: 0.12)
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Play/Pause button
          GestureDetector(
            onTap: _togglePlayback,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                color: accentColor,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Waveform + time
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Waveform progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    height: 24,
                    child: CustomPaint(
                      painter: _WaveformPainter(
                        progress: _progress.clamp(0.0, 1.0),
                        activeColor: accentColor,
                        inactiveColor: accentColor.withValues(alpha: 0.2),
                      ),
                      size: const Size(double.infinity, 24),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                // Duration label
                Text(
                  _isPlaying
                      ? _formatDuration(_currentPos)
                      : _formatDuration(_totalDuration),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),

          // Mic icon
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(
              Icons.mic,
              size: 14,
              color: accentColor.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Simple waveform-style progress bar painter.
class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  @override
  void paint(Canvas canvas, Size size) {
    const barCount = 30;
    const barWidth = 2.5;
    const gap = 1.5;

    final totalBarWidth = barCount * barWidth + (barCount - 1) * gap;
    final startX = (size.width - totalBarWidth) / 2;

    // Generate pseudo-random waveform pattern (deterministic)
    final heights = List.generate(barCount, (i) {
      // Create a pleasing waveform shape
      final t = i / barCount;
      final base =
          0.3 +
          0.4 * _pseudoSin(t * 3.14 * 2 + 0.5) +
          0.2 * _pseudoSin(t * 3.14 * 5 + 1.2);
      return (base * size.height).clamp(3.0, size.height - 2);
    });

    final progressX = progress * size.width;

    for (var i = 0; i < barCount; i++) {
      final x = startX + i * (barWidth + gap);
      final h = heights[i];
      final y = (size.height - h) / 2;
      final isActive = x + barWidth <= progressX;

      final paint = Paint()
        ..color = isActive ? activeColor : inactiveColor
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, h),
          const Radius.circular(1.5),
        ),
        paint,
      );
    }
  }

  double _pseudoSin(double x) {
    // Simple sine approximation for deterministic waveform
    final normalized = x % (3.14159 * 2);
    final half = normalized > 3.14159 ? -1.0 : 1.0;
    final t = (normalized % 3.14159) / 3.14159;
    return half * 4 * t * (1 - t);
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      progress != oldDelegate.progress;
}
