import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

/// "Matrix rain" encryption animation widget.
///
/// Matches Android `MatrixEncryptionAnimation.kt`:
/// - Characters cycle through random encrypted glyphs
/// - Staggered reveal — each character starts animating with 50ms delay
/// - 10% chance to reveal per cycle (100ms tick)
/// - After reveal, stays for 2s then re-encrypts (continuous loop)
/// - Spaces pass through unchanged
class MatrixAnimation extends StatefulWidget {
  const MatrixAnimation({
    super.key,
    required this.text,
    this.isAnimating = true,
    this.style,
    this.encryptedColor,
  });

  /// The original text to encrypt/reveal.
  final String text;

  /// Whether the animation is active.
  final bool isAnimating;

  /// Base text style.
  final TextStyle? style;

  /// Color for encrypted characters (defaults to green).
  final Color? encryptedColor;

  @override
  State<MatrixAnimation> createState() => _MatrixAnimationState();
}

class _MatrixAnimationState extends State<MatrixAnimation> {
  static const _encryptedChars = '!@\$%^&*()_+-=[]{}|;:,<>?';
  static const _tickInterval = Duration(milliseconds: 100);
  static const _revealProbability = 0.10;
  static const _staggerDelay = 50; // ms per character
  static const _revealHoldDuration = 2000; // ms before re-encrypting

  final _random = Random();
  late List<_CharState> _chars;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _initCharStates();
    if (widget.isAnimating) _startAnimation();
  }

  @override
  void didUpdateWidget(MatrixAnimation old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _ticker?.cancel();
      _initCharStates();
      if (widget.isAnimating) _startAnimation();
    } else if (old.isAnimating != widget.isAnimating) {
      if (widget.isAnimating) {
        _initCharStates();
        _startAnimation();
      } else {
        _ticker?.cancel();
        setState(() {
          for (final c in _chars) {
            c.phase = _Phase.revealed;
            c.display = c.target;
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _initCharStates() {
    _chars = widget.text.split('').asMap().entries.map((entry) {
      final i = entry.key;
      final ch = entry.value;
      if (ch == ' ') {
        return _CharState(
          target: ' ',
          display: ' ',
          phase: _Phase.revealed,
          staggerMs: 0,
        );
      }
      return _CharState(
        target: ch,
        display: _randomChar(),
        phase: _Phase.encrypted,
        staggerMs: i * _staggerDelay,
      );
    }).toList();
  }

  void _startAnimation() {
    _ticker?.cancel();
    final startTime = DateTime.now().millisecondsSinceEpoch;

    _ticker = Timer.periodic(_tickInterval, (_) {
      if (!mounted) return;
      final elapsed = DateTime.now().millisecondsSinceEpoch - startTime;
      var changed = false;

      for (final c in _chars) {
        if (c.phase == _Phase.revealed && c.target == ' ') continue;

        final charElapsed = elapsed - c.staggerMs;
        if (charElapsed < 0) continue; // Not yet started due to stagger

        switch (c.phase) {
          case _Phase.encrypted:
            // Cycle random characters
            c.display = _randomChar();
            changed = true;
            // Random chance to reveal
            if (_random.nextDouble() < _revealProbability) {
              c.phase = _Phase.revealed;
              c.display = c.target;
              c.revealedAt = DateTime.now().millisecondsSinceEpoch;
            }
          case _Phase.revealed:
            // After hold duration, re-encrypt
            if (c.target != ' ' &&
                c.revealedAt != null &&
                DateTime.now().millisecondsSinceEpoch - c.revealedAt! >
                    _revealHoldDuration) {
              c.phase = _Phase.encrypted;
              c.display = _randomChar();
              changed = true;
            }
        }
      }

      if (changed) setState(() {});
    });
  }

  String _randomChar() {
    return _encryptedChars[_random.nextInt(_encryptedChars.length)];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseStyle =
        widget.style ??
        TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: Theme.of(context).colorScheme.onSurface,
        );
    final encColor =
        widget.encryptedColor ??
        (isDark ? const Color(0xFF32D74B) : const Color(0xFF248A3D));

    return RichText(
      text: TextSpan(
        children: _chars.map((c) {
          final isEncrypted = c.phase == _Phase.encrypted;
          return TextSpan(
            text: c.display,
            style: baseStyle.copyWith(
              color: isEncrypted ? encColor : baseStyle.color,
              fontWeight: isEncrypted ? FontWeight.bold : baseStyle.fontWeight,
            ),
          );
        }).toList(),
      ),
    );
  }
}

enum _Phase { encrypted, revealed }

class _CharState {
  _CharState({
    required this.target,
    required this.display,
    required this.phase,
    required this.staggerMs,
    this.revealedAt,
  });

  final String target;
  String display;
  _Phase phase;
  final int staggerMs;
  int? revealedAt;
}
