import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bitchat/ui/widgets/file_message_bubble.dart';
import 'package:bitchat/ui/debug_panel.dart';

void main() {
  // ---------------------------------------------------------------------------
  // FileMessageBubble
  // ---------------------------------------------------------------------------
  group('FileMessageBubble', () {
    testWidgets('shows file name and size', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FileMessageBubble(
              fileName: 'document.pdf',
              fileSize: 1048576, // 1 MB
            ),
          ),
        ),
      );
      expect(find.text('document.pdf'), findsOneWidget);
      expect(find.text('1.0 MB'), findsOneWidget);
      expect(find.byIcon(Icons.picture_as_pdf), findsOneWidget);
    });

    testWidgets('shows progress indicator when transferring', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FileMessageBubble(
              fileName: 'video.mp4',
              fileSize: 5242880,
              progress: 0.5,
            ),
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows download icon when complete', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FileMessageBubble(fileName: 'photo.jpg', fileSize: 512000),
          ),
        ),
      );
      expect(find.byIcon(Icons.download), findsOneWidget);
    });

    testWidgets('shows check icon for outgoing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FileMessageBubble(
              fileName: 'notes.txt',
              fileSize: 256,
              isOutgoing: true,
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });

    testWidgets('formats sizes correctly', (tester) async {
      // Bytes
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FileMessageBubble(fileName: 'a.txt', fileSize: 512),
          ),
        ),
      );
      expect(find.text('512 B'), findsOneWidget);

      // KB
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FileMessageBubble(fileName: 'b.txt', fileSize: 2048),
          ),
        ),
      );
      expect(find.text('2.0 KB'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // MediaPickerSheet
  // ---------------------------------------------------------------------------
  group('MediaPickerSheet', () {
    testWidgets('shows photo, file, voice options', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: MediaPickerSheet())),
      );
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Photo'), findsOneWidget);
      expect(find.text('File'), findsOneWidget);
      expect(find.text('Voice'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // DebugPanel
  // ---------------------------------------------------------------------------
  group('DebugPanel', () {
    testWidgets('shows network stats', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: DebugPanel(
            relayStatus: 'Connected',
            connectedPeers: 3,
            messagesSent: 42,
          ),
        ),
      );
      expect(find.text('Debug Panel'), findsOneWidget);
      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
    });

    testWidgets('shows experimental toggles', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: DebugPanel()));
      expect(find.text('Proof of Work'), findsOneWidget);
      expect(find.text('Cover Traffic'), findsOneWidget);
      expect(find.text('Compression'), findsOneWidget);
    });

    testWidgets('shows protocol info', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: DebugPanel()));
      // Scroll down to reveal protocol section
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.text('XX_25519_ChaChaPoly_SHA256'), findsOneWidget);
    });
  });
}
