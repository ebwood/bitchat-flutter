import 'package:flutter_test/flutter_test.dart';

import 'package:bitchat/services/mesh_graph_service.dart';
import 'package:bitchat/services/gossip_sync.dart';

void main() {
  // ---------------------------------------------------------------------------
  // MeshGraphService
  // ---------------------------------------------------------------------------
  group('MeshGraphService', () {
    late MeshGraphService service;

    setUp(() {
      service = MeshGraphService.instance;
      service.reset();
    });

    test('starts with empty snapshot', () {
      final snap = service.snapshot;
      expect(snap.nodes, isEmpty);
      expect(snap.edges, isEmpty);
    });

    test('adds nodes from announcement', () {
      service.updateFromAnnouncement(
        'peer1',
        nickname: 'Alice',
        neighbors: ['peer2'],
        timestamp: 1,
      );
      final snap = service.snapshot;
      expect(snap.nodes.length, 2); // peer1 + peer2
      expect(snap.nodes.any((n) => n.peerID == 'peer1'), true);
      expect(snap.nodes.any((n) => n.peerID == 'peer2'), true);
    });

    test('creates unconfirmed edge from one-way announcement', () {
      service.updateFromAnnouncement(
        'peer1',
        neighbors: ['peer2'],
        timestamp: 1,
      );
      final snap = service.snapshot;
      expect(snap.edges.length, 1);
      expect(snap.edges[0].isConfirmed, false);
    });

    test('creates confirmed edge from two-way announcements', () {
      service.updateFromAnnouncement(
        'peer1',
        neighbors: ['peer2'],
        timestamp: 1,
      );
      service.updateFromAnnouncement(
        'peer2',
        neighbors: ['peer1'],
        timestamp: 1,
      );
      final snap = service.snapshot;
      expect(snap.edges.length, 1);
      expect(snap.edges[0].isConfirmed, true);
    });

    test('ignores older timestamps', () {
      service.updateFromAnnouncement(
        'peer1',
        neighbors: ['peer2'],
        timestamp: 5,
      );
      service.updateFromAnnouncement(
        'peer1',
        neighbors: ['peer3'],
        timestamp: 3,
      ); // older
      final snap = service.snapshot;
      // Should still have peer2, not peer3
      expect(snap.nodes.any((n) => n.peerID == 'peer2'), true);
    });

    test('removePeer works', () {
      service.updateFromAnnouncement('peer1', neighbors: [], timestamp: 1);
      service.removePeer('peer1');
      expect(service.snapshot.nodes, isEmpty);
    });

    test('displayLabel uses nickname or truncated ID', () {
      final withNick = GraphNode(peerID: 'abcdef1234567890', nickname: 'Bob');
      expect(withNick.displayLabel, 'Bob');

      final withoutNick = GraphNode(peerID: 'abcdef1234567890');
      expect(withoutNick.displayLabel, 'abcdef12');
    });
  });

  // ---------------------------------------------------------------------------
  // SyncTypeFlags
  // ---------------------------------------------------------------------------
  group('SyncTypeFlags', () {
    test('toByte and fromByte round-trip', () {
      const flags = SyncTypeFlags(
        messages: true,
        presence: false,
        files: true,
        channels: true,
      );
      final byte = flags.toByte();
      final restored = SyncTypeFlags.fromByte(byte);
      expect(restored.messages, true);
      expect(restored.presence, false);
      expect(restored.files, true);
      expect(restored.channels, true);
    });

    test('standard has files disabled', () {
      expect(SyncTypeFlags.standard.files, false);
      expect(SyncTypeFlags.standard.messages, true);
    });

    test('full has files enabled', () {
      expect(SyncTypeFlags.full.files, true);
    });

    test('toByte encodes correctly', () {
      const all = SyncTypeFlags(
        messages: true,
        presence: true,
        files: true,
        channels: true,
      );
      expect(all.toByte(), 0x0F);

      const none = SyncTypeFlags(
        messages: false,
        presence: false,
        files: false,
        channels: false,
      );
      expect(none.toByte(), 0);
    });
  });

  // ---------------------------------------------------------------------------
  // GossipSyncManager
  // ---------------------------------------------------------------------------
  group('GossipSyncManager', () {
    test('builds filter from known messages', () {
      final mgr = GossipSyncManager();
      mgr.addKnownMessages(['msg1', 'msg2', 'msg3']);
      final filter = mgr.buildFilter();
      expect(filter.count, 3);
      expect(filter.mightContain('msg1'), true);
      expect(filter.mightContain('msg2'), true);
    });

    test('creates sync request', () {
      final mgr = GossipSyncManager();
      mgr.addKnownMessage('msg1');
      final req = mgr.createSyncRequest('my_peer_id');
      expect(req.senderPeerId, 'my_peer_id');
      expect(req.filter.count, 1);
      expect(req.syncFlags.messages, true);
    });

    test('finds missing messages from sync request', () {
      final sender = GossipSyncManager();
      sender.addKnownMessages(['msg1', 'msg2']);

      final receiver = GossipSyncManager();
      receiver.addKnownMessages(['msg1', 'msg2', 'msg3', 'msg4']);

      final request = sender.createSyncRequest('sender');
      final missing = receiver.findMissingMessages(request);

      // msg3, msg4 are missing from sender
      expect(missing.contains('msg3'), true);
      expect(missing.contains('msg4'), true);
    });

    test('message request queue works', () {
      final mgr = GossipSyncManager();
      mgr.addMessageRequest(
        const MessageRequest(messageIds: ['a', 'b'], requesterPeerId: 'peer1'),
      );
      final drained = mgr.drainPendingRequests();
      expect(drained.length, 1);
      expect(mgr.drainPendingRequests(), isEmpty);
    });

    test('reset clears state', () {
      final mgr = GossipSyncManager();
      mgr.addKnownMessage('msg1');
      mgr.reset();
      expect(mgr.knownMessageCount, 0);
    });
  });
}
