/// Accessibility helpers — semantic labels and announcements.
///
/// Provides consistent semantic labels for screen readers
/// and accessibility tools across the app.

import 'package:flutter/material.dart';

/// Wraps a widget with semantic labels for screen reader support.
class Semantic extends StatelessWidget {
  const Semantic({
    super.key,
    required this.label,
    required this.child,
    this.isButton = false,
    this.isHeader = false,
    this.isTextField = false,
    this.isImage = false,
    this.isLink = false,
    this.hint,
    this.value,
    this.onTapHint,
    this.excludeSemantics = false,
  });

  final String label;
  final Widget child;
  final bool isButton;
  final bool isHeader;
  final bool isTextField;
  final bool isImage;
  final bool isLink;
  final String? hint;
  final String? value;
  final String? onTapHint;
  final bool excludeSemantics;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: isButton,
      header: isHeader,
      textField: isTextField,
      image: isImage,
      link: isLink,
      hint: hint,
      value: value,
      onTapHint: onTapHint,
      excludeSemantics: excludeSemantics,
      child: child,
    );
  }
}

/// Standard semantic labels for common UI elements.
class SemanticLabels {
  const SemanticLabels._();

  // Navigation
  static const String settingsButton = 'Settings';
  static const String backButton = 'Go back';
  static const String menuButton = 'Open menu';
  static const String closeButton = 'Close';

  // Chat
  static const String sendButton = 'Send message';
  static const String messageInput = 'Type a message';
  static const String attachButton = 'Attach file or photo';
  static const String voiceButton = 'Record voice note';

  // Messages
  static String messageFrom(String sender) => 'Message from $sender';
  static String messageStatus(String status) => 'Message $status';
  static String imageMessage(String sender) => 'Image from $sender';
  static String voiceMessage(String sender, String duration) =>
      'Voice note from $sender, $duration';
  static String fileMessage(String sender, String fileName) =>
      'File from $sender: $fileName';

  // Contacts
  static String contact(String name, String status) => '$name, $status';
  static String peerOnline(String name) => '$name is online';
  static String peerOffline(String name) => '$name is offline';

  // Encryption
  static const String verifiedPeer = 'Verified peer';
  static const String unverifiedPeer = 'Unverified peer';
  static String fingerprint(String hash) => 'Fingerprint: $hash';

  // Status
  static String connectionStatus(int peers) =>
      '$peers peer${peers == 1 ? '' : 's'} connected';
  static const String miningProofOfWork = 'Mining proof of work';
  static const String encrypted = 'Message is encrypted';
}

/// High-contrast color helpers for accessibility.
class A11yColors {
  const A11yColors._();

  /// Check if a color has sufficient contrast against background.
  /// WCAG AA requires ratio >= 4.5:1 for normal text.
  static bool hasGoodContrast(Color foreground, Color background) {
    final ratio = contrastRatio(foreground, background);
    return ratio >= 4.5;
  }

  /// Calculate contrast ratio between two colors (1:1 to 21:1).
  static double contrastRatio(Color color1, Color color2) {
    final l1 = _luminance(color1);
    final l2 = _luminance(color2);
    final lighter = l1 > l2 ? l1 : l2;
    final darker = l1 > l2 ? l2 : l1;
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// Relative luminance of a color.
  static double _luminance(Color color) {
    double channel(double c) {
      return c <= 0.03928 ? c / 12.92 : _pow((c + 0.055) / 1.055, 2.4);
    }

    return 0.2126 * channel(color.r) +
        0.7152 * channel(color.g) +
        0.0722 * channel(color.b);
  }

  /// Simple power function.
  static double _pow(double base, double exp) {
    double result = 1;
    for (var i = 0; i < exp.toInt(); i++) {
      result *= base;
    }
    // Handle fractional part approximately
    if (exp % 1 > 0) {
      // Linear interpolation for fractional exponents
      final nextPow = result * base;
      result = result + (nextPow - result) * (exp % 1);
    }
    return result;
  }

  /// Suggest a high-contrast alternative for text on a background.
  static Color ensureContrast(Color foreground, Color background) {
    if (hasGoodContrast(foreground, background)) return foreground;
    // Try white or black
    final whiteRatio = contrastRatio(Colors.white, background);
    final blackRatio = contrastRatio(Colors.black, background);
    return whiteRatio > blackRatio ? Colors.white : Colors.black;
  }
}

/// Minimum touch target sizes (Material Design guidelines).
class TouchTargets {
  const TouchTargets._();

  /// Minimum interactive element size (48dp).
  static const double minimum = 48.0;

  /// Recommended size for primary actions.
  static const double recommended = 56.0;

  /// Ensure a widget meets minimum touch target.
  static Widget ensureMinimum({required Widget child, double? size}) {
    final targetSize = size ?? minimum;
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: targetSize, minHeight: targetSize),
      child: child,
    );
  }
}
