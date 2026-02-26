import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

import 'package:bitchat/services/power_mode_manager.dart';
import 'package:bitchat/services/emergency_wipe.dart';
import 'package:bitchat/services/message_compressor.dart';
import 'package:bitchat/services/cover_traffic.dart';
import 'package:bitchat/services/protocol_negotiator.dart';
import 'package:bitchat/services/tor_manager.dart';
import 'package:bitchat/services/notification_service.dart';

void main() {
  // -------------------------------------------------------------------------
  // PowerModeManager
  // -------------------------------------------------------------------------
  group('PowerModeManager', () {
    test('default mode is balanced', () {
      final mgr = PowerModeManager();
      expect(mgr.currentMode, PowerMode.balanced);
    });

    test('setMode changes mode', () {
      final mgr = PowerModeManager();
      mgr.setMode(PowerMode.performance);
      expect(mgr.currentMode, PowerMode.performance);
      mgr.setMode(PowerMode.ultraLow);
      expect(mgr.currentMode, PowerMode.ultraLow);
    });

    test('adaptToBattery selects correct modes', () {
      final mgr = PowerModeManager();

      mgr.adaptToBattery(100);
      expect(mgr.currentMode, PowerMode.performance);

      mgr.adaptToBattery(50);
      expect(mgr.currentMode, PowerMode.balanced);

      mgr.adaptToBattery(20);
      expect(mgr.currentMode, PowerMode.lowPower);

      mgr.adaptToBattery(5);
      expect(mgr.currentMode, PowerMode.ultraLow);
    });

    test('config returns correct values for each mode', () {
      final mgr = PowerModeManager();

      mgr.setMode(PowerMode.performance);
      expect(mgr.config.maxConnections, 7);
      expect(mgr.config.relayEnabled, true);
      expect(mgr.config.coverTrafficEnabled, true);

      mgr.setMode(PowerMode.ultraLow);
      expect(mgr.config.maxConnections, 1);
      expect(mgr.config.relayEnabled, false);
    });

    test('modeStream emits on change', () async {
      final mgr = PowerModeManager();

      final modes = <PowerMode>[];
      mgr.modeStream.listen(modes.add);

      mgr.setMode(PowerMode.performance);
      mgr.setMode(PowerMode.lowPower);

      await Future.delayed(Duration.zero);
      expect(modes, [PowerMode.performance, PowerMode.lowPower]);

      mgr.dispose();
    });

    test('modeDescription returns non-empty', () {
      final mgr = PowerModeManager();
      for (final mode in PowerMode.values) {
        mgr.setMode(mode);
        expect(mgr.modeDescription.isNotEmpty, true);
      }
    });
  });

  // -------------------------------------------------------------------------
  // EmergencyWipe
  // -------------------------------------------------------------------------
  group('EmergencyWipe', () {
    test('single tap does not trigger wipe', () {
      final wipe = EmergencyWipe();
      expect(wipe.registerTap(), false);
    });

    test('triple tap triggers wipe', () {
      final wipe = EmergencyWipe(requiredTaps: 3);
      expect(wipe.registerTap(), false);
      expect(wipe.registerTap(), false);
      expect(wipe.registerTap(), true);
    });

    test('taps outside window do not count', () {
      final wipe = EmergencyWipe(requiredTaps: 3, tapWindow: Duration.zero);
      wipe.registerTap();
      wipe.registerTap();
      // All taps are immediately "expired"
      expect(wipe.registerTap(), false);
    });

    test('custom tap count', () {
      final wipe = EmergencyWipe(requiredTaps: 5);
      for (var i = 0; i < 4; i++) {
        expect(wipe.registerTap(), false);
      }
      expect(wipe.registerTap(), true);
    });
  });

  // -------------------------------------------------------------------------
  // MessageCompressor
  // -------------------------------------------------------------------------
  group('MessageCompressor', () {
    test('compress and decompress round-trip', () {
      final compressor = MessageCompressor();
      final original = Uint8List.fromList(
        List.generate(200, (i) => i % 26 + 65), // repeating ASCII
      );
      final compressed = compressor.compress(original);
      final decompressed = compressor.decompress(compressed);
      expect(decompressed, original);
    });

    test('empty data returns empty', () {
      final compressor = MessageCompressor();
      expect(compressor.compress(Uint8List(0)), isEmpty);
      expect(compressor.decompress(Uint8List(0)), isEmpty);
    });

    test('small data may not compress', () {
      final compressor = MessageCompressor();
      final tiny = Uint8List.fromList([1, 2, 3]);
      final result = compressor.compress(tiny);
      // Either compressed or uncompressed marker
      expect(result[0] == 0xCC || result[0] == 0x00, true);

      // Round-trip still works
      final back = compressor.decompress(result);
      expect(back, tiny);
    });

    test('compression ratio is positive', () {
      final compressor = MessageCompressor();
      final data = Uint8List.fromList(List.filled(500, 65));
      final ratio = compressor.compressionRatio(data);
      expect(ratio, greaterThan(0));
      expect(ratio, lessThanOrEqualTo(2.0));
    });

    test('highly repetitive data compresses well', () {
      final compressor = MessageCompressor();
      final data = Uint8List.fromList(List.filled(1000, 0));
      final compressed = compressor.compress(data);
      expect(compressed.length, lessThan(data.length));
    });
  });

  // -------------------------------------------------------------------------
  // CoverTrafficGenerator
  // -------------------------------------------------------------------------
  group('CoverTrafficGenerator', () {
    test('starts and stops', () {
      final gen = CoverTrafficGenerator();
      expect(gen.isRunning, false);
      gen.start();
      expect(gen.isRunning, true);
      gen.stop();
      expect(gen.isRunning, false);
      gen.dispose();
    });

    test('does not emit when stopped', () async {
      final gen = CoverTrafficGenerator();
      final packets = <Uint8List>[];
      gen.dummyPackets.listen(packets.add);

      await Future.delayed(const Duration(milliseconds: 50));
      expect(packets, isEmpty);
      gen.dispose();
    });
  });

  // -------------------------------------------------------------------------
  // ProtocolNegotiator
  // -------------------------------------------------------------------------
  group('ProtocolNegotiator', () {
    test('builds valid version message', () {
      final neg = ProtocolNegotiator();
      final msg = neg.buildVersionMessage();
      expect(msg.length, 8);
      // Magic check
      expect(msg[0], 0xBC);
      expect(msg[1], 0x01);
      // Version
      expect(msg[2], ProtocolNegotiator.currentVersion);
    });

    test('same version peers negotiate successfully', () {
      final a = ProtocolNegotiator();
      final b = ProtocolNegotiator();

      final msgA = a.buildVersionMessage();
      final msgB = b.buildVersionMessage();

      final resultA = a.negotiate(msgB);
      final resultB = b.negotiate(msgA);

      expect(resultA.compatible, true);
      expect(resultB.compatible, true);
      expect(resultA.version, ProtocolNegotiator.currentVersion);
      expect(resultA.features, isNotEmpty);
    });

    test('different version peers negotiate to lower version', () {
      final v1 = ProtocolNegotiator(localVersion: 1);
      final v2 = ProtocolNegotiator(localVersion: 2);

      final result = v2.negotiate(v1.buildVersionMessage());
      expect(result.compatible, true);
      expect(result.version, 1);
    });

    test('invalid magic rejected', () {
      final neg = ProtocolNegotiator();
      final bad = Uint8List.fromList([0xFF, 0xFF, 2, 1, 0, 0, 0, 0]);
      final result = neg.negotiate(bad);
      expect(result.compatible, false);
      expect(result.error, contains('Invalid magic'));
    });

    test('too-short message rejected', () {
      final neg = ProtocolNegotiator();
      final result = neg.negotiate(Uint8List(3));
      expect(result.compatible, false);
    });

    test('feature intersection works', () {
      final a = ProtocolNegotiator(
        supportedFeatures: {ProtocolFeature.compression, ProtocolFeature.nostr},
      );
      final b = ProtocolNegotiator(
        supportedFeatures: {ProtocolFeature.nostr, ProtocolFeature.meshRelay},
      );

      final result = a.negotiate(b.buildVersionMessage());
      expect(result.compatible, true);
      expect(result.hasFeature(ProtocolFeature.nostr), true);
      expect(result.hasFeature(ProtocolFeature.compression), false);
      expect(result.hasFeature(ProtocolFeature.meshRelay), false);
    });
  });

  // -------------------------------------------------------------------------
  // TorManager
  // -------------------------------------------------------------------------
  group('TorManager', () {
    test('initial status is disconnected', () {
      expect(TorManager.instance.status, TorStatus.disconnected);
    });

    test('shouldUseTor detects .onion URLs', () {
      expect(
        TorManager.instance.shouldUseTor('wss://relay.example.onion'),
        true,
      );
      expect(TorManager.instance.shouldUseTor('wss://relay.damus.io'), false);
    });
  });

  // -------------------------------------------------------------------------
  // NotificationService
  // -------------------------------------------------------------------------
  group('NotificationService', () {
    test('initializes without error', () async {
      await NotificationService.instance.initialize();
      expect(NotificationService.instance.isInitialized, true);
    });

    test('shows notification without crash', () async {
      await NotificationService.instance.initialize();
      await NotificationService.instance.showMessageNotification(
        senderNickname: 'alice',
        message: 'hello',
      );
      // No exception = pass
    });
  });
}
