import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:bitchat/ble/ble_native_channel.dart';
import 'package:bitchat/models/bitchat_message.dart';
import 'package:bitchat/models/bitchat_packet.dart';
import 'package:bitchat/models/message_type.dart' as proto;
import 'package:bitchat/models/peer_id.dart';
import 'package:bitchat/services/mesh_chat_service.dart';

void main() {
  setUpAll(() {
    // Disable native macOS BLE channel in test environment
    BLENativeChannel.overrideSupported = false;
  });
  group('MeshChatService', () {
    test('initial state is disconnected', () {
      final svc = MeshChatService(nickname: 'alice');
      expect(svc.status, MeshConnectionStatus.disconnected);
      expect(svc.connectedPeerCount, 0);
      expect(svc.peers, isEmpty);
    });

    test('setNickname updates nickname', () {
      final svc = MeshChatService(nickname: 'alice');
      svc.setNickname('bob');
      // Nickname updated — reflected in bleService
      expect(svc.bleService.nickname, 'bob');
    });

    test('dispose closes streams without error', () {
      final svc = MeshChatService(nickname: 'alice');
      svc.dispose();
      // After dispose, the stream controller is closed — verify no error
      expect(svc.status, MeshConnectionStatus.disconnected);
    });

    test('stop resets status to disconnected', () async {
      final svc = MeshChatService(nickname: 'alice');
      await svc.stop();
      expect(svc.status, MeshConnectionStatus.disconnected);
    });
  });

  group('PeerID.generate', () {
    test('generates a 16-character hex id', () {
      final id = PeerID.generate();
      expect(id.id.length, 16);
      // Valid hex characters only
      expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(id.id), isTrue);
    });

    test('generates unique IDs', () {
      final ids = List.generate(100, (_) => PeerID.generate().id);
      expect(ids.toSet().length, ids.length);
    });
  });

  group('BitchatMessage binary round-trip', () {
    test('encode and decode preserves message', () {
      final msg = BitchatMessage(
        sender: 'alice',
        content: 'Hello, mesh world!',
        timestamp: DateTime(2024, 1, 1, 12, 0, 0),
        isRelay: false,
      );

      final payload = msg.toBinaryPayload();
      expect(payload, isNotNull);

      final decoded = BitchatMessage.fromBinaryPayload(payload!);
      expect(decoded, isNotNull);
      expect(decoded!.sender, 'alice');
      expect(decoded.content, 'Hello, mesh world!');
      expect(decoded.isRelay, false);
    });

    test('relay and private flags round-trip', () {
      final msg = BitchatMessage(
        sender: 'bob',
        content: 'Secret message',
        timestamp: DateTime(2024, 6, 15),
        isRelay: true,
        isPrivate: true,
        recipientNickname: 'alice',
      );

      final payload = msg.toBinaryPayload();
      final decoded = BitchatMessage.fromBinaryPayload(payload!);

      expect(decoded!.isRelay, true);
      expect(decoded.isPrivate, true);
      expect(decoded.recipientNickname, 'alice');
    });
  });

  group('MeshConnectionStatus', () {
    test('enum values exist', () {
      expect(MeshConnectionStatus.values, hasLength(3));
      expect(MeshConnectionStatus.disconnected, isNotNull);
      expect(MeshConnectionStatus.scanning, isNotNull);
      expect(MeshConnectionStatus.connected, isNotNull);
    });
  });

  group('BitchatPacket.create', () {
    test('creates packet with correct fields', () {
      final peerId = PeerID.generate();
      final payload = Uint8List.fromList([1, 2, 3, 4]);

      final packet = BitchatPacket.create(
        type: proto.MessageType.message.value,
        ttl: 3,
        senderPeerID: peerId,
        payload: payload,
      );

      expect(packet.type, proto.MessageType.message.value);
      expect(packet.ttl, 3);
      expect(packet.senderID, peerId.toBytes());
      expect(packet.payload, payload);
      expect(packet.version, 1);
    });
  });
}
