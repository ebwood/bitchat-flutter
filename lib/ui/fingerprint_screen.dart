import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:bitchat/services/identity_service.dart';

/// Fingerprint verification screen — side-by-side comparison of
/// your fingerprint and a peer's fingerprint.
///
/// Matches the iOS `FingerprintView.swift` design.
class FingerprintScreen extends StatelessWidget {
  const FingerprintScreen({
    super.key,
    required this.myPublicKeyHex,
    required this.peerIdentity,
    this.onVerify,
    this.onUnverify,
  });

  final String myPublicKeyHex;
  final PeerIdentity peerIdentity;
  final VoidCallback? onVerify;
  final VoidCallback? onUnverify;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final myFingerprint = IdentityService.myFingerprint(myPublicKeyHex);
    final myFormatted = _formatFingerprint(myFingerprint);
    final theirFormatted = peerIdentity.formattedFingerprint;
    final isVerified = peerIdentity.trustLevel == TrustLevel.verified;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: AppBar(
        title: Text(
          '🔐 Fingerprint',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.green : const Color(0xFF008000),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Peer info card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    isVerified ? Icons.verified_user : Icons.shield_outlined,
                    color: isVerified ? Colors.green : Colors.orange,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          peerIdentity.displayName,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          isVerified ? '✅ Verified' : '⚠️ Not verified',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: isVerified ? Colors.green : Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Their fingerprint
            _FingerprintBlock(
              label: "THEIR FINGERPRINT",
              fingerprint: theirFormatted,
              isDark: isDark,
              colorScheme: colorScheme,
            ),

            const SizedBox(height: 20),

            // My fingerprint
            _FingerprintBlock(
              label: "YOUR FINGERPRINT",
              fingerprint: myFormatted,
              isDark: isDark,
              colorScheme: colorScheme,
            ),

            const SizedBox(height: 16),

            // Verification instructions
            Text(
              'Compare the fingerprint blocks above with your contact\'s device. '
              'If they match exactly, tap "Mark as Verified" to confirm.',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),

            const Spacer(),

            // Verify / Unverify button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: Icon(
                  isVerified
                      ? Icons.remove_circle_outline
                      : Icons.verified_user,
                  size: 18,
                ),
                label: Text(
                  isVerified ? 'Remove Verification' : 'Mark as Verified',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isVerified ? Colors.red : Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () {
                  if (isVerified) {
                    onUnverify?.call();
                  } else {
                    onVerify?.call();
                  }
                  Navigator.of(context).pop();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatFingerprint(String hex) {
    final clean = hex.replaceAll(' ', '');
    final groups = <String>[];
    for (var i = 0; i < clean.length; i += 4) {
      final end = (i + 4 > clean.length) ? clean.length : i + 4;
      groups.add(clean.substring(i, end));
    }
    return groups.join(' ');
  }
}

/// A styled fingerprint display block with copy-to-clipboard.
class _FingerprintBlock extends StatelessWidget {
  const _FingerprintBlock({
    required this.label,
    required this.fingerprint,
    required this.isDark,
    required this.colorScheme,
  });

  final String label;
  final String fingerprint;
  final bool isDark;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final accentColor = isDark ? Colors.green : const Color(0xFF008000);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: accentColor.withValues(alpha: 0.7),
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: fingerprint));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Fingerprint copied'),
                duration: Duration(seconds: 1),
              ),
            );
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accentColor.withValues(alpha: 0.2)),
            ),
            child: SelectableText(
              fingerprint,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: accentColor,
                letterSpacing: 1.0,
                height: 1.6,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
