import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:bitchat/services/nostr_chat_service.dart';
import 'package:bitchat/services/voice_note_service.dart';

void main() {
  // ---------------------------------------------------------------------------
  // VoiceNoteService — encoding
  // ---------------------------------------------------------------------------
  group('VoiceNoteService', () {
    test('decodeBase64Audio decodes valid base64', () {
      final original = Uint8List.fromList([0x00, 0x01, 0x02, 0x03]);
      final encoded = base64Encode(original);
      final decoded = VoiceNoteService.decodeBase64Audio(encoded);
      expect(decoded, original);
    });

    test('decodeBase64Audio returns null for invalid base64', () {
      final result = VoiceNoteService.decodeBase64Audio('not-valid!!!');
      expect(result, isNull);
    });

    test('maxDuration is 120 seconds', () {
      expect(VoiceNoteService.maxDuration, const Duration(seconds: 120));
    });
  });

  // ---------------------------------------------------------------------------
  // VoiceNotePayload
  // ---------------------------------------------------------------------------
  group('VoiceNotePayload', () {
    test('stores all fields', () {
      final payload = VoiceNotePayload(
        base64Data: 'AAEC',
        durationSeconds: 5.3,
        sizeBytes: 3000,
        filePath: '/tmp/voice.m4a',
      );
      expect(payload.base64Data, 'AAEC');
      expect(payload.durationSeconds, 5.3);
      expect(payload.sizeBytes, 3000);
      expect(payload.filePath, '/tmp/voice.m4a');
    });
  });

  // ---------------------------------------------------------------------------
  // ChatMessage — voice support
  // ---------------------------------------------------------------------------
  group('ChatMessage voice support', () {
    test('voice message fields', () {
      final msg = ChatMessage(
        text: '[Voice Note]',
        senderNickname: 'alice',
        senderPubKey: 'abc123',
        timestamp: DateTime.now(),
        channel: 'general',
        isOwnMessage: true,
        messageType: MessageType.voice,
        voiceBase64: 'base64audio',
        voiceDuration: 5.5,
      );
      expect(msg.messageType, MessageType.voice);
      expect(msg.isVoice, true);
      expect(msg.isImage, false);
      expect(msg.voiceBase64, 'base64audio');
      expect(msg.voiceDuration, 5.5);
    });

    test('voice message without base64 is not voice', () {
      final msg = ChatMessage(
        text: '[Voice Note]',
        senderNickname: 'bob',
        senderPubKey: 'def456',
        timestamp: DateTime.now(),
        channel: 'general',
        isOwnMessage: false,
        messageType: MessageType.voice,
        // voiceBase64 is null
      );
      expect(msg.isVoice, false);
    });

    test('text message is not voice', () {
      final msg = ChatMessage(
        text: 'hello',
        senderNickname: 'carol',
        senderPubKey: 'ghi789',
        timestamp: DateTime.now(),
        channel: 'general',
        isOwnMessage: false,
      );
      expect(msg.isVoice, false);
      expect(msg.isImage, false);
    });
  });

  // ---------------------------------------------------------------------------
  // MessageType enum
  // ---------------------------------------------------------------------------
  group('MessageType voice', () {
    test('includes voice value', () {
      expect(MessageType.values, contains(MessageType.voice));
      expect(MessageType.values.length, 4); // text, image, voice, system
    });
  });
}
