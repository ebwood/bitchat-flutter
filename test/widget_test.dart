import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:bitchat/models/bitchat_packet.dart';
import 'package:bitchat/models/bitchat_message.dart';
import 'package:bitchat/models/peer_id.dart';
import 'package:bitchat/models/message_type.dart';
import 'package:bitchat/protocol/binary_protocol.dart';
import 'package:bitchat/protocol/message_padding.dart';
import 'package:bitchat/services/command_processor.dart';

void main() {
  group('PeerID', () {
    test('round-trip hex ↔ bytes', () {
      final id = PeerID('0a1b2c3d4e5f6789');
      final bytes = id.toBytes();
      expect(bytes.length, 8);
      final restored = PeerID.fromBytes(bytes);
      expect(restored.id, id.id);
    });

    test('broadcast address', () {
      final broadcast = PeerID.broadcast();
      expect(broadcast.isBroadcast, true);
      expect(broadcast.toBytes().every((b) => b == 0xFF), true);
    });

    test('short ID', () {
      final id = PeerID('abcdef0123456789');
      expect(id.shortId, 'abcdef01');
    });

    test('pads short data', () {
      final id = PeerID.fromBytes(Uint8List.fromList([0x01, 0x02]));
      expect(id.toBytes().length, 8);
      expect(id.toBytes()[0], 0x01);
      expect(id.toBytes()[1], 0x02);
      expect(id.toBytes()[2], 0x00);
    });
  });

  group('MessagePadding', () {
    test('pads to correct block sizes', () {
      expect(MessagePadding.optimalBlockSize(100), 256);
      expect(MessagePadding.optimalBlockSize(250), 256);
      expect(MessagePadding.optimalBlockSize(300), 512);
      expect(MessagePadding.optimalBlockSize(600), 1024);
      expect(MessagePadding.optimalBlockSize(1500), 2048);
    });

    test('round-trip pad/unpad small data', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final padded = MessagePadding.pad(data, 256);
      expect(padded.length, 256);
      final unpadded = MessagePadding.unpad(padded);
      expect(unpadded.length, 5);
      expect(unpadded, data);
    });

    test('round-trip pad/unpad large data', () {
      final data = Uint8List(500);
      for (var i = 0; i < 500; i++) {
        data[i] = i % 256;
      }
      final padded = MessagePadding.pad(data, 512);
      expect(padded.length, 512);
      final unpadded = MessagePadding.unpad(padded);
      expect(unpadded.length, 500);
      expect(unpadded, data);
    });
  });

  group('BinaryProtocol', () {
    test('encode/decode round-trip (v1, no optional fields)', () {
      final original = BitchatPacket(
        version: 1,
        type: MessageType.message.value,
        senderID: PeerID('abcdef0123456789').toBytes(),
        timestamp: 1700000000000,
        payload: Uint8List.fromList([0x48, 0x65, 0x6C, 0x6C, 0x6F]),
        ttl: 7,
      );

      final encoded = BinaryProtocol.encode(original);
      expect(encoded, isNotNull);

      final decoded = BinaryProtocol.decode(encoded!);
      expect(decoded, isNotNull);
      expect(decoded!.version, 1);
      expect(decoded.type, MessageType.message.value);
      expect(decoded.ttl, 7);
      expect(decoded.senderID, original.senderID);
      expect(decoded.recipientID, isNull);
      expect(decoded.signature, isNull);
      expect(decoded.payload, original.payload);
    });

    test('encode/decode with recipient and signature', () {
      final original = BitchatPacket(
        version: 1,
        type: MessageType.noiseEncrypted.value,
        senderID: PeerID('1111111111111111').toBytes(),
        recipientID: PeerID('2222222222222222').toBytes(),
        timestamp: 1700000000000,
        payload: Uint8List.fromList([0xDE, 0xAD]),
        signature: Uint8List(64)..fillRange(0, 64, 0xAB),
        ttl: 3,
      );

      final encoded = BinaryProtocol.encode(original);
      expect(encoded, isNotNull);

      final decoded = BinaryProtocol.decode(encoded!);
      expect(decoded, isNotNull);
      expect(decoded!.recipientID, isNotNull);
      expect(decoded.recipientID, original.recipientID);
      expect(decoded.signature, isNotNull);
      expect(decoded.signature!.length, 64);
    });

    test('decode without padding', () {
      final original = BitchatPacket(
        version: 1,
        type: MessageType.announce.value,
        senderID: Uint8List(8),
        timestamp: 1234567890000,
        payload: Uint8List.fromList([0x01]),
        ttl: 5,
      );

      final encoded = BinaryProtocol.encode(original, padding: false);
      expect(encoded, isNotNull);
      // Without padding, size = 14 header + 8 sender + 1 payload = 23
      expect(encoded!.length, 23);

      final decoded = BinaryProtocol.decode(encoded);
      expect(decoded, isNotNull);
      expect(decoded!.type, MessageType.announce.value);
    });
  });

  group('BitchatMessage', () {
    test('binary round-trip (simple public message)', () {
      final orig = BitchatMessage(
        sender: 'alice',
        content: 'Hello, world!',
        timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        isRelay: false,
      );

      final encoded = orig.toBinaryPayload();
      expect(encoded, isNotNull);

      final decoded = BitchatMessage.fromBinaryPayload(encoded!);
      expect(decoded, isNotNull);
      expect(decoded!.sender, 'alice');
      expect(decoded.content, 'Hello, world!');
      expect(decoded.isRelay, false);
      expect(decoded.isPrivate, false);
    });

    test('binary round-trip (private message with mentions)', () {
      final orig = BitchatMessage(
        sender: 'bob',
        content: 'Hey @alice, check this out',
        timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        isRelay: false,
        isPrivate: true,
        recipientNickname: 'alice',
        senderPeerID: PeerID('abcdef0123456789'),
        mentions: ['alice'],
      );

      final encoded = orig.toBinaryPayload();
      expect(encoded, isNotNull);

      final decoded = BitchatMessage.fromBinaryPayload(encoded!);
      expect(decoded, isNotNull);
      expect(decoded!.sender, 'bob');
      expect(decoded.isPrivate, true);
      expect(decoded.recipientNickname, 'alice');
      expect(decoded.senderPeerID?.id, 'abcdef0123456789');
      expect(decoded.mentions, ['alice']);
    });

    test('binary round-trip (relay message)', () {
      final orig = BitchatMessage(
        sender: 'charlie',
        content: 'Relayed message',
        timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        isRelay: true,
        originalSender: 'dave',
      );

      final encoded = orig.toBinaryPayload();
      final decoded = BitchatMessage.fromBinaryPayload(encoded!);
      expect(decoded!.isRelay, true);
      expect(decoded.originalSender, 'dave');
    });
  });

  group('CommandProcessor', () {
    test('parses /j channel', () {
      final result = CommandProcessor.parse('/j general');
      expect(result, isNotNull);
      expect(result!.type, CommandType.joinChannel);
      expect(result.channel, '#general');
    });

    test('parses /msg', () {
      final result = CommandProcessor.parse('/msg @alice hello there');
      expect(result, isNotNull);
      expect(result!.type, CommandType.privateMessage);
      expect(result.targetUser, 'alice');
      expect(result.message, 'hello there');
    });

    test('parses /who', () {
      final result = CommandProcessor.parse('/w');
      expect(result!.type, CommandType.who);
    });

    test('parses /nick', () {
      final result = CommandProcessor.parse('/nick satoshi');
      expect(result!.type, CommandType.nick);
      expect(result.message, 'satoshi');
    });

    test('returns null for non-commands', () {
      expect(CommandProcessor.parse('hello world'), isNull);
    });

    test('handles unknown commands', () {
      final result = CommandProcessor.parse('/xyz');
      expect(result!.type, CommandType.unknown);
    });
  });
}
