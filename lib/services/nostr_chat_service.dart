import 'dart:async';
import 'dart:convert';

import 'package:bitchat/nostr/nostr_event.dart';
import 'package:bitchat/nostr/nostr_filter.dart';
import 'package:bitchat/nostr/nostr_relay_manager.dart';
import 'package:bitchat/nostr/relay_directory.dart';

/// Bridges the chat UI with Nostr relay communication.
///
/// Generates a secp256k1 identity on init, connects to public relays,
/// sends messages as Nostr kind-1 text notes with a `#bitchat` tag,
/// and subscribes to incoming messages.
class NostrChatService {
  /// [channelTag] is a geohash string (e.g. 'wtw3s') for geohash mode,
  /// or a named channel for legacy mode.
  /// [useGeohashMode] enables kind 20000 events matching original bitchat.
  NostrChatService({
    List<String>? relayUrls,
    String? channelTag,
    this.useGeohashMode = true,
  }) : _channelTag = channelTag ?? 'bitchat-general',
       _relayManager = NostrRelayManager(
         relayUrls:
             relayUrls ??
             [
               'wss://relay.damus.io',
               'wss://nos.lol',
               'wss://relay.primal.net',
             ],
       );

  /// Private constructor for fromLocation factory.
  NostrChatService._withManager({
    required NostrRelayManager relayManager,
    String? channelTag,
    this.useGeohashMode = true,
  }) : _channelTag = channelTag ?? 'bitchat-general',
       _relayManager = relayManager;

  /// Create a chat service using the closest relays to the user's location.
  ///
  /// Loads 305 relays from bundled CSV and selects the [relayCount]
  /// closest via haversine distance — matching original Android behavior.
  static Future<NostrChatService> fromLocation({
    required double latitude,
    required double longitude,
    int relayCount = 5,
    String? channelTag,
  }) async {
    final directory = RelayDirectory.instance;
    await directory.initialize();
    final urls = directory.closestRelays(
      latitude: latitude,
      longitude: longitude,
      count: relayCount,
    );
    return NostrChatService._withManager(
      relayManager: NostrRelayManager(relayUrls: urls),
      channelTag: channelTag,
    );
  }

  final NostrRelayManager _relayManager;
  String _channelTag;

  /// Whether to use geohash mode (kind 20000) matching original bitchat.
  /// When false, uses kind 1 + t-tag (legacy/Flutter-only mode).
  final bool useGeohashMode;

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
  ///
  /// In geohash mode: sends kind 20000 with ["g", geohash] + ["n", nick]
  /// and plain text content (matching original bitchat format).
  void sendMessage(String text, {String? senderNickname}) {
    if (!_initialized) return;
    final nick = senderNickname ?? _nickname ?? shortPubKey;
    _relayManager.sendEvent(_createEvent(text, nick));
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
      if (width != null) 'w': width,
      if (height != null) 'h': height,
    });
    _relayManager.sendEvent(_createEvent(content, nick));
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
      if (duration != null) 'dur': duration,
    });
    _relayManager.sendEvent(_createEvent(content, nick));
  }

  /// Create a Nostr event in the appropriate format.
  ///
  /// Geohash mode: kind 20000 + ["g", geohash] + ["n", nick] (original bitchat)
  /// Legacy mode: kind 1 + ["t", channelTag] (Flutter-only)
  NostrEvent _createEvent(String content, String nick) {
    if (useGeohashMode) {
      // Original bitchat format: kind 20000, geohash tag, nickname tag
      return NostrEvent.createGeohashEvent(
        content: content,
        geohash: _channelTag,
        publicKeyHex: _publicKeyHex,
        privateKeyHex: _privateKeyHex,
        nickname: nick,
      );
    } else {
      final wrappedContent = jsonEncode({
        'type': 'text',
        'text': content,
        'nick': nick,
      });
      return NostrEvent.createTextNote(
        content: wrappedContent,
        publicKeyHex: _publicKeyHex,
        privateKeyHex: _privateKeyHex,
        tags: [
          ['t', _channelTag],
          ['client', 'bitchat-flutter'],
        ],
      );
    }
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

    final NostrFilter filter;
    if (useGeohashMode) {
      // Original bitchat format: subscribe to kind 20000 + 20001 events
      // with #g tag matching the geohash
      filter = NostrFilter(
        kinds: [NostrKind.ephemeralEvent, NostrKind.geohashPresence],
        since: now - 3600,
        tagFilters: {
          'g': [channelTag],
        },
        limit: 1000,
      );
    } else {
      filter = NostrFilter(
        kinds: [NostrKind.textNote],
        since: now - 3600,
        tagFilters: {
          't': [channelTag],
        },
        limit: 50,
      );
    }

    _relayManager.subscribe(
      filter,
      _handleIncomingEvent,
      id: 'bitchat-channel',
    );
  }

  void _handleIncomingEvent(NostrEvent event) {
    // Skip own messages
    if (event.pubkey == _publicKeyHex) return;

    // Skip presence events (kind 20001) — they have no message content
    if (event.kind == NostrKind.geohashPresence) return;

    final ts = DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000);

    if (useGeohashMode) {
      // Original bitchat format: nickname in "n" tag, content is plain text
      final nick = _getTagValue(event.tags, 'n') ?? _shortKey(event.pubkey);

      // Try to parse as JSON (image/voice from Flutter clients)
      try {
        final data = jsonDecode(event.content) as Map<String, dynamic>;
        final msgType = data['type'] as String?;
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
          return;
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
          return;
        }
      } catch (_) {
        // Not JSON — plain text message from original bitchat
      }

      // Plain text message (original bitchat format)
      _messageController.add(
        ChatMessage(
          text: event.content,
          senderNickname: nick,
          senderPubKey: event.pubkey,
          timestamp: ts,
          channel: _channelTag,
          isOwnMessage: false,
        ),
      );
    } else {
      // Legacy mode: JSON content with type/nick fields
      try {
        final data = jsonDecode(event.content) as Map<String, dynamic>;
        final msgType = data['type'] as String? ?? 'text';
        final nick = data['nick'] as String? ?? _shortKey(event.pubkey);

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
          _messageController.add(
            ChatMessage(
              text: data['text'] as String? ?? event.content,
              senderNickname: nick,
              senderPubKey: event.pubkey,
              timestamp: ts,
              channel: _channelTag,
              isOwnMessage: false,
            ),
          );
        }
      } catch (_) {
        _messageController.add(
          ChatMessage(
            text: event.content,
            senderNickname: _shortKey(event.pubkey),
            senderPubKey: event.pubkey,
            timestamp: ts,
            channel: _channelTag,
            isOwnMessage: false,
          ),
        );
      }
    }
  }

  /// Extract the first value for a given tag name from event tags.
  String? _getTagValue(List<List<String>> tags, String tagName) {
    for (final tag in tags) {
      if (tag.length >= 2 && tag[0] == tagName) return tag[1];
    }
    return null;
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
