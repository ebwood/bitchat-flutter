import 'dart:async';
import 'dart:convert';

import 'package:bitchat/nostr/nostr_event.dart';
import 'package:bitchat/nostr/nostr_filter.dart';
import 'package:bitchat/nostr/nostr_relay_manager.dart';

/// Bridges the chat UI with Nostr relay communication.
///
/// Generates a secp256k1 identity on init, connects to public relays,
/// sends messages as Nostr kind-1 text notes with a `#bitchat` tag,
/// and subscribes to incoming messages.
class NostrChatService {
  NostrChatService({List<String>? relayUrls, String? channelTag})
    : _channelTag = channelTag ?? 'bitchat-general',
      _relayManager = NostrRelayManager(
        relayUrls:
            relayUrls ??
            ['wss://relay.damus.io', 'wss://nos.lol', 'wss://relay.primal.net'],
      );

  final NostrRelayManager _relayManager;
  String _channelTag;

  // Identity
  late String _privateKeyHex;
  late String _publicKeyHex;
  String? _nickname;

  bool _initialized = false;
  bool get isInitialized => _initialized;
  String get publicKeyHex => _publicKeyHex;
  String get privateKeyHex => _privateKeyHex;
  NostrRelayManager get relayManager => _relayManager;
  String get shortPubKey => _publicKeyHex.length >= 12
      ? '${_publicKeyHex.substring(0, 6)}...${_publicKeyHex.substring(_publicKeyHex.length - 6)}'
      : _publicKeyHex;

  String get channel => _channelTag;

  // Incoming message stream
  final _messageController = StreamController<ChatMessage>.broadcast();
  Stream<ChatMessage> get messages => _messageController.stream;

  // Connection status
  final _statusController = StreamController<NostrConnectionStatus>.broadcast();
  Stream<NostrConnectionStatus> get statusStream => _statusController.stream;
  NostrConnectionStatus _status = NostrConnectionStatus.disconnected;
  NostrConnectionStatus get status => _status;

  /// Initialize — generate identity and connect to relays.
  Future<void> initialize({String? nickname}) async {
    if (_initialized) return;

    _nickname = nickname;

    // Generate secp256k1 key pair for Nostr
    final keys = NostrCrypto.generateKeyPair();
    _privateKeyHex = keys.$1;
    _publicKeyHex = keys.$2;

    _initialized = true;
    _updateStatus(NostrConnectionStatus.connecting);

    // Connect to relays
    await _relayManager.connect();
    _updateStatus(NostrConnectionStatus.connected);

    // Subscribe to bitchat channel messages
    _subscribeToChannel(_channelTag);
  }

  /// Send a text chat message to the current channel.
  void sendMessage(String text, {String? senderNickname}) {
    if (!_initialized) return;

    final nick = senderNickname ?? _nickname ?? shortPubKey;

    // Build content as JSON with nickname metadata
    final content = jsonEncode({'type': 'text', 'text': text, 'nick': nick});

    final event = NostrEvent.createTextNote(
      content: content,
      publicKeyHex: _publicKeyHex,
      privateKeyHex: _privateKeyHex,
      tags: [
        ['t', _channelTag], // channel tag
        ['client', 'bitchat-flutter'],
      ],
    );

    _relayManager.sendEvent(event);
  }

  /// Send an image message (base64-encoded JPEG) to the current channel.
  void sendImageMessage(
    String base64Data, {
    String? senderNickname,
    int? width,
    int? height,
  }) {
    if (!_initialized) return;

    final nick = senderNickname ?? _nickname ?? shortPubKey;

    final content = jsonEncode({
      'type': 'image',
      'data': base64Data,
      'nick': nick,
      if (width != null) 'w': width,
      if (height != null) 'h': height,
    });

    final event = NostrEvent.createTextNote(
      content: content,
      publicKeyHex: _publicKeyHex,
      privateKeyHex: _privateKeyHex,
      tags: [
        ['t', _channelTag],
        ['client', 'bitchat-flutter'],
      ],
    );

    _relayManager.sendEvent(event);
  }

  /// Send a voice note (base64-encoded M4A) to the current channel.
  void sendVoiceMessage(
    String base64Data, {
    String? senderNickname,
    double? duration,
  }) {
    if (!_initialized) return;

    final nick = senderNickname ?? _nickname ?? shortPubKey;

    final content = jsonEncode({
      'type': 'voice',
      'data': base64Data,
      'nick': nick,
      if (duration != null) 'dur': duration,
    });

    final event = NostrEvent.createTextNote(
      content: content,
      publicKeyHex: _publicKeyHex,
      privateKeyHex: _privateKeyHex,
      tags: [
        ['t', _channelTag],
        ['client', 'bitchat-flutter'],
      ],
    );

    _relayManager.sendEvent(event);
  }

  /// Switch to a different channel.
  void switchChannel(String channelTag) {
    _channelTag = channelTag;
    // Re-subscribe
    _relayManager.unsubscribe('bitchat-channel');
    _subscribeToChannel(channelTag);
  }

  void _subscribeToChannel(String channelTag) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final filter = NostrFilter(
      kinds: [NostrKind.textNote],
      since: now - 3600, // last hour
      tagFilters: {
        't': [channelTag],
      },
      limit: 50,
    );

    _relayManager.subscribe(
      filter,
      _handleIncomingEvent,
      id: 'bitchat-channel',
    );
  }

  void _handleIncomingEvent(NostrEvent event) {
    // Skip own messages
    if (event.pubkey == _publicKeyHex) return;

    try {
      final data = jsonDecode(event.content) as Map<String, dynamic>;
      final msgType = data['type'] as String? ?? 'text';
      final nick = data['nick'] as String? ?? _shortKey(event.pubkey);
      final ts = DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000);

      if (msgType == 'image') {
        _messageController.add(
          ChatMessage(
            text: '[Image]',
            senderNickname: nick,
            senderPubKey: event.pubkey,
            timestamp: ts,
            channel: _channelTag,
            isOwnMessage: false,
            messageType: MessageType.image,
            imageBase64: data['data'] as String?,
            imageWidth: data['w'] as int?,
            imageHeight: data['h'] as int?,
          ),
        );
      } else if (msgType == 'voice') {
        _messageController.add(
          ChatMessage(
            text: '[Voice Note]',
            senderNickname: nick,
            senderPubKey: event.pubkey,
            timestamp: ts,
            channel: _channelTag,
            isOwnMessage: false,
            messageType: MessageType.voice,
            voiceBase64: data['data'] as String?,
            voiceDuration: (data['dur'] as num?)?.toDouble(),
          ),
        );
      } else {
        final text = data['text'] as String? ?? event.content;
        _messageController.add(
          ChatMessage(
            text: text,
            senderNickname: nick,
            senderPubKey: event.pubkey,
            timestamp: ts,
            channel: _channelTag,
            isOwnMessage: false,
          ),
        );
      }
    } catch (_) {
      // Plain text content (from non-bitchat clients)
      _messageController.add(
        ChatMessage(
          text: event.content,
          senderNickname: _shortKey(event.pubkey),
          senderPubKey: event.pubkey,
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            event.createdAt * 1000,
          ),
          channel: _channelTag,
          isOwnMessage: false,
        ),
      );
    }
  }

  String _shortKey(String pubkey) {
    if (pubkey.length >= 12) {
      return '${pubkey.substring(0, 6)}..${pubkey.substring(pubkey.length - 4)}';
    }
    return pubkey;
  }

  void _updateStatus(NostrConnectionStatus s) {
    _status = s;
    _statusController.add(s);
  }

  /// Set nickname.
  void setNickname(String nick) {
    _nickname = nick;
  }

  /// Disconnect and clean up.
  void dispose() {
    _relayManager.dispose();
    _messageController.close();
    _statusController.close();
  }
}

/// Message type enum.
enum MessageType { text, image, voice, system }

/// A received or sent chat message.
class ChatMessage {
  const ChatMessage({
    required this.text,
    required this.senderNickname,
    required this.senderPubKey,
    required this.timestamp,
    required this.channel,
    required this.isOwnMessage,
    this.messageType = MessageType.text,
    this.imageBase64,
    this.imageWidth,
    this.imageHeight,
    this.voiceBase64,
    this.voiceDuration,
  });

  final String text;
  final String senderNickname;
  final String senderPubKey;
  final DateTime timestamp;
  final String channel;
  final bool isOwnMessage;
  final MessageType messageType;
  final String? imageBase64;
  final int? imageWidth;
  final int? imageHeight;
  final String? voiceBase64;
  final double? voiceDuration;

  bool get isImage => messageType == MessageType.image && imageBase64 != null;
  bool get isVoice => messageType == MessageType.voice && voiceBase64 != null;
}

/// Service connection status.
enum NostrConnectionStatus { disconnected, connecting, connected }
