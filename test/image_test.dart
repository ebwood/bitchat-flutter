import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:bitchat/services/image_message_service.dart';
import 'package:bitchat/services/nostr_chat_service.dart';

void main() {
  // ---------------------------------------------------------------------------
  // ImageMessageService — compression & encoding
  // ---------------------------------------------------------------------------
  group('ImageMessageService', () {
    late ImageMessageService service;

    setUp(() {
      service = ImageMessageService();
    });

    test('processImageBytes handles valid image', () {
      // Use the `image` package to create a proper 4x4 red PNG
      final image = img.Image(width: 4, height: 4);
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 4; x++) {
          image.setPixelRgba(x, y, 255, 0, 0, 255);
        }
      }
      final pngBytes = Uint8List.fromList(img.encodePng(image));

      final result = service.processImageBytes(pngBytes);
      expect(result, isNotNull);
      expect(result!.length, greaterThan(0));
      // Should be JPEG output (starts with 0xFF 0xD8)
      expect(result[0], 0xFF);
      expect(result[1], 0xD8);
    });

    test('processImageBytes returns null for invalid data', () {
      final garbage = Uint8List.fromList([1, 2, 3, 4, 5]);
      final result = service.processImageBytes(garbage);
      expect(result, isNull);
    });

    test('decodeBase64Image decodes valid base64', () {
      final original = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);
      final encoded = base64Encode(original);
      final decoded = ImageMessageService.decodeBase64Image(encoded);
      expect(decoded, original);
    });

    test('decodeBase64Image returns null for invalid base64', () {
      final result = ImageMessageService.decodeBase64Image('not-valid!!!');
      expect(result, isNull);
    });

    test('target constants match iOS values', () {
      expect(ImageMessageService.maxDimension, 448);
      expect(ImageMessageService.targetBytes, 45000);
      expect(ImageMessageService.initialQuality, 82);
    });
  });

  // ---------------------------------------------------------------------------
  // ChatMessage — image support
  // ---------------------------------------------------------------------------
  group('ChatMessage image support', () {
    test('text message defaults', () {
      final msg = ChatMessage(
        text: 'hello',
        senderNickname: 'alice',
        senderPubKey: 'abc123',
        timestamp: DateTime.now(),
        channel: 'general',
        isOwnMessage: false,
      );
      expect(msg.messageType, MessageType.text);
      expect(msg.isImage, false);
      expect(msg.imageBase64, isNull);
    });

    test('image message fields', () {
      final msg = ChatMessage(
        text: '[Image]',
        senderNickname: 'bob',
        senderPubKey: 'def456',
        timestamp: DateTime.now(),
        channel: 'general',
        isOwnMessage: true,
        messageType: MessageType.image,
        imageBase64: 'base64data',
        imageWidth: 200,
        imageHeight: 150,
      );
      expect(msg.messageType, MessageType.image);
      expect(msg.isImage, true);
      expect(msg.imageBase64, 'base64data');
      expect(msg.imageWidth, 200);
      expect(msg.imageHeight, 150);
    });

    test('image message without base64 is not image', () {
      final msg = ChatMessage(
        text: '[Image]',
        senderNickname: 'bob',
        senderPubKey: 'def456',
        timestamp: DateTime.now(),
        channel: 'general',
        isOwnMessage: false,
        messageType: MessageType.image,
        // imageBase64 is null
      );
      expect(msg.isImage, false); // no actual data
    });
  });

  // ---------------------------------------------------------------------------
  // MessageType enum
  // ---------------------------------------------------------------------------
  group('MessageType', () {
    test('has correct values', () {
      expect(MessageType.values.length, 4);
      expect(MessageType.values, contains(MessageType.text));
      expect(MessageType.values, contains(MessageType.image));
      expect(MessageType.values, contains(MessageType.system));
    });
  });

  // ---------------------------------------------------------------------------
  // ImagePayload
  // ---------------------------------------------------------------------------
  group('ImagePayload', () {
    test('stores all fields', () {
      final payload = ImagePayload(
        base64Data: 'abc123',
        width: 100,
        height: 200,
        sizeBytes: 5000,
      );
      expect(payload.base64Data, 'abc123');
      expect(payload.width, 100);
      expect(payload.height, 200);
      expect(payload.sizeBytes, 5000);
    });
  });
}
