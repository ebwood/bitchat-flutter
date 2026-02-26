import 'package:flutter_test/flutter_test.dart';

import 'package:bitchat/services/permission_service.dart';
import 'package:bitchat/services/unified_peer_service.dart';
import 'package:bitchat/l10n/l10n.dart';

void main() {
  // ---------------------------------------------------------------------------
  // PermissionService
  // ---------------------------------------------------------------------------
  group('PermissionService', () {
    test('initial status is notRequested', () {
      final svc = PermissionService();
      expect(
        svc.getStatus(AppPermission.bluetooth),
        PermissionStatus.notRequested,
      );
      expect(svc.allGranted, false);
    });

    test('set and check permission', () {
      final svc = PermissionService();
      svc.setStatus(AppPermission.bluetooth, PermissionStatus.granted);
      expect(svc.isGranted(AppPermission.bluetooth), true);
    });

    test('allGranted when all granted', () {
      final svc = PermissionService();
      svc.setStatus(AppPermission.bluetooth, PermissionStatus.granted);
      svc.setStatus(AppPermission.location, PermissionStatus.granted);
      svc.setStatus(AppPermission.microphone, PermissionStatus.granted);
      expect(svc.allGranted, true);
    });

    test('needsAttention on denied', () {
      final svc = PermissionService();
      svc.setStatus(AppPermission.bluetooth, PermissionStatus.denied);
      expect(svc.needsAttention, true);
    });

    test('pendingPermissions returns not-requested', () {
      final svc = PermissionService();
      svc.setStatus(AppPermission.bluetooth, PermissionStatus.granted);
      expect(svc.pendingPermissions.length, 2); // location + mic
    });

    test('explanations and icons exist', () {
      for (final p in AppPermission.values) {
        expect(PermissionService.explanation(p), isNotEmpty);
        expect(PermissionService.icon(p), isNotNull);
        expect(PermissionService.color(p), isNotNull);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // UnifiedPeerService
  // ---------------------------------------------------------------------------
  group('UnifiedPeerService', () {
    late UnifiedPeerService svc;

    setUp(() {
      svc = UnifiedPeerService();
    });

    test('upsert and retrieve peers', () {
      svc.upsertPeer(peerId: 'p1', nickname: 'Alice');
      svc.upsertPeer(peerId: 'p2', nickname: 'Bob');
      expect(svc.peerCount, 2);
      expect(svc.onlinePeerCount, 2);
    });

    test('update existing peer', () {
      svc.upsertPeer(
        peerId: 'p1',
        nickname: 'Alice',
        transport: PeerTransport.ble,
      );
      svc.upsertPeer(peerId: 'p1', transport: PeerTransport.nostr);
      final peer = svc.allPeers.firstWhere((p) => p.peerId == 'p1');
      expect(peer.transport, PeerTransport.both); // merged
    });

    test('mark offline', () {
      svc.upsertPeer(peerId: 'p1');
      svc.markOffline('p1');
      expect(svc.onlinePeerCount, 0);
      expect(svc.allPeers[0].quality, ConnectionQuality.disconnected);
    });

    test('filter by transport', () {
      svc.upsertPeer(peerId: 'p1', transport: PeerTransport.ble);
      svc.upsertPeer(peerId: 'p2', transport: PeerTransport.nostr);
      svc.upsertPeer(peerId: 'p3', transport: PeerTransport.both);
      expect(svc.blePeers.length, 2); // p1 + p3
      expect(svc.nostrPeers.length, 2); // p2 + p3
    });

    test('network mode controls activation', () {
      svc.setNetworkMode(NetworkMode.bleOnly);
      expect(svc.isBleActive, true);
      expect(svc.isNostrActive, false);

      svc.setNetworkMode(NetworkMode.nostrOnly);
      expect(svc.isBleActive, false);
      expect(svc.isNostrActive, true);

      svc.setNetworkMode(NetworkMode.auto);
      expect(svc.isBleActive, true);
      expect(svc.isNostrActive, true);
    });

    test('quality score values', () {
      final peer = UnifiedPeer(
        peerId: 'p1',
        quality: ConnectionQuality.excellent,
      );
      expect(peer.qualityScore, 1.0);
      peer.quality = ConnectionQuality.poor;
      expect(peer.qualityScore, 0.25);
    });
  });

  // ---------------------------------------------------------------------------
  // L10n
  // ---------------------------------------------------------------------------
  group('L10n', () {
    test('default locale is English', () {
      expect(L10n.currentLocale, AppLocale.en);
      expect(L10n.tr('welcome'), 'Welcome to BitChat');
    });

    test('switch to Chinese', () {
      L10n.setLocale(AppLocale.zh);
      expect(L10n.tr('welcome'), '欢迎使用 BitChat');
      expect(L10n.tr('settings'), '设置');
      L10n.setLocale(AppLocale.en); // reset
    });

    test('fallback to English for missing keys', () {
      L10n.setLocale(AppLocale.ja);
      // 'debug' not in Japanese table
      expect(L10n.tr('debug'), 'Debug Panel');
      L10n.setLocale(AppLocale.en);
    });

    test('unknown key returns key itself', () {
      expect(L10n.tr('nonexistent_key'), 'nonexistent_key');
    });

    test('all locales have display names', () {
      for (final locale in AppLocale.values) {
        expect(L10n.localeNames[locale], isNotNull);
      }
    });
  });
}
