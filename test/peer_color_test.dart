import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bitchat/ui/peer_color.dart';
import 'package:bitchat/ui/message_formatter.dart';

void main() {
  // ---------------------------------------------------------------------------
  // PeerColor
  // ---------------------------------------------------------------------------
  group('PeerColor', () {
    test('same nickname produces same color', () {
      final c1 = PeerColor.forNickname('alice');
      final c2 = PeerColor.forNickname('alice');
      expect(c1, equals(c2));
    });

    test('different nicknames produce different colors', () {
      final c1 = PeerColor.forNickname('alice');
      final c2 = PeerColor.forNickname('bob');
      expect(c1, isNot(equals(c2)));
    });

    test('same pubkey produces same color', () {
      const pubkey =
          'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2';
      final c1 = PeerColor.forPubKey(pubkey);
      final c2 = PeerColor.forPubKey(pubkey);
      expect(c1, equals(c2));
    });

    test('case insensitive for pubkey', () {
      const pk = 'AABBCC';
      final c1 = PeerColor.forPubKey(pk);
      final c2 = PeerColor.forPubKey(pk.toLowerCase());
      expect(c1, equals(c2));
    });

    test('selfColor is orange', () {
      expect(PeerColor.selfColor, const Color(0xFFFF9500));
    });

    test('dark and light mode produce different colors', () {
      final dark = PeerColor.forNickname('alice', isDark: true);
      final light = PeerColor.forNickname('alice', isDark: false);
      expect(dark, isNot(equals(light)));
    });
  });

  // ---------------------------------------------------------------------------
  // MessageFormatter
  // ---------------------------------------------------------------------------
  group('MessageFormatter', () {
    const baseStyle = TextStyle(fontSize: 13, fontFamily: 'monospace');

    test('plain text produces single TextSpan', () {
      final spans = MessageFormatter.format(
        'hello world',
        baseStyle: baseStyle,
      );
      expect(spans.length, 1);
      expect((spans[0] as TextSpan).text, 'hello world');
    });

    test('bold text wrapped in **', () {
      final spans = MessageFormatter.format(
        'hello **bold** world',
        baseStyle: baseStyle,
      );
      // Should be 3 spans: "hello ", "bold", " world"
      expect(spans.length, 3);
      final boldSpan = spans[1] as TextSpan;
      expect(boldSpan.text, 'bold');
      expect(boldSpan.style?.fontWeight, FontWeight.bold);
    });

    test('italic text wrapped in *', () {
      final spans = MessageFormatter.format(
        'hello *italic* world',
        baseStyle: baseStyle,
      );
      expect(spans.length, 3);
      final italicSpan = spans[1] as TextSpan;
      expect(italicSpan.text, 'italic');
      expect(italicSpan.style?.fontStyle, FontStyle.italic);
    });

    test('code text wrapped in backticks', () {
      final spans = MessageFormatter.format(
        'run `flutter test` now',
        baseStyle: baseStyle,
      );
      expect(spans.length, 3);
      // Code span is a WidgetSpan
      expect(spans[1], isA<WidgetSpan>());
    });

    test('no formatting markers returns plain text', () {
      final spans = MessageFormatter.format(
        'just plain text',
        baseStyle: baseStyle,
      );
      expect(spans.length, 1);
    });

    test('unclosed markers treated as plain text', () {
      final spans = MessageFormatter.format(
        'unclosed **bold without end',
        baseStyle: baseStyle,
      );
      // Since there's no closing **, it should be plain text
      expect(spans.length, 1);
    });
  });
}
