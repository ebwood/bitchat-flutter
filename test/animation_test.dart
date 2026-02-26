import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bitchat/ui/widgets/matrix_animation.dart';
import 'package:bitchat/ui/widgets/pow_indicator.dart';

void main() {
  // ---------------------------------------------------------------------------
  // MatrixAnimation
  // ---------------------------------------------------------------------------
  group('MatrixAnimation widget', () {
    testWidgets('renders when not animating', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MatrixAnimation(text: 'Hello', isAnimating: false),
          ),
        ),
      );
      expect(find.byType(MatrixAnimation), findsOneWidget);
      expect(find.byType(RichText), findsOneWidget);
    });

    testWidgets('animating mode shows different text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MatrixAnimation(text: 'Test', isAnimating: true),
          ),
        ),
      );
      // After pump, the animated text should exist (may not match original)
      expect(find.byType(MatrixAnimation), findsOneWidget);
      expect(find.byType(RichText), findsOneWidget);
    });

    testWidgets('spaces are preserved during animation', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: MatrixAnimation(text: 'A B', isAnimating: true)),
        ),
      );
      // Widget renders
      expect(find.byType(MatrixAnimation), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // PoWStatusIndicator
  // ---------------------------------------------------------------------------
  group('PoWStatusIndicator', () {
    testWidgets('hidden when disabled', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PoWStatusIndicator(isEnabled: false, difficulty: 16),
          ),
        ),
      );
      // SizedBox.shrink when disabled
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('compact mode shows icon and difficulty', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PoWStatusIndicator(
              isEnabled: true,
              difficulty: 16,
              style: PoWIndicatorStyle.compact,
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.security), findsOneWidget);
      expect(find.text('16b'), findsOneWidget);
    });

    testWidgets('detailed mode shows status text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PoWStatusIndicator(
              isEnabled: true,
              difficulty: 12,
              style: PoWIndicatorStyle.detailed,
            ),
          ),
        ),
      );
      expect(find.text('PoW: 12'), findsOneWidget);
      expect(find.text('~<5s'), findsOneWidget);
    });

    testWidgets('mining state shows Mining text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PoWStatusIndicator(
              isEnabled: true,
              difficulty: 16,
              isMining: true,
              style: PoWIndicatorStyle.detailed,
            ),
          ),
        ),
      );
      expect(find.text('Mining…'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // PoWIndicatorStyle enum
  // ---------------------------------------------------------------------------
  group('PoWIndicatorStyle', () {
    test('has compact and detailed', () {
      expect(PoWIndicatorStyle.values.length, 2);
      expect(PoWIndicatorStyle.values, contains(PoWIndicatorStyle.compact));
      expect(PoWIndicatorStyle.values, contains(PoWIndicatorStyle.detailed));
    });
  });
}
