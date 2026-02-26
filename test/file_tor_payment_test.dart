import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bitchat/services/file_picker_service.dart';
import 'package:bitchat/services/tor_preference.dart';
import 'package:bitchat/ui/widgets/payment_chip.dart';

void main() {
  // ---------------------------------------------------------------------------
  // FilePickerService
  // ---------------------------------------------------------------------------
  group('FilePickerService', () {
    test('allowed extensions for each mode', () {
      expect(FilePickerService.allowedExtensions(FilePickMode.any), isNull);
      expect(
        FilePickerService.allowedExtensions(FilePickMode.image),
        contains('jpg'),
      );
      expect(
        FilePickerService.allowedExtensions(FilePickMode.audio),
        contains('mp3'),
      );
      expect(
        FilePickerService.allowedExtensions(FilePickMode.video),
        contains('mp4'),
      );
      expect(
        FilePickerService.allowedExtensions(FilePickMode.document),
        contains('pdf'),
      );
    });

    test('validate file size', () {
      final valid = PickedFile(
        name: 'small.txt',
        path: '/tmp/small.txt',
        size: 1024,
      );
      expect(FilePickerService.validate(valid).isValid, true);

      final tooLarge = PickedFile(
        name: 'huge.zip',
        path: '/tmp/huge.zip',
        size: 20 * 1024 * 1024, // 20 MB
      );
      expect(FilePickerService.validate(tooLarge).isValid, false);
      expect(FilePickerService.validate(tooLarge).error, contains('too large'));
    });

    test('PickedFile extension and size formatting', () {
      final file = PickedFile(
        name: 'report.pdf',
        path: '/tmp/report.pdf',
        size: 2048,
      );
      expect(file.extension, 'pdf');
      expect(file.formattedSize, '2.0 KB');
    });
  });

  group('FileViewerService', () {
    test('can preview images and text in-app', () {
      expect(FileViewerService.canPreviewInApp('photo.jpg'), true);
      expect(FileViewerService.canPreviewInApp('notes.txt'), true);
      expect(FileViewerService.canPreviewInApp('data.json'), true);
    });

    test('cannot preview binary files in-app', () {
      expect(FileViewerService.canPreviewInApp('app.apk'), false);
      expect(FileViewerService.canPreviewInApp('archive.zip'), false);
      expect(FileViewerService.canPreviewInApp('movie.mp4'), false);
    });

    test('action labels', () {
      expect(FileViewerService.actionLabel('photo.png'), 'Preview');
      expect(FileViewerService.actionLabel('app.exe'), 'Open With...');
    });
  });

  // ---------------------------------------------------------------------------
  // TorPreferenceManager
  // ---------------------------------------------------------------------------
  group('TorPreferenceManager', () {
    late TorPreferenceManager tor;

    setUp(() {
      tor = TorPreferenceManager();
    });

    test('initial state is off', () {
      expect(tor.mode, TorMode.off);
      expect(tor.connectionState, TorConnectionState.disabled);
      expect(tor.shouldRouteThrough, false);
    });

    test('set mode to whenAvailable', () {
      tor.setMode(TorMode.whenAvailable);
      expect(tor.mode, TorMode.whenAvailable);
      expect(tor.allowDirectConnection, true);
    });

    test('set mode to always', () {
      tor.setMode(TorMode.always);
      expect(tor.allowDirectConnection, false);
    });

    test('simulate connection lifecycle', () {
      tor.setMode(TorMode.whenAvailable);
      tor.simulateConnecting();
      expect(tor.connectionState, TorConnectionState.connecting);

      tor.simulateConnected(address: '127.0.0.1', port: 9050);
      expect(tor.connectionState, TorConnectionState.connected);
      expect(tor.socksProxyUrl, 'socks5://127.0.0.1:9050');
      expect(tor.shouldRouteThrough, true);
      expect(tor.uptime, isNotNull);
    });

    test('simulate failure', () {
      tor.setMode(TorMode.whenAvailable);
      tor.simulateFailed('Network unreachable');
      expect(tor.connectionState, TorConnectionState.failed);
      expect(tor.lastError, 'Network unreachable');
      expect(tor.shouldRouteThrough, false);
    });

    test('off mode ignores connect attempts', () {
      tor.simulateConnecting(); // mode is off
      expect(tor.connectionState, TorConnectionState.disabled);
    });

    test('statusText for each state', () {
      expect(tor.statusText, 'Tor disabled');
      tor.setMode(TorMode.always);
      tor.simulateConnected();
      expect(tor.statusText, 'Connected via Tor');
    });

    test('mode descriptions exist', () {
      for (final mode in TorMode.values) {
        expect(TorPreferenceManager.modeDescription(mode), isNotEmpty);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // PaymentChip
  // ---------------------------------------------------------------------------
  group('LightningPayment', () {
    test('formatted amount', () {
      expect(
        LightningPayment(
          paymentId: 'p1',
          amountSats: 500,
          senderPeerId: 's1',
        ).formattedAmount,
        '500 sats',
      );
      expect(
        LightningPayment(
          paymentId: 'p2',
          amountSats: 2500,
          senderPeerId: 's1',
        ).formattedAmount,
        '2.5K sats',
      );
      expect(
        LightningPayment(
          paymentId: 'p3',
          amountSats: 1500000,
          senderPeerId: 's1',
        ).formattedAmount,
        '1.5M sats',
      );
    });

    test('isActionable based on state', () {
      final p = LightningPayment(
        paymentId: 'p1',
        amountSats: 100,
        senderPeerId: 's1',
      );
      expect(p.isActionable, true);
      p.state = PaymentState.completed;
      expect(p.isActionable, false);
    });

    test('amountBtc conversion', () {
      final p = LightningPayment(
        paymentId: 'p1',
        amountSats: 100000000,
        senderPeerId: 's1',
      );
      expect(p.amountBtc, 1.0);
    });
  });

  group('PaymentChip widget', () {
    testWidgets('shows amount and status', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaymentChip(
              payment: LightningPayment(
                paymentId: 'p1',
                amountSats: 1000,
                senderPeerId: 's1',
                memo: 'Coffee tip',
              ),
            ),
          ),
        ),
      );
      expect(find.text('1.0K sats'), findsOneWidget);
      expect(find.text('Coffee tip'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
    });

    testWidgets('compact mode hides memo', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaymentChip(
              payment: LightningPayment(
                paymentId: 'p1',
                amountSats: 100,
                senderPeerId: 's1',
                memo: 'Hidden memo',
              ),
              compact: true,
            ),
          ),
        ),
      );
      expect(find.text('100 sats'), findsOneWidget);
      expect(find.text('Hidden memo'), findsNothing);
    });
  });
}
