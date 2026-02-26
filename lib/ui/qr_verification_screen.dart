import 'dart:math';

import 'package:flutter/material.dart';

/// QR code verification screen — display and compare fingerprints via QR codes.
///
/// Matches iOS `FingerprintView.swift` QR verification flow:
/// - Display own fingerprint as QR code
/// - (Future) Camera scanner to scan peer's QR code
/// - Visual comparison and verify/reject actions
class QrVerificationScreen extends StatelessWidget {
  const QrVerificationScreen({
    super.key,
    required this.myFingerprint,
    required this.myNickname,
    this.peerFingerprint,
    this.peerNickname,
    this.onVerify,
    this.onReject,
  });

  final String myFingerprint;
  final String myNickname;
  final String? peerFingerprint;
  final String? peerNickname;
  final VoidCallback? onVerify;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark
        ? const Color(0xFF32D74B)
        : const Color(0xFF248A3D);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Verify Identity',
          style: TextStyle(fontFamily: 'monospace', fontSize: 16),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Instructions
            Text(
              peerFingerprint != null
                  ? 'Compare fingerprints to verify identity'
                  : 'Share your QR code for verification',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 24),

            // My QR code
            _QrCard(
              label: 'Your Fingerprint',
              nickname: myNickname,
              fingerprint: myFingerprint,
              accentColor: accentColor,
              isDark: isDark,
              colorScheme: colorScheme,
            ),

            if (peerFingerprint != null) ...[
              const SizedBox(height: 16),

              // Peer QR code
              _QrCard(
                label: 'Peer Fingerprint',
                nickname: peerNickname ?? 'Unknown',
                fingerprint: peerFingerprint!,
                accentColor: const Color(0xFF007AFF),
                isDark: isDark,
                colorScheme: colorScheme,
              ),

              const SizedBox(height: 24),

              // Match indicator
              _FingerprintMatch(
                myFingerprint: myFingerprint,
                peerFingerprint: peerFingerprint!,
                isDark: isDark,
              ),

              const SizedBox(height: 24),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        onReject?.call();
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text(
                        'Reject',
                        style: TextStyle(fontFamily: 'monospace'),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        onVerify?.call();
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.verified, size: 16),
                      label: const Text(
                        'Verify',
                        style: TextStyle(fontFamily: 'monospace'),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: accentColor,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// QR-style fingerprint display card.
class _QrCard extends StatelessWidget {
  const _QrCard({
    required this.label,
    required this.nickname,
    required this.fingerprint,
    required this.accentColor,
    required this.isDark,
    required this.colorScheme,
  });

  final String label;
  final String nickname;
  final String fingerprint;
  final Color accentColor;
  final bool isDark;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            nickname,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: accentColor,
            ),
          ),
          const SizedBox(height: 12),

          // QR-style grid (generated from fingerprint hash)
          _QrGrid(fingerprint: fingerprint, color: accentColor),

          const SizedBox(height: 12),

          // Fingerprint in groups of 4
          Text(
            _formatFingerprint(fingerprint),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              letterSpacing: 1,
              color: colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatFingerprint(String fp) {
    final clean = fp.replaceAll(RegExp(r'[^a-fA-F0-9]'), '');
    final groups = <String>[];
    for (var i = 0; i < clean.length; i += 4) {
      groups.add(clean.substring(i, min(i + 4, clean.length)));
    }
    final lines = <String>[];
    for (var i = 0; i < groups.length; i += 4) {
      lines.add(groups.sublist(i, min(i + 4, groups.length)).join(' '));
    }
    return lines.join('\n');
  }
}

/// Simple QR-like grid generated deterministically from fingerprint.
class _QrGrid extends StatelessWidget {
  const _QrGrid({required this.fingerprint, required this.color});
  final String fingerprint;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 120,
      child: CustomPaint(
        painter: _QrPainter(fingerprint: fingerprint, color: color),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter({required this.fingerprint, required this.color});
  final String fingerprint;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const gridSize = 10;
    final cellW = size.width / gridSize;
    final cellH = size.height / gridSize;
    final paint = Paint()..color = color;

    // Generate deterministic pattern from fingerprint
    final clean = fingerprint.replaceAll(RegExp(r'[^a-fA-F0-9]'), '');
    for (var row = 0; row < gridSize; row++) {
      for (var col = 0; col < gridSize; col++) {
        final idx = (row * gridSize + col) % clean.length;
        final charCode = clean.codeUnitAt(idx);
        // Fill cell if char value is odd
        if (charCode % 2 == 1) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(
                col * cellW + 1,
                row * cellH + 1,
                cellW - 2,
                cellH - 2,
              ),
              const Radius.circular(2),
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrPainter old) =>
      old.fingerprint != fingerprint;
}

/// Fingerprint match comparison widget.
class _FingerprintMatch extends StatelessWidget {
  const _FingerprintMatch({
    required this.myFingerprint,
    required this.peerFingerprint,
    required this.isDark,
  });
  final String myFingerprint;
  final String peerFingerprint;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final match = myFingerprint.toLowerCase() == peerFingerprint.toLowerCase();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: (match ? Colors.green : Colors.orange).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: (match ? Colors.green : Colors.orange).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            match ? Icons.check_circle : Icons.warning,
            size: 16,
            color: match ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 8),
          Text(
            match ? 'Fingerprints match!' : 'Fingerprints do NOT match',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: match ? Colors.green : Colors.orange,
            ),
          ),
        ],
      ),
    );
  }
}
