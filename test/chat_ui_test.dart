import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bitchat/services/rate_limiter.dart';
import 'package:bitchat/ui/message_formatter.dart';

void main() {
  // ---------------------------------------------------------------------------
  // RateLimiter
  // ---------------------------------------------------------------------------
  group('RateLimiter', () {
    test('allows burst of messages', () {
      final limiter = RateLimiter(maxBurst: 3);
      expect(limiter.tryConsume('ch1'), true);
      expect(limiter.tryConsume('ch1'), true);
      expect(limiter.tryConsume('ch1'), true);
    });

    test('blocks after burst exhausted', () {
      final limiter = RateLimiter(
        maxBurst: 2,
        cooldownDuration: const Duration(seconds: 5),
      );
      limiter.tryConsume('ch1');
      limiter.tryConsume('ch1');
      expect(limiter.tryConsume('ch1'), false);
    });

    test('different channels are independent', () {
      final limiter = RateLimiter(maxBurst: 1);
      limiter.tryConsume('ch1');
      expect(limiter.tryConsume('ch2'), true); // different channel
    });

    test('remainingCooldown is null when not limited', () {
      final limiter = RateLimiter();
      expect(limiter.remainingCooldown('ch1'), isNull);
    });

    test('remainingCooldown returns duration when limited', () {
      final limiter = RateLimiter(
        maxBurst: 1,
        cooldownDuration: const Duration(seconds: 5),
      );
      limiter.tryConsume('ch1');
      limiter.tryConsume('ch1'); // triggers cooldown
      final cd = limiter.remainingCooldown('ch1');
      expect(cd, isNotNull);
      expect(cd!.inSeconds, greaterThan(0));
    });

    test('availableTokens returns maxBurst for unused channel', () {
      final limiter = RateLimiter(maxBurst: 5);
      expect(limiter.availableTokens('ch1'), 5.0);
    });

    test('reset clears channel state', () {
      final limiter = RateLimiter(maxBurst: 1);
      limiter.tryConsume('ch1');
      limiter.reset('ch1');
      expect(limiter.tryConsume('ch1'), true);
    });

    test('resetAll clears all channels', () {
      final limiter = RateLimiter(maxBurst: 1);
      limiter.tryConsume('ch1');
      limiter.tryConsume('ch2');
      limiter.resetAll();
      expect(limiter.tryConsume('ch1'), true);
      expect(limiter.tryConsume('ch2'), true);
    });
  });

  // ---------------------------------------------------------------------------
  // InputValidator
  // ---------------------------------------------------------------------------
  group('InputValidator', () {
    test('empty message is invalid', () {
      final r = InputValidator.validateMessage('');
      expect(r.isValid, false);
    });

    test('normal message is valid', () {
      final r = InputValidator.validateMessage('hello');
      expect(r.isValid, true);
    });

    test('message over 2000 chars is invalid', () {
      final r = InputValidator.validateMessage('a' * 2001);
      expect(r.isValid, false);
    });

    test('message at exactly 2000 chars is valid', () {
      final r = InputValidator.validateMessage('a' * 2000);
      expect(r.isValid, true);
    });

    test('empty nickname is invalid', () {
      final r = InputValidator.validateNickname('');
      expect(r.isValid, false);
    });

    test('normal nickname is valid', () {
      final r = InputValidator.validateNickname('alice');
      expect(r.isValid, true);
    });

    test('nickname over 24 chars is invalid', () {
      final r = InputValidator.validateNickname('a' * 25);
      expect(r.isValid, false);
    });

    test('nickname with newlines is invalid', () {
      final r = InputValidator.validateNickname('alice\nbob');
      expect(r.isValid, false);
    });

    test('maxMessageLength is 2000', () {
      expect(InputValidator.maxMessageLength, 2000);
    });

    test('maxNicknameLength is 24', () {
      expect(InputValidator.maxNicknameLength, 24);
    });
  });

  // ---------------------------------------------------------------------------
  // MessageFormatter — URL detection
  // ---------------------------------------------------------------------------
  group('MessageFormatter URL detection', () {
    const baseStyle = TextStyle(fontSize: 13, fontFamily: 'monospace');

    test('detects https URL', () {
      final spans = MessageFormatter.format(
        'visit https://example.com today',
        baseStyle: baseStyle,
      );
      // Should be: "visit ", URL, " today"
      expect(spans.length, 3);
      final urlSpan = spans[1] as TextSpan;
      expect(urlSpan.text, 'https://example.com');
      expect(urlSpan.style?.decoration, TextDecoration.underline);
    });

    test('detects http URL', () {
      final spans = MessageFormatter.format(
        'go to http://test.org/page',
        baseStyle: baseStyle,
      );
      expect(spans.length, 2); // "go to " + URL
      final urlSpan = spans[1] as TextSpan;
      expect(urlSpan.text, 'http://test.org/page');
    });

    test('detects www URL', () {
      final spans = MessageFormatter.format(
        'see www.example.org for info',
        baseStyle: baseStyle,
      );
      expect(spans.length, 3);
      final urlSpan = spans[1] as TextSpan;
      expect(urlSpan.text, 'www.example.org');
    });

    test('no URL returns plain text', () {
      final spans = MessageFormatter.format(
        'no links here',
        baseStyle: baseStyle,
      );
      expect(spans.length, 1);
    });
  });
}
