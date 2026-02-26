import 'package:flutter/material.dart';

/// Lightning payment chip — Bitcoin LN payment/tip in chat.
///
/// Matches Android `PaymentChip` concept.
/// Provides the UI component; actual payment requires
/// a Lightning wallet SDK (e.g., Breez, LDK, or LNURL).

/// Payment state.
enum PaymentState {
  /// Payment request created, pending.
  pending,

  /// Payment is being processed.
  processing,

  /// Payment completed successfully.
  completed,

  /// Payment failed or expired.
  failed,

  /// Payment expired before completion.
  expired,
}

/// A Lightning payment/tip in chat.
class LightningPayment {
  LightningPayment({
    required this.paymentId,
    required this.amountSats,
    required this.senderPeerId,
    this.recipientPeerId,
    this.memo,
    this.invoice,
    this.state = PaymentState.pending,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String paymentId;
  final int amountSats;
  final String senderPeerId;
  final String? recipientPeerId;
  final String? memo;
  final String? invoice;
  PaymentState state;
  final DateTime createdAt;

  /// Amount in BTC.
  double get amountBtc => amountSats / 100000000;

  /// Formatted amount string.
  String get formattedAmount {
    if (amountSats >= 1000000) {
      return '${(amountSats / 1000000).toStringAsFixed(1)}M sats';
    }
    if (amountSats >= 1000) {
      return '${(amountSats / 1000).toStringAsFixed(1)}K sats';
    }
    return '$amountSats sats';
  }

  /// Whether payment is still actionable.
  bool get isActionable =>
      state == PaymentState.pending || state == PaymentState.processing;
}

/// Lightning payment chip widget for chat bubbles.
class PaymentChip extends StatelessWidget {
  const PaymentChip({
    super.key,
    required this.payment,
    this.onTap,
    this.compact = false,
  });

  final LightningPayment payment;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stateColor = _colorForState(payment.state);
    final btcOrange = const Color(0xFFF7931A);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12,
          vertical: compact ? 4 : 8,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              btcOrange.withValues(alpha: isDark ? 0.15 : 0.08),
              stateColor.withValues(alpha: isDark ? 0.1 : 0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(compact ? 12 : 10),
          border: Border.all(color: btcOrange.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Lightning icon
            Icon(Icons.bolt, size: compact ? 14 : 18, color: btcOrange),
            SizedBox(width: compact ? 4 : 6),

            // Amount
            Text(
              payment.formattedAmount,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: compact ? 11 : 13,
                fontWeight: FontWeight.bold,
                color: btcOrange,
              ),
            ),

            if (!compact && payment.memo != null) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  payment.memo!,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],

            const SizedBox(width: 6),

            // Status indicator
            _StatusBadge(state: payment.state, compact: compact),
          ],
        ),
      ),
    );
  }

  static Color _colorForState(PaymentState state) {
    switch (state) {
      case PaymentState.pending:
        return const Color(0xFFF7931A);
      case PaymentState.processing:
        return const Color(0xFF007AFF);
      case PaymentState.completed:
        return const Color(0xFF32D74B);
      case PaymentState.failed:
        return const Color(0xFFFF3B30);
      case PaymentState.expired:
        return const Color(0xFF8E8E93);
    }
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.state, required this.compact});
  final PaymentState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (state) {
      PaymentState.pending => (
        Icons.schedule,
        const Color(0xFFF7931A),
        'Pending',
      ),
      PaymentState.processing => (
        Icons.sync,
        const Color(0xFF007AFF),
        'Sending',
      ),
      PaymentState.completed => (
        Icons.check_circle,
        const Color(0xFF32D74B),
        'Paid',
      ),
      PaymentState.failed => (
        Icons.error_outline,
        const Color(0xFFFF3B30),
        'Failed',
      ),
      PaymentState.expired => (
        Icons.timer_off,
        const Color(0xFF8E8E93),
        'Expired',
      ),
    };

    if (compact) {
      return Icon(icon, size: 12, color: color);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
