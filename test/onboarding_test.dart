import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bitchat/services/gcs_filter.dart';
import 'package:bitchat/ui/onboarding_screen.dart';

void main() {
  // ---------------------------------------------------------------------------
  // GcsFilter
  // ---------------------------------------------------------------------------
  group('GcsFilter', () {
    test('empty build produces empty filter', () {
      final filter = GcsFilter();
      filter.build([]);
      expect(filter.count, 0);
      expect(filter.data, isNotNull);
      expect(filter.data!.isEmpty, true);
    });

    test('built filter contains added elements', () {
      final filter = GcsFilter();
      filter.build(['msg1', 'msg2', 'msg3']);
      expect(filter.count, 3);
      expect(filter.mightContain('msg1'), true);
      expect(filter.mightContain('msg2'), true);
      expect(filter.mightContain('msg3'), true);
    });

    test('filter does not contain non-added elements (low false positive)', () {
      final filter = GcsFilter();
      final ids = List.generate(100, (i) => 'message_$i');
      filter.build(ids);

      // Check a few non-members — should mostly be false
      var falsePositives = 0;
      for (var i = 1000; i < 1100; i++) {
        if (filter.mightContain('nonexistent_$i')) falsePositives++;
      }
      // With M=784931, expect < 5% false positive rate
      expect(falsePositives, lessThan(10));
    });

    test('serialize and deserialize round-trips', () {
      final filter = GcsFilter();
      filter.build(['a', 'b', 'c']);

      final bytes = filter.serialize();
      final restored = GcsFilter.deserialize(bytes);

      expect(restored.count, 3);
      expect(restored.mightContain('a'), true);
      expect(restored.mightContain('b'), true);
      expect(restored.mightContain('c'), true);
    });

    test('bitsPerElement is reasonable', () {
      final filter = GcsFilter();
      filter.build(List.generate(100, (i) => 'msg_$i'));
      // GCS should use ~20 bits per element (for P=19)
      expect(filter.bitsPerElement, greaterThan(10));
      expect(filter.bitsPerElement, lessThan(40));
    });

    test('estimatedFalsePositiveRate matches 1/M', () {
      final filter = GcsFilter();
      expect(filter.estimatedFalsePositiveRate, closeTo(1.0 / 784931, 1e-10));
    });

    test('single element filter works', () {
      final filter = GcsFilter();
      filter.build(['only_one']);
      expect(filter.count, 1);
      expect(filter.mightContain('only_one'), true);
    });
  });

  // ---------------------------------------------------------------------------
  // OnboardingScreen
  // ---------------------------------------------------------------------------
  group('OnboardingScreen', () {
    testWidgets('shows welcome page initially', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: OnboardingScreen(onComplete: (_) {})),
      );
      expect(find.text('Welcome to BitChat'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
    });

    testWidgets('navigates to nickname page on Next', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: OnboardingScreen(onComplete: (_) {})),
      );
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Choose Your Name'), findsOneWidget);
    });

    testWidgets('navigates through all 4 pages', (tester) async {
      String? completedNickname;
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(
            onComplete: (nick) => completedNickname = nick,
          ),
        ),
      );

      // Page 1 → 2
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Choose Your Name'), findsOneWidget);

      // Page 2 → 3
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Permissions'), findsOneWidget);

      // Page 3 → 4
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text("You're Ready!"), findsOneWidget);

      // Page 4 → complete
      await tester.tap(find.text('Get Started'));
      await tester.pumpAndSettle();
      expect(completedNickname, isNotNull);
    });
  });
}
