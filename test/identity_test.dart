import 'package:flutter_test/flutter_test.dart';

import 'package:bitchat/services/identity_service.dart';

void main() {
  // ---------------------------------------------------------------------------
  // IdentityService.computeFingerprint
  // ---------------------------------------------------------------------------
  group('IdentityService.computeFingerprint', () {
    test('produces 64-char hex string', () {
      final fp = IdentityService.computeFingerprint(
        'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2',
      );
      expect(fp.length, 64);
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(fp), true);
    });

    test('same input produces same fingerprint', () {
      final key = 'deadbeef' * 8;
      final fp1 = IdentityService.computeFingerprint(key);
      final fp2 = IdentityService.computeFingerprint(key);
      expect(fp1, equals(fp2));
    });

    test('different inputs produce different fingerprints', () {
      final fp1 = IdentityService.computeFingerprint('aa' * 32);
      final fp2 = IdentityService.computeFingerprint('bb' * 32);
      expect(fp1, isNot(equals(fp2)));
    });
  });

  // ---------------------------------------------------------------------------
  // PeerIdentity
  // ---------------------------------------------------------------------------
  group('PeerIdentity', () {
    test('displayName prioritizes petname', () {
      final id = PeerIdentity(
        publicKeyHex: 'aa' * 32,
        fingerprint: 'ff' * 32,
        nickname: 'Alice',
        petname: 'My Friend',
      );
      expect(id.displayName, 'My Friend');
    });

    test('displayName falls back to nickname', () {
      final id = PeerIdentity(
        publicKeyHex: 'aa' * 32,
        fingerprint: 'ff' * 32,
        nickname: 'Bob',
      );
      expect(id.displayName, 'Bob');
    });

    test('displayName falls back to short pubkey', () {
      final id = PeerIdentity(
        publicKeyHex: 'aabbccdd' * 8,
        fingerprint: 'ff' * 32,
      );
      expect(id.displayName, 'aabbccdd…');
    });

    test('formattedFingerprint groups by 4', () {
      final id = PeerIdentity(
        publicKeyHex: 'aa' * 32,
        fingerprint: 'abcdef0123456789' * 4,
      );
      final formatted = id.formattedFingerprint;
      final groups = formatted.split(' ');
      expect(groups.first.length, 4);
    });

    test('shortFingerprint shows first and last 8 chars', () {
      final fp = 'abcdef0123456789' * 4;
      final id = PeerIdentity(publicKeyHex: 'aa' * 32, fingerprint: fp);
      expect(id.shortFingerprint, contains('…'));
      expect(id.shortFingerprint.length, 17); // 8 + 1 + 8
    });

    test('JSON round-trip', () {
      final original = PeerIdentity(
        publicKeyHex: 'aa' * 32,
        fingerprint: 'ff' * 32,
        nickname: 'Alice',
        petname: 'Friend',
        trustLevel: TrustLevel.verified,
        isFavorite: true,
      );
      final json = original.toJson();
      final restored = PeerIdentity.fromJson(json);
      expect(restored.publicKeyHex, original.publicKeyHex);
      expect(restored.nickname, 'Alice');
      expect(restored.petname, 'Friend');
      expect(restored.trustLevel, TrustLevel.verified);
      expect(restored.isFavorite, true);
    });
  });

  // ---------------------------------------------------------------------------
  // IdentityService
  // ---------------------------------------------------------------------------
  group('IdentityService', () {
    late IdentityService service;

    setUp(() {
      service = IdentityService();
    });

    test('getOrCreate creates new identity', () {
      final id = service.getOrCreate('aa' * 32, nickname: 'Alice');
      expect(id.nickname, 'Alice');
      expect(id.trustLevel, TrustLevel.unknown);
      expect(service.identities.length, 1);
    });

    test('getOrCreate returns existing identity', () {
      service.getOrCreate('aa' * 32, nickname: 'Alice');
      final same = service.getOrCreate('aa' * 32, nickname: 'Alice2');
      expect(same.nickname, 'Alice2'); // updated
      expect(service.identities.length, 1);
    });

    test('verify sets trust level', () {
      final id = service.getOrCreate('aa' * 32);
      service.verify(id.fingerprint);
      expect(id.trustLevel, TrustLevel.verified);
    });

    test('unverify resets to casual', () {
      final id = service.getOrCreate('aa' * 32);
      service.verify(id.fingerprint);
      service.unverify(id.fingerprint);
      expect(id.trustLevel, TrustLevel.casual);
    });

    test('block and unblock', () {
      final id = service.getOrCreate('aa' * 32);
      service.block(id.fingerprint);
      expect(id.isBlocked, true);
      expect(service.blockedPeers.length, 1);

      service.unblock(id.fingerprint);
      expect(id.isBlocked, false);
      expect(service.blockedPeers.length, 0);
    });

    test('contacts excludes blocked', () {
      service.getOrCreate('aa' * 32, nickname: 'Alice');
      final bob = service.getOrCreate('bb' * 32, nickname: 'Bob');
      service.block(bob.fingerprint);

      final contacts = service.contacts;
      expect(contacts.length, 1);
      expect(contacts.first.nickname, 'Alice');
    });

    test('contacts sorted by trust level', () {
      final alice = service.getOrCreate('aa' * 32, nickname: 'Alice');
      service.getOrCreate('bb' * 32, nickname: 'Bob');
      service.verify(alice.fingerprint);

      final contacts = service.contacts;
      expect(contacts.first.nickname, 'Alice'); // verified first
    });

    test('setPetname', () {
      final id = service.getOrCreate('aa' * 32, nickname: 'Alice');
      service.setPetname(id.fingerprint, 'My BFF');
      expect(id.displayName, 'My BFF');
    });

    test('toggleFavorite', () {
      final id = service.getOrCreate('aa' * 32);
      expect(id.isFavorite, false);
      service.toggleFavorite(id.fingerprint);
      expect(id.isFavorite, true);
      service.toggleFavorite(id.fingerprint);
      expect(id.isFavorite, false);
    });

    test('remove identity', () {
      final id = service.getOrCreate('aa' * 32);
      service.remove(id.fingerprint);
      expect(service.identities.length, 0);
    });

    test('export and import JSON', () {
      service.getOrCreate('aa' * 32, nickname: 'Alice');
      service.getOrCreate('bb' * 32, nickname: 'Bob');

      final json = service.exportJson();
      final newService = IdentityService();
      newService.importJson(json);

      expect(newService.identities.length, 2);
    });

    test('byPubKey lookup', () {
      service.getOrCreate('aa' * 32, nickname: 'Alice');
      final found = service.byPubKey('aa' * 32);
      expect(found, isNotNull);
      expect(found!.nickname, 'Alice');
    });
  });

  // ---------------------------------------------------------------------------
  // TrustLevel enum
  // ---------------------------------------------------------------------------
  group('TrustLevel', () {
    test('has 4 values', () {
      expect(TrustLevel.values.length, 4);
    });

    test('ordering: unknown < casual < trusted < verified', () {
      expect(TrustLevel.unknown.index, lessThan(TrustLevel.casual.index));
      expect(TrustLevel.casual.index, lessThan(TrustLevel.trusted.index));
      expect(TrustLevel.trusted.index, lessThan(TrustLevel.verified.index));
    });
  });
}
