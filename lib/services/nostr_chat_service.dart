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
            ['wss://relay.damus.io', 'wss://nos.lol', 'wss://relay.nostr.band'],
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

  /// Send a chat message to the current channel.
  void sendMessage(String text, {String? senderNickname}) {
    if (!_initialized) return;

    final nick = senderNickname ?? _nickname ?? shortPubKey;

    // Build content as JSON with nickname metadata
    final content = jsonEncode({'text': text, 'nick': nick});

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
      final text = data['text'] as String? ?? event.content;
      final nick = data['nick'] as String? ?? _shortKey(event.pubkey);

      _messageController.add(
        ChatMessage(
          text: text,
          senderNickname: nick,
          senderPubKey: event.pubkey,
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            event.createdAt * 1000,
          ),
          channel: _channelTag,
          isOwnMessage: false,
        ),
      );
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

/// A received or sent chat message.
class ChatMessage {
  const ChatMessage({
    required this.text,
    required this.senderNickname,
    required this.senderPubKey,
    required this.timestamp,
    required this.channel,
    required this.isOwnMessage,
  });

  final String text;
  final String senderNickname;
  final String senderPubKey;
  final DateTime timestamp;
  final String channel;
  final bool isOwnMessage;
}

/// Service connection status.
enum NostrConnectionStatus { disconnected, connecting, connected }
