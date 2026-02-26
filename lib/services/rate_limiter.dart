/// Rate limiter for chat messages — prevents message flooding.
///
/// Matches the iOS/Android behavior:
/// - Token bucket algorithm (burst of N, refill M per second)
/// - Per-channel rate limiting
/// - Cool-down period on burst exhaustion
class RateLimiter {
  RateLimiter({
    this.maxBurst = 5,
    this.refillRate = 1.0,
    this.cooldownDuration = const Duration(seconds: 3),
  });

  /// Maximum messages allowed in a burst.
  final int maxBurst;

  /// Tokens added per second.
  final double refillRate;

  /// Cooldown after tokens are exhausted.
  final Duration cooldownDuration;

  // Per-channel state
  final Map<String, _BucketState> _buckets = {};

  /// Check if a message can be sent on this channel.
  /// Returns true if allowed, false if rate-limited.
  bool tryConsume(String channel) {
    final now = DateTime.now();
    final bucket = _buckets.putIfAbsent(
      channel,
      () => _BucketState(tokens: maxBurst.toDouble(), lastRefill: now),
    );

    // Cooldown check
    if (bucket.cooldownUntil != null && now.isBefore(bucket.cooldownUntil!)) {
      return false;
    }

    // Refill tokens based on time elapsed
    final elapsed = now.difference(bucket.lastRefill).inMilliseconds / 1000.0;
    bucket.tokens = (bucket.tokens + elapsed * refillRate).clamp(
      0,
      maxBurst.toDouble(),
    );
    bucket.lastRefill = now;

    // Try to consume a token
    if (bucket.tokens >= 1.0) {
      bucket.tokens -= 1.0;
      bucket.cooldownUntil = null;
      return true;
    }

    // Exhausted — enter cooldown
    bucket.cooldownUntil = now.add(cooldownDuration);
    return false;
  }

  /// Get remaining cooldown time for a channel.
  Duration? remainingCooldown(String channel) {
    final bucket = _buckets[channel];
    if (bucket?.cooldownUntil == null) return null;
    final remaining = bucket!.cooldownUntil!.difference(DateTime.now());
    return remaining.isNegative ? null : remaining;
  }

  /// Get current token count for a channel.
  double availableTokens(String channel) {
    final bucket = _buckets[channel];
    if (bucket == null) return maxBurst.toDouble();

    final now = DateTime.now();
    final elapsed = now.difference(bucket.lastRefill).inMilliseconds / 1000.0;
    return (bucket.tokens + elapsed * refillRate).clamp(0, maxBurst.toDouble());
  }

  /// Reset rate limiter for a channel.
  void reset(String channel) {
    _buckets.remove(channel);
  }

  /// Reset all channels.
  void resetAll() {
    _buckets.clear();
  }
}

class _BucketState {
  _BucketState({
    required this.tokens,
    required this.lastRefill,
    this.cooldownUntil,
  });

  double tokens;
  DateTime lastRefill;
  DateTime? cooldownUntil;
}

/// Input validator for chat messages and nicknames.
class InputValidator {
  InputValidator._();

  /// Maximum message length (matches iOS/Android limits).
  static const int maxMessageLength = 2000;

  /// Maximum nickname length.
  static const int maxNicknameLength = 24;

  /// Minimum nickname length.
  static const int minNicknameLength = 1;

  /// Validate a chat message.
  static ValidationResult validateMessage(String text) {
    if (text.isEmpty) {
      return const ValidationResult(false, 'Message cannot be empty');
    }
    if (text.length > maxMessageLength) {
      return ValidationResult(
        false,
        'Message too long (${text.length}/$maxMessageLength chars)',
      );
    }
    return const ValidationResult(true, null);
  }

  /// Validate a nickname.
  static ValidationResult validateNickname(String nickname) {
    final trimmed = nickname.trim();
    if (trimmed.length < minNicknameLength) {
      return const ValidationResult(false, 'Nickname cannot be empty');
    }
    if (trimmed.length > maxNicknameLength) {
      return ValidationResult(
        false,
        'Nickname too long (${trimmed.length}/$maxNicknameLength chars)',
      );
    }
    // No special characters that could break the protocol
    if (trimmed.contains('\n') || trimmed.contains('\r')) {
      return const ValidationResult(false, 'Nickname cannot contain newlines');
    }
    return const ValidationResult(true, null);
  }
}

/// Result of an input validation check.
class ValidationResult {
  const ValidationResult(this.isValid, this.error);

  final bool isValid;
  final String? error;
}
