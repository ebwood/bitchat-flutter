import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bitchat/services/delivery_status.dart';
import 'package:bitchat/services/file_transfer.dart';
import 'package:bitchat/ui/qr_verification_screen.dart';

void main() {
  // ---------------------------------------------------------------------------
  // DeliveryStatus
  // ---------------------------------------------------------------------------
  group('DeliveryStatus', () {
    test('initial state is pending', () {
      final s = DeliveryStatus(messageId: 'msg1');
      expect(s.state, DeliveryState.pending);
      expect(s.statusIcon, '⏳');
    });

    test('state transitions work correctly', () {
      final s = DeliveryStatus(messageId: 'msg1');
      s.markSent();
      expect(s.state, DeliveryState.sent);
      expect(s.sentAt, isNotNull);

      s.markDelivered();
      expect(s.state, DeliveryState.delivered);
      expect(s.deliveredAt, isNotNull);

      s.markRead();
      expect(s.state, DeliveryState.read);
      expect(s.readAt, isNotNull);
    });

    test('cannot go backwards in state', () {
      final s = DeliveryStatus(messageId: 'msg1');
      s.markRead(); // jump ahead
      s.markSent(); // should not change
      expect(s.state, DeliveryState.read);
    });

    test('failed state works', () {
      final s = DeliveryStatus(messageId: 'msg1');
      s.markFailed('Network error');
      expect(s.state, DeliveryState.failed);
      expect(s.error, 'Network error');
      expect(s.statusIcon, '✗');
    });
  });

  group('ReadReceipt', () {
    test('JSON round-trip', () {
      final now = DateTime.now();
      final receipt = ReadReceipt(
        messageId: 'msg1',
        readerPeerId: 'peer1',
        timestamp: now,
      );
      final json = receipt.toJson();
      final restored = ReadReceipt.fromJson(json);
      expect(restored.messageId, 'msg1');
      expect(restored.readerPeerId, 'peer1');
    });
  });

  group('DeliveryTracker', () {
    test('track and get status', () {
      final tracker = DeliveryTracker();
      tracker.track('msg1');
      expect(tracker.getStatus('msg1'), isNotNull);
      expect(tracker.trackedCount, 1);
    });

    test('process read receipt', () {
      final tracker = DeliveryTracker();
      tracker.track('msg1');
      tracker.processReceipt(
        ReadReceipt(
          messageId: 'msg1',
          readerPeerId: 'peer1',
          timestamp: DateTime.now(),
        ),
      );
      expect(tracker.getStatus('msg1')!.state, DeliveryState.read);
    });

    test('get pending messages', () {
      final tracker = DeliveryTracker();
      tracker.track('msg1');
      tracker.track('msg2');
      tracker.markSent('msg2');
      expect(tracker.getPendingMessages().length, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // MimeType
  // ---------------------------------------------------------------------------
  group('MimeType', () {
    test('detects image types', () {
      expect(MimeType.fromFileName('photo.jpg'), 'image/jpeg');
      expect(MimeType.fromFileName('image.png'), 'image/png');
      expect(MimeType.fromFileName('anim.gif'), 'image/gif');
      expect(MimeType.isImage('photo.jpg'), true);
      expect(MimeType.isImage('doc.pdf'), false);
    });

    test('detects audio types', () {
      expect(MimeType.fromFileName('song.mp3'), 'audio/mpeg');
      expect(MimeType.isAudio('voice.aac'), true);
    });

    test('detects video types', () {
      expect(MimeType.fromFileName('clip.mp4'), 'video/mp4');
      expect(MimeType.isVideo('movie.mov'), true);
    });

    test('detects documents', () {
      expect(MimeType.fromFileName('report.pdf'), 'application/pdf');
      expect(MimeType.isDocument('report.pdf'), true);
      expect(MimeType.isDocument('data.csv'), true);
    });

    test('returns default for unknown', () {
      expect(MimeType.fromFileName('file.xyz'), 'application/octet-stream');
    });

    test('label for known types', () {
      expect(MimeType.labelForFileName('photo.jpg'), 'JPEG Image');
      expect(MimeType.labelForFileName('doc.pdf'), 'PDF Document');
      expect(MimeType.labelForFileName('unknown.xyz'), 'File');
    });
  });

  // ---------------------------------------------------------------------------
  // TransferProgressManager
  // ---------------------------------------------------------------------------
  group('TransferProgressManager', () {
    test('start and track transfer', () {
      final mgr = TransferProgressManager();
      mgr.startTransfer(
        transferId: 't1',
        fileName: 'file.zip',
        totalBytes: 1000,
      );
      expect(mgr.totalTransfers, 1);
      expect(mgr.getTransfer('t1')!.progress, 0.0);
    });

    test('update progress', () {
      final mgr = TransferProgressManager();
      mgr.startTransfer(transferId: 't1', fileName: 'f.zip', totalBytes: 100);
      mgr.updateProgress('t1', 50);
      expect(mgr.getTransfer('t1')!.progress, 0.5);
    });

    test('auto-completes when done', () {
      final mgr = TransferProgressManager();
      mgr.startTransfer(transferId: 't1', fileName: 'f.zip', totalBytes: 100);
      mgr.updateProgress('t1', 100);
      expect(mgr.getTransfer('t1')!.state, TransferState.completed);
    });

    test('fail and cancel work', () {
      final mgr = TransferProgressManager();
      mgr.startTransfer(transferId: 't1', fileName: 'f.zip', totalBytes: 100);
      mgr.failTransfer('t1', 'error');
      expect(mgr.getTransfer('t1')!.state, TransferState.failed);

      mgr.startTransfer(transferId: 't2', fileName: 'g.zip', totalBytes: 100);
      mgr.cancelTransfer('t2');
      expect(mgr.getTransfer('t2')!.state, TransferState.cancelled);
    });

    test('cleanup removes finished transfers', () {
      final mgr = TransferProgressManager();
      mgr.startTransfer(transferId: 't1', fileName: 'f.zip', totalBytes: 100);
      mgr.updateProgress('t1', 100); // completed
      mgr.startTransfer(transferId: 't2', fileName: 'g.zip', totalBytes: 100);
      mgr.cleanup();
      expect(mgr.totalTransfers, 1); // only t2 remains
    });

    test('progressText format', () {
      final mgr = TransferProgressManager();
      mgr.startTransfer(transferId: 't1', fileName: 'f.zip', totalBytes: 2048);
      mgr.updateProgress('t1', 1024);
      expect(mgr.getTransfer('t1')!.progressText, '50% (1.0 KB/2.0 KB)');
    });
  });

  // ---------------------------------------------------------------------------
  // QrVerificationScreen
  // ---------------------------------------------------------------------------
  group('QrVerificationScreen', () {
    testWidgets('shows fingerprint and QR grid', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: QrVerificationScreen(
            myFingerprint: 'abcd1234efgh5678',
            myNickname: 'Alice',
          ),
        ),
      );
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Your Fingerprint'), findsOneWidget);
    });

    testWidgets('shows peer comparison when provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: QrVerificationScreen(
            myFingerprint: 'abcd1234',
            myNickname: 'Alice',
            peerFingerprint: 'abcd1234',
            peerNickname: 'Bob',
          ),
        ),
      );
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Peer Fingerprint'), findsOneWidget);
      expect(find.text('Fingerprints match!'), findsOneWidget);
    });

    testWidgets('shows mismatch warning', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: QrVerificationScreen(
            myFingerprint: 'aaaa1111',
            myNickname: 'Alice',
            peerFingerprint: 'bbbb2222',
            peerNickname: 'Bob',
          ),
        ),
      );
      expect(find.text('Fingerprints do NOT match'), findsOneWidget);
    });
  });
}
