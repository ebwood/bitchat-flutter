import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

import 'package:bitchat/nostr/nostr_event.dart';
import 'package:bitchat/nostr/nostr_filter.dart';
import 'package:bitchat/nostr/nostr_relay_manager.dart';

void main() {
  group('NostrCrypto', () {
    test('generateKeyPair produces valid keys', () {
      final (privKey, pubKey) = NostrCrypto.generateKeyPair();
      expect(privKey.length, 64); // 32 bytes hex
      expect(pubKey.length, 64);
    });

    test('derivePublicKey matches generated pair', () {
      final (privKey, pubKey) = NostrCrypto.generateKeyPair();
      final derived = NostrCrypto.derivePublicKey(privKey);
      expect(derived, pubKey);
    });

    test('schnorrSign and schnorrVerify round-trip', () {
      final (privKey, pubKey) = NostrCrypto.generateKeyPair();
      final message = Uint8List(32);
      for (var i = 0; i < 32; i++) {
        message[i] = i;
      }

      final sig = NostrCrypto.schnorrSign(message, privKey);
      expect(sig.length, 128); // 64 bytes hex

      final valid = NostrCrypto.schnorrVerify(message, sig, pubKey);
      expect(valid, true);
    });

    test('schnorrVerify rejects tampered message', () {
      final (privKey, pubKey) = NostrCrypto.generateKeyPair();
      final message = Uint8List(32);
      final sig = NostrCrypto.schnorrSign(message, privKey);

      message[0] = 0xFF;
      final valid = NostrCrypto.schnorrVerify(message, sig, pubKey);
      expect(valid, false);
    });

    test('schnorrVerify rejects wrong key', () {
      final (privKey1, _) = NostrCrypto.generateKeyPair();
      final (_, pubKey2) = NostrCrypto.generateKeyPair();
      final message = Uint8List(32);
      final sig = NostrCrypto.schnorrSign(message, privKey1);

      final valid = NostrCrypto.schnorrVerify(message, sig, pubKey2);
      expect(valid, false);
    });
  });

  group('NostrEvent', () {
    test('createTextNote produces valid signed event', () {
      final (privKey, pubKey) = NostrCrypto.generateKeyPair();
      final event = NostrEvent.createTextNote(
        content: 'Hello Nostr from BitChat!',
        publicKeyHex: pubKey,
        privateKeyHex: privKey,
      );

      expect(event.id.length, 64);
      expect(event.pubkey, pubKey);
      expect(event.kind, NostrKind.textNote);
      expect(event.content, 'Hello Nostr from BitChat!');
      expect(event.sig, isNotNull);
      expect(event.sig!.length, 128);
    });

    test('event signature is valid', () {
      final (privKey, pubKey) = NostrCrypto.generateKeyPair();
      final event = NostrEvent.createTextNote(
        content: 'Test message',
        publicKeyHex: pubKey,
        privateKeyHex: privKey,
      );

      expect(event.isValidSignature(), true);
      expect(event.isValid(), true);
    });

    test('createGeohashEvent includes geohash tag', () {
      final (privKey, pubKey) = NostrCrypto.generateKeyPair();
      final event = NostrEvent.createGeohashEvent(
        content: 'Location message',
        geohash: 'w21z3w',
        publicKeyHex: pubKey,
        privateKeyHex: privKey,
        nickname: 'alice',
      );

      expect(event.kind, NostrKind.ephemeralEvent);
      expect(event.getTagValue('g'), 'w21z3w');
      expect(event.getTagValue('n'), 'alice');
      expect(event.isValid(), true);
    });

    test('JSON round-trip preserves event', () {
      final (privKey, pubKey) = NostrCrypto.generateKeyPair();
      final original = NostrEvent.createTextNote(
        content: 'Round trip test',
        publicKeyHex: pubKey,
        privateKeyHex: privKey,
      );

      final json = original.toJsonString();
      final restored = NostrEvent.fromJsonString(json);

      expect(restored, isNotNull);
      expect(restored!.id, original.id);
      expect(restored.pubkey, original.pubkey);
      expect(restored.content, original.content);
      expect(restored.sig, original.sig);
      expect(restored.isValidSignature(), true);
    });

    test('event ID is deterministic', () {
      final (privKey, pubKey) = NostrCrypto.generateKeyPair();
      final event = NostrEvent(
        pubkey: pubKey,
        createdAt: 1700000000,
        kind: NostrKind.textNote,
        tags: [],
        content: 'Deterministic ID test',
      );

      final id1 = event.computeEventIdHex();
      final id2 = event.computeEventIdHex();
      expect(id1, id2);
      expect(id1.length, 64);
    });
  });

  group('NostrFilter', () {
    test('toJson includes all set fields', () {
      final filter = NostrFilter(
        kinds: [1],
        since: 1700000000,
        limit: 50,
        tagFilters: {
          'g': ['w21z3w'],
        },
      );

      final json = filter.toJson();
      expect(json['kinds'], [1]);
      expect(json['since'], 1700000000);
      expect(json['limit'], 50);
      expect(json['#g'], ['w21z3w']);
      expect(json.containsKey('ids'), false);
    });

    test('giftWrapsFor creates correct filter', () {
      final filter = NostrFilter.giftWrapsFor('abc123');
      expect(filter.kinds, [NostrKind.giftWrap]);
      expect(filter.limit, 100);
      final json = filter.toJson();
      expect(json['#p'], ['abc123']);
    });

    test('geohashEphemeral creates correct filter', () {
      final filter = NostrFilter.geohashEphemeral('w21z3w');
      expect(filter.kinds, contains(NostrKind.ephemeralEvent));
      expect(filter.kinds, contains(NostrKind.geohashPresence));
      expect(filter.geohash, 'w21z3w');
    });

    test('matches filters events correctly', () {
      final filter = NostrFilter(
        kinds: [NostrKind.textNote],
        since: 1700000000,
      );

      final match = NostrEvent(
        pubkey: 'a' * 64,
        createdAt: 1700000001,
        kind: NostrKind.textNote,
        tags: [],
        content: 'match',
      );

      final noMatch = NostrEvent(
        pubkey: 'b' * 64,
        createdAt: 1600000000,
        kind: NostrKind.textNote,
        tags: [],
        content: 'too old',
      );

      expect(filter.matches(match), true);
      expect(filter.matches(noMatch), false);
    });
  });

  group('NostrRelayManager', () {
    test('initialization with default relays', () {
      final mgr = NostrRelayManager();
      expect(mgr.relayStatuses.length, NostrRelayManager.defaultRelays.length);
      expect(mgr.connectedCount, 0);
      expect(mgr.activeSubscriptionCount, 0);
    });

    test('custom relay URLs', () {
      final mgr = NostrRelayManager(
        relayUrls: ['wss://relay1.test', 'wss://relay2.test'],
      );
      expect(mgr.relayStatuses.length, 2);
      expect(
        mgr.relayStatuses.keys,
        containsAll(['wss://relay1.test', 'wss://relay2.test']),
      );
    });

    test('deduplication cache', () {
      final mgr = NostrRelayManager();
      expect(mgr.deduplicationCacheSize, 0);
      mgr.clearDeduplicationCache();
      expect(mgr.deduplicationCacheSize, 0);
    });

    test('subscribe and unsubscribe tracking', () {
      final mgr = NostrRelayManager(relayUrls: []);
      final subId = mgr.subscribe(NostrFilter(kinds: [1]), (event) {});
      expect(mgr.activeSubscriptionCount, 1);

      mgr.unsubscribe(subId);
      expect(mgr.activeSubscriptionCount, 0);
    });

    test('geohash relay mapping', () {
      final mgr = NostrRelayManager(relayUrls: []);
      mgr.mapGeohashToRelays('w21z', ['wss://geo-relay.test']);
      expect(mgr.relayStatuses.containsKey('wss://geo-relay.test'), true);
    });

    test('dispose cleans up', () {
      final mgr = NostrRelayManager(relayUrls: []);
      mgr.subscribe(NostrFilter(kinds: [1]), (e) {});
      mgr.dispose();
      expect(mgr.activeSubscriptionCount, 0);
    });
  });
}
