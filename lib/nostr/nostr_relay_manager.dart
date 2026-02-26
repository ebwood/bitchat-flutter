import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'nostr_event.dart';
import 'nostr_filter.dart';
import 'relay_directory.dart' as dir;

/// Connection state for a relay.
enum RelayStatus { disconnected, connecting, connected, error }

/// Information about a relay connection.
class RelayInfo {
  RelayInfo({
    required this.url,
    this.status = RelayStatus.disconnected,
    this.lastError,
    this.retryCount = 0,
  });

  final String url;
  RelayStatus status;
  String? lastError;
  int retryCount;
  WebSocketChannel? channel;
  StreamSubscription? subscription;
}

/// Active subscription tracking.
class _SubscriptionInfo {
  _SubscriptionInfo({
    required this.id,
    required this.filter,
    required this.handler,
    this.targetRelayUrls,
  });

  final String id;
  final NostrFilter filter;
  final void Function(NostrEvent) handler;
  final List<String>? targetRelayUrls;
}

/// Manages WebSocket connections to Nostr relays.
///
/// Handles connection lifecycle, reconnection with exponential backoff,
/// subscription management, and event deduplication.
class NostrRelayManager {
  NostrRelayManager({List<String>? relayUrls}) {
    for (final url in relayUrls ?? defaultRelays) {
      _relays[url] = RelayInfo(url: url);
    }
  }

  /// Create a relay manager using the closest relays to a location.
  ///
  /// Loads all 305 relays from the bundled CSV and selects the [count]
  /// closest relays via haversine distance. This matches the original
  /// Android RelayDirectory behavior for geolocation-based relay selection.
  static Future<NostrRelayManager> fromLocation({
    required double latitude,
    required double longitude,
    int count = 5,
  }) async {
    final directory = dir.RelayDirectory.instance;
    await directory.initialize();
    final urls = directory.closestRelays(
      latitude: latitude,
      longitude: longitude,
      count: count,
    );
    return NostrRelayManager(relayUrls: urls);
  }

  /// Default relay list — matching iOS/Android defaults.
  static const defaultRelays = [
    'wss://relay.damus.io',
    'wss://nos.lol',
    'wss://relay.primal.net',
    'wss://offchain.pub',
    'wss://nostr21.com',
  ];

  final Map<String, RelayInfo> _relays = {};
  final Map<String, _SubscriptionInfo> _subscriptions = {};
  final Set<String> _seenEventIds = {};
  final _eventController = StreamController<NostrEvent>.broadcast();

  /// Relay URL → geohash set for routing.
  final Map<String, Set<String>> _geohashRelayMap = {};

  /// Stream of all deduplicated incoming events.
  Stream<NostrEvent> get events => _eventController.stream;

  /// Current relay statuses.
  Map<String, RelayStatus> get relayStatuses =>
      _relays.map((k, v) => MapEntry(k, v.status));

  /// All configured relay URLs.
  List<String> get relayUrls => _relays.keys.toList();

  /// Number of connected relays.
  int get connectedCount =>
      _relays.values.where((r) => r.status == RelayStatus.connected).length;

  /// Number of active subscriptions.
  int get activeSubscriptionCount => _subscriptions.length;

  // ---------------------------------------------------------------------------
  // Connection management
  // ---------------------------------------------------------------------------

  /// Connect to all configured relays.
  Future<void> connect() async {
    for (final relay in _relays.values) {
      _connectRelay(relay);
    }
  }

  /// Disconnect from all relays.
  void disconnect() {
    for (final relay in _relays.values) {
      _disconnectRelay(relay);
    }
  }

  /// Add and connect to a new relay URL.
  void addRelay(String url) {
    if (_relays.containsKey(url)) return;
    final relay = RelayInfo(url: url);
    _relays[url] = relay;
    _connectRelay(relay);
  }

  /// Remove and disconnect from a relay.
  void removeRelay(String url) {
    final relay = _relays.remove(url);
    if (relay != null) _disconnectRelay(relay);
  }

  Future<void> _connectRelay(RelayInfo relay) async {
    if (relay.status == RelayStatus.connected ||
        relay.status == RelayStatus.connecting) {
      return;
    }

    relay.status = RelayStatus.connecting;

    try {
      relay.channel = WebSocketChannel.connect(Uri.parse(relay.url));
      await relay.channel!.ready;
      relay.status = RelayStatus.connected;
      relay.retryCount = 0;

      relay.subscription = relay.channel!.stream.listen(
        (data) => _handleMessage(relay, data.toString()),
        onError: (error) {
          relay.status = RelayStatus.error;
          relay.lastError = error.toString();
          _scheduleReconnect(relay);
        },
        onDone: () {
          relay.status = RelayStatus.disconnected;
          _scheduleReconnect(relay);
        },
      );

      // Re-establish existing subscriptions on this relay
      for (final sub in _subscriptions.values) {
        _sendSubscription(relay, sub);
      }
    } catch (e) {
      relay.status = RelayStatus.error;
      relay.lastError = e.toString();
      _scheduleReconnect(relay);
    }
  }

  void _disconnectRelay(RelayInfo relay) {
    relay.subscription?.cancel();
    relay.channel?.sink.close();
    relay.status = RelayStatus.disconnected;
    relay.retryCount = 0;
  }

  void _scheduleReconnect(RelayInfo relay) {
    if (!_relays.containsKey(relay.url)) return;

    relay.retryCount++;
    final delay = min(30, pow(2, relay.retryCount).toInt());

    Future.delayed(Duration(seconds: delay), () {
      if (_relays.containsKey(relay.url) &&
          relay.status != RelayStatus.connected) {
        _connectRelay(relay);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Message handling
  // ---------------------------------------------------------------------------

  void _handleMessage(RelayInfo relay, String raw) {
    try {
      final msg = jsonDecode(raw) as List;
      if (msg.isEmpty) return;

      final type = msg[0] as String;

      switch (type) {
        case 'EVENT':
          if (msg.length >= 3) {
            final eventJson = msg[2] as Map<String, dynamic>;
            final event = NostrEvent.fromJson(eventJson);
            if (event != null && !_seenEventIds.contains(event.id)) {
              _seenEventIds.add(event.id);

              // Cap dedup cache size
              if (_seenEventIds.length > 10000) {
                _seenEventIds.remove(_seenEventIds.first);
              }

              // Dispatch to matching subscriptions
              final subId = msg[1] as String;
              final sub = _subscriptions[subId];
              if (sub != null) {
                sub.handler(event);
              }

              _eventController.add(event);
            }
          }
        case 'EOSE':
          // End of stored events — subscription is now live
          break;
        case 'OK':
          // Event publish acknowledgement
          break;
        case 'NOTICE':
          // Relay notice/error message
          break;
      }
    } catch (_) {
      // Ignore malformed messages
    }
  }

  // ---------------------------------------------------------------------------
  // Publishing
  // ---------------------------------------------------------------------------

  /// Send an event to all connected relays (or specific ones).
  void sendEvent(NostrEvent event, {List<String>? relayUrls}) {
    final message = jsonEncode(['EVENT', event.toJson()]);
    final targets = relayUrls ?? _relays.keys.toList();

    for (final url in targets) {
      final relay = _relays[url];
      if (relay != null && relay.status == RelayStatus.connected) {
        relay.channel?.sink.add(message);
      }
    }
  }

  /// Send an event to relays mapped to a geohash.
  void sendEventToGeohash(NostrEvent event, String geohash) {
    final relayUrls = _geohashRelayMap.entries
        .where((e) => e.value.contains(geohash))
        .map((e) => e.key)
        .toList();

    if (relayUrls.isEmpty) {
      // Fallback to all
      sendEvent(event);
    } else {
      sendEvent(event, relayUrls: relayUrls);
    }
  }

  // ---------------------------------------------------------------------------
  // Subscriptions
  // ---------------------------------------------------------------------------

  static final _rng = Random();
  static String _generateSubId() {
    final chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(8, (_) => chars[_rng.nextInt(chars.length)]).join();
  }

  /// Subscribe to events matching a filter.
  ///
  /// Returns the subscription ID for later unsubscribing.
  String subscribe(
    NostrFilter filter,
    void Function(NostrEvent) handler, {
    String? id,
    List<String>? targetRelayUrls,
  }) {
    final subId = id ?? _generateSubId();
    final sub = _SubscriptionInfo(
      id: subId,
      filter: filter,
      handler: handler,
      targetRelayUrls: targetRelayUrls,
    );
    _subscriptions[subId] = sub;

    // Send to connected relays
    for (final relay in _relays.values) {
      if (relay.status == RelayStatus.connected) {
        _sendSubscription(relay, sub);
      }
    }

    return subId;
  }

  /// Unsubscribe from events.
  void unsubscribe(String id) {
    _subscriptions.remove(id);
    final message = jsonEncode(['CLOSE', id]);
    for (final relay in _relays.values) {
      if (relay.status == RelayStatus.connected) {
        relay.channel?.sink.add(message);
      }
    }
  }

  void _sendSubscription(RelayInfo relay, _SubscriptionInfo sub) {
    // Only send to target relays if specified
    if (sub.targetRelayUrls != null &&
        !sub.targetRelayUrls!.contains(relay.url)) {
      return;
    }

    final message = jsonEncode(['REQ', sub.id, sub.filter.toJson()]);
    relay.channel?.sink.add(message);
  }

  // ---------------------------------------------------------------------------
  // Geohash routing
  // ---------------------------------------------------------------------------

  /// Map a geohash to specific relay URLs for targeted routing.
  void mapGeohashToRelays(String geohash, List<String> relayUrls) {
    for (final url in relayUrls) {
      _geohashRelayMap.putIfAbsent(url, () => {}).add(geohash);
      addRelay(url);
    }
  }

  /// Subscribe to geohash channel events.
  String subscribeToGeohash(
    String geohash,
    void Function(NostrEvent) handler, {
    int? since,
  }) {
    final filter = NostrFilter.geohashEphemeral(geohash, since: since);
    final relayUrls = _geohashRelayMap.entries
        .where((e) => e.value.contains(geohash))
        .map((e) => e.key)
        .toList();

    return subscribe(
      filter,
      handler,
      targetRelayUrls: relayUrls.isEmpty ? null : relayUrls,
    );
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  /// Dispose all resources.
  void dispose() {
    disconnect();
    _eventController.close();
    _subscriptions.clear();
    _seenEventIds.clear();
  }

  /// Get deduplication cache stats.
  int get deduplicationCacheSize => _seenEventIds.length;

  /// Clear deduplication cache.
  void clearDeduplicationCache() => _seenEventIds.clear();
}
