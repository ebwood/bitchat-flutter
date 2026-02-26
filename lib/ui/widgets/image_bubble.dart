import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';

/// Chat bubble widget for displaying image messages.
///
/// Features (matching iOS BlockRevealImageView):
/// - Rounded image display with loading indicator
/// - Blur/privacy mode — tap to toggle reveal
/// - Full-screen viewer on long-press
class ImageBubble extends StatefulWidget {
  const ImageBubble({
    super.key,
    required this.base64Data,
    this.width,
    this.height,
    this.isOwnMessage = false,
  });

  final String base64Data;
  final int? width;
  final int? height;
  final bool isOwnMessage;

  @override
  State<ImageBubble> createState() => _ImageBubbleState();
}

class _ImageBubbleState extends State<ImageBubble>
    with SingleTickerProviderStateMixin {
  bool _revealed = false;
  late AnimationController _animController;
  late Animation<double> _blurAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _blurAnimation = Tween<double>(begin: 20.0, end: 0.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );

    // Own messages are auto-revealed
    if (widget.isOwnMessage) {
      _revealed = true;
      _animController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _toggleReveal() {
    setState(() {
      _revealed = !_revealed;
      if (_revealed) {
        _animController.forward();
      } else {
        _animController.reverse();
      }
    });
  }

  void _openFullScreen(BuildContext context, MemoryImage imageProvider) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullScreenImageView(imageProvider: imageProvider),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final imageBytes = base64Decode(widget.base64Data);
    final imageProvider = MemoryImage(imageBytes);

    // Calculate aspect ratio
    final double aspectRatio;
    if (widget.width != null && widget.height != null && widget.height! > 0) {
      aspectRatio = widget.width! / widget.height!;
    } else {
      aspectRatio = 4 / 3; // default
    }

    final maxWidth = MediaQuery.of(context).size.width * 0.65;

    return GestureDetector(
      onTap: _toggleReveal,
      onLongPress: () => _openFullScreen(context, imageProvider),
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: 300),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              // Image
              AspectRatio(
                aspectRatio: aspectRatio.clamp(0.5, 2.0),
                child: Image(
                  image: imageProvider,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.grey.shade800,
                    child: const Center(
                      child: Icon(Icons.broken_image, color: Colors.white54),
                    ),
                  ),
                ),
              ),

              // Blur overlay (animated)
              if (!widget.isOwnMessage)
                AnimatedBuilder(
                  animation: _blurAnimation,
                  builder: (context, child) {
                    if (_blurAnimation.value < 0.5) {
                      return const SizedBox.shrink();
                    }
                    return Positioned.fill(
                      child: ClipRRect(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(
                            sigmaX: _blurAnimation.value,
                            sigmaY: _blurAnimation.value,
                          ),
                          child: Container(
                            color: Colors.black.withValues(
                              alpha: _blurAnimation.value / 40,
                            ),
                            child: Center(
                              child: AnimatedOpacity(
                                opacity: _blurAnimation.value > 10 ? 1.0 : 0.0,
                                duration: const Duration(milliseconds: 200),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Text(
                                    'Tap to reveal',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen image viewer with close gesture.
class _FullScreenImageView extends StatelessWidget {
  const _FullScreenImageView({required this.imageProvider});

  final ImageProvider imageProvider;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Center(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Image(image: imageProvider, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}
