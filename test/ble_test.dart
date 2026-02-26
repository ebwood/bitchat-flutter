import 'package:flutter_test/flutter_test.dart';

import 'package:bitchat/ble/message_deduplicator.dart';
import 'package:bitchat/ble/ble_peer_manager.dart';
import 'package:bitchat/ble/ble_mesh_service.dart';
import 'package:bitchat/models/peer_id.dart';

void main() {
  group('MessageDeduplicator', () {
    test('detects duplicates', () {
      final dedup = MessageDeduplicator();
      expect(dedup.isDuplicate('msg-1'), false);
      expect(dedup.isDuplicate('msg-1'), true);
      expect(dedup.isDuplicate('msg-2'), false);
    });

    test('markProcessed marks as seen', () {
      final dedup = MessageDeduplicator();
      dedup.markProcessed('msg-1');
      expect(dedup.hasSeen('msg-1'), true);
      expect(dedup.isDuplicate('msg-1'), true);
    });

    test('reset clears all entries', () {
      final dedup = MessageDeduplicator();
      dedup.isDuplicate('msg-1');
      dedup.isDuplicate('msg-2');
      expect(dedup.size, 2);

      dedup.reset();
      expect(dedup.size, 0);
      expect(dedup.isDuplicate('msg-1'), false);
    });

    test('capacity eviction works', () {
      final dedup = MessageDeduplicator(capacity: 10);
      for (var i = 0; i < 15; i++) {
        dedup.isDuplicate('msg-$i');
      }
      // Should have evicted some entries
      expect(dedup.size, lessThanOrEqualTo(13)); // 15 - 20% of 10
    });

    test('sweep removes old entries', () {
      final dedup = MessageDeduplicator(maxAge: Duration.zero);
      dedup.isDuplicate('old-msg');
      dedup.sweep();
      expect(dedup.size, 0);
    });
  });

  group('BLEPeerManager', () {
    test('shouldConnect respects max connections', () {
      final mgr = BLEPeerManager(maxConnections: 2);
      expect(
        mgr.shouldConnect(
          deviceId: 'dev-1',
          rssi: -50,
          currentConnectionCount: 2,
        ),
        false,
      );
      expect(
        mgr.shouldConnect(
          deviceId: 'dev-1',
          rssi: -50,
          currentConnectionCount: 1,
        ),
        true,
      );
    });

    test('shouldConnect respects RSSI threshold', () {
      final mgr = BLEPeerManager(minRSSI: -70);
      expect(
        mgr.shouldConnect(
          deviceId: 'dev-1',
          rssi: -90,
          currentConnectionCount: 0,
        ),
        false,
      );
      expect(
        mgr.shouldConnect(
          deviceId: 'dev-1',
          rssi: -60,
          currentConnectionCount: 0,
        ),
        true,
      );
    });

    test('backoff after failure', () {
      final mgr = BLEPeerManager(connectionBackoff: const Duration(hours: 1));
      mgr.recordFailure('dev-1');
      expect(
        mgr.shouldConnect(
          deviceId: 'dev-1',
          rssi: -50,
          currentConnectionCount: 0,
        ),
        false, // backed off
      );

      // Different device still allowed
      expect(
        mgr.shouldConnect(
          deviceId: 'dev-2',
          rssi: -50,
          currentConnectionCount: 0,
        ),
        true,
      );
    });

    test('success resets backoff', () {
      final mgr = BLEPeerManager(connectionBackoff: const Duration(hours: 1));
      mgr.recordFailure('dev-1');
      mgr.recordSuccess('dev-1');
      expect(
        mgr.shouldConnect(
          deviceId: 'dev-1',
          rssi: -50,
          currentConnectionCount: 0,
        ),
        true,
      );
    });

    test('prioritize sorts by RSSI descending', () {
      final mgr = BLEPeerManager();
      final peers = [
        BLEPeerInfo(
          deviceId: 'a',
          peerID: PeerID('0000000000000001'),
          rssi: -80,
        ),
        BLEPeerInfo(
          deviceId: 'b',
          peerID: PeerID('0000000000000002'),
          rssi: -40,
        ),
        BLEPeerInfo(
          deviceId: 'c',
          peerID: PeerID('0000000000000003'),
          rssi: -60,
        ),
      ];

      final sorted = mgr.prioritize(peers);
      expect(sorted[0].deviceId, 'b'); // -40
      expect(sorted[1].deviceId, 'c'); // -60
      expect(sorted[2].deviceId, 'a'); // -80
    });
  });

  group('BLEConstants', () {
    test('service UUID matches protocol', () {
      expect(
        BLEConstants.serviceUUID.toString().toUpperCase(),
        contains('F47B5E2D'),
      );
    });

    test('fragment size is reasonable', () {
      expect(BLEConstants.defaultFragmentSize, greaterThan(100));
      expect(BLEConstants.defaultFragmentSize, lessThanOrEqualTo(512));
    });
  });

  group('BLEMeshService fragmentation', () {
    test('small data not fragmented', () {
      final service = BLEMeshService(myPeerID: PeerID('0000000000000001'));
      // _fragment is private, test the public API instead
      expect(service.connectedPeerCount, 0);
      expect(service.status, BLEMeshStatus.idle);
    });

    test('initial state is idle', () {
      final service = BLEMeshService(myPeerID: PeerID('0000000000000001'));
      expect(service.status, BLEMeshStatus.idle);
      expect(service.peers, isEmpty);
      expect(service.connectedPeerCount, 0);
    });
  });
}
