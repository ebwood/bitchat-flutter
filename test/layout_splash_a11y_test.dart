import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bitchat/ui/adaptive_layout.dart';
import 'package:bitchat/ui/splash_screen.dart';
import 'package:bitchat/ui/accessibility.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Adaptive Layout
  // ---------------------------------------------------------------------------
  group('Breakpoints', () {
    test('phone below 600', () {
      expect(Breakpoints.fromWidth(400), DeviceType.phone);
    });
    test('tablet 600-1024', () {
      expect(Breakpoints.fromWidth(768), DeviceType.tablet);
    });
    test('desktop above 1024', () {
      expect(Breakpoints.fromWidth(1200), DeviceType.desktop);
    });
  });

  group('AdaptiveLayout', () {
    testWidgets('shows phone layout on narrow screen', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: AdaptiveLayout(
            phone: Text('phone'),
            tablet: Text('tablet'),
            desktop: Text('desktop'),
          ),
        ),
      );
      expect(find.text('phone'), findsOneWidget);
    });

    testWidgets('shows tablet layout on medium screen', (tester) async {
      tester.view.physicalSize = const Size(800, 1024);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: AdaptiveLayout(phone: Text('phone'), tablet: Text('tablet')),
        ),
      );
      expect(find.text('tablet'), findsOneWidget);
    });
  });

  group('MasterDetailLayout', () {
    testWidgets('shows master only on phone', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: MasterDetailLayout(
            master: Text('list'),
            detail: Text('content'),
          ),
        ),
      );
      expect(find.text('list'), findsOneWidget);
      expect(find.text('content'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // SplashScreen
  // ---------------------------------------------------------------------------
  group('SplashScreen', () {
    testWidgets('shows BitChat text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SplashScreen(
            onComplete: () {},
            duration: const Duration(milliseconds: 500),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('BitChat'), findsOneWidget);
    });

    testWidgets('calls onComplete after animation', (tester) async {
      var completed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: SplashScreen(
            onComplete: () => completed = true,
            duration: const Duration(milliseconds: 100),
          ),
        ),
      );
      // Wait for animation to complete + 300ms post-delay
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      expect(completed, true);
    });
  });

  // ---------------------------------------------------------------------------
  // Accessibility
  // ---------------------------------------------------------------------------
  group('SemanticLabels', () {
    test('message labels', () {
      expect(SemanticLabels.messageFrom('Alice'), 'Message from Alice');
      expect(SemanticLabels.connectionStatus(3), '3 peers connected');
      expect(SemanticLabels.connectionStatus(1), '1 peer connected');
    });

    test('file labels', () {
      expect(
        SemanticLabels.fileMessage('Bob', 'photo.jpg'),
        'File from Bob: photo.jpg',
      );
    });
  });

  group('A11yColors', () {
    test('black on white has good contrast', () {
      expect(A11yColors.hasGoodContrast(Colors.black, Colors.white), true);
    });

    test('white on white has bad contrast', () {
      expect(A11yColors.hasGoodContrast(Colors.white, Colors.white), false);
    });

    test('ensureContrast picks accessible color', () {
      // Light gray on white → should return black
      final result = A11yColors.ensureContrast(Colors.grey[300]!, Colors.white);
      expect(result, Colors.black);
    });

    test('contrast ratio range', () {
      final ratio = A11yColors.contrastRatio(Colors.black, Colors.white);
      expect(ratio, greaterThan(15)); // Should be ~21:1
    });
  });

  group('TouchTargets', () {
    testWidgets('ensureMinimum wraps with constraints', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TouchTargets.ensureMinimum(
              child: const SizedBox(width: 20, height: 20),
            ),
          ),
        ),
      );
      // The wrapper should enforce minimum size
      final finder = find.byType(ConstrainedBox);
      expect(finder, findsWidgets);
      final box = tester.firstRenderObject<RenderBox>(finder);
      expect(box.constraints.minWidth, greaterThanOrEqualTo(48));
    });
  });

  group('Semantic widget', () {
    testWidgets('provides semantics', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Semantic(
              label: 'Send message button',
              isButton: true,
              child: Icon(Icons.send),
            ),
          ),
        ),
      );
      final semantics = tester.getSemantics(find.byType(Semantic));
      expect(semantics.label, 'Send message button');
    });
  });
}
