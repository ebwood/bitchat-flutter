import 'package:flutter/material.dart';

/// Splash screen with animated transition to main app.
///
/// Shows the BitChat logo with a matrix-style fade-in effect,
/// then smoothly transitions to the next screen.
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.onComplete,
    this.duration = const Duration(milliseconds: 2000),
  });

  /// Called when splash animation completes.
  final VoidCallback onComplete;

  /// Total duration of splash screen.
  final Duration duration;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _logoFade;
  late Animation<double> _logoScale;
  late Animation<double> _textFade;
  late Animation<double> _taglineFade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);

    _logoFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.4, curve: Curves.easeOut),
      ),
    );
    _logoScale = Tween<double>(begin: 0.5, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.4, curve: Curves.elasticOut),
      ),
    );
    _textFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 0.6, curve: Curves.easeIn),
      ),
    );
    _taglineFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.5, 0.8)),
    );

    _controller.forward();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Future.delayed(const Duration(milliseconds: 300), widget.onComplete);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo icon
                FadeTransition(
                  opacity: _logoFade,
                  child: ScaleTransition(
                    scale: _logoScale,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF32D74B), Color(0xFF00C7BE)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF32D74B,
                            ).withValues(alpha: 0.3),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.forum_rounded,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // App name
                FadeTransition(
                  opacity: _textFade,
                  child: const Text(
                    'BitChat',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 2,
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // Tagline
                FadeTransition(
                  opacity: _taglineFade,
                  child: Text(
                    'Decentralized. Encrypted. Unstoppable.',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.5),
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
