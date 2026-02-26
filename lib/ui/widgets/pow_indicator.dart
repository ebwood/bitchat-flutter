import 'package:flutter/material.dart';

/// Proof-of-Work status indicator widget.
///
/// Matches Android `PoWStatusIndicator.kt`:
/// - Compact mode: small shield icon + difficulty
/// - Detailed mode: icon + status text + time estimate
/// - Spinning animation when mining
enum PoWIndicatorStyle { compact, detailed }

class PoWStatusIndicator extends StatefulWidget {
  const PoWStatusIndicator({
    super.key,
    required this.isEnabled,
    required this.difficulty,
    this.isMining = false,
    this.style = PoWIndicatorStyle.compact,
  });

  final bool isEnabled;
  final int difficulty;
  final bool isMining;
  final PoWIndicatorStyle style;

  @override
  State<PoWStatusIndicator> createState() => _PoWStatusIndicatorState();
}

class _PoWStatusIndicatorState extends State<PoWStatusIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    if (widget.isMining) _rotationController.repeat();
  }

  @override
  void didUpdateWidget(PoWStatusIndicator old) {
    super.didUpdateWidget(old);
    if (widget.isMining && !old.isMining) {
      _rotationController.repeat();
    } else if (!widget.isMining && old.isMining) {
      _rotationController.stop();
      _rotationController.reset();
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isEnabled) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    final miningColor = const Color(0xFFFF9500); // Orange
    final readyColor = isDark
        ? const Color(0xFF32D74B) // Green (dark)
        : const Color(0xFF248A3D); // Green (light)
    final iconColor = widget.isMining ? miningColor : readyColor;

    switch (widget.style) {
      case PoWIndicatorStyle.compact:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildIcon(iconColor, 12),
            const SizedBox(width: 4),
            Text(
              '${widget.difficulty}b',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: iconColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        );

      case PoWIndicatorStyle.detailed:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildIcon(iconColor, 14),
              const SizedBox(width: 6),
              Text(
                widget.isMining ? 'Mining…' : 'PoW: ${widget.difficulty}',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: widget.isMining
                      ? miningColor
                      : colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              if (!widget.isMining && widget.difficulty > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '~${_estimateMiningTime(widget.difficulty)}',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 9,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ],
          ),
        );
    }
  }

  Widget _buildIcon(Color color, double size) {
    if (widget.isMining) {
      return AnimatedBuilder(
        animation: _rotationController,
        builder: (_, child) {
          return Transform.rotate(
            angle: _rotationController.value * 2 * 3.14159,
            child: child,
          );
        },
        child: Icon(Icons.security, color: color, size: size),
      );
    }
    return Icon(Icons.security, color: color, size: size);
  }

  /// Estimate mining time based on difficulty bits.
  static String _estimateMiningTime(int difficulty) {
    // Each bit doubles the expected iterations (2^difficulty)
    // Rough estimate: ~1000 hashes/sec on mobile
    if (difficulty <= 8) return '<1s';
    if (difficulty <= 12) return '<5s';
    if (difficulty <= 16) return '<30s';
    if (difficulty <= 20) return '~2m';
    if (difficulty <= 24) return '~15m';
    return '>1h';
  }
}
