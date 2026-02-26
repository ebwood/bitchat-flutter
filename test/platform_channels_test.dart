import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

import 'package:bitchat/platform/native_channels.dart';
import 'package:bitchat/platform/tor_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  // BLEPeripheralChannel
  // ---------------------------------------------------------------------------
  group('BLEPeripheralChannel', () {
    test('initial state is unknown', () {
      final ble = BLEPeripheralChannel.instance;
      expect(ble.state, PeripheralState.unknown);
    });

    test('state stream broadcasts changes', () async {
      final ble = BLEPeripheralChannel.instance;
      final states = <PeripheralState>[];
      final sub = ble.stateChanges.listen(states.add);

      // Simulate native callback
      await ble.handleMethodCallForTest(
        const MethodCall('onStateChanged', 'advertising'),
      );

      expect(states, [PeripheralState.advertising]);
      expect(ble.state, PeripheralState.advertising);
      await sub.cancel();
    });

    test('data received stream works', () async {
      final ble = BLEPeripheralChannel.instance;
      final data = <BLEReceivedData>[];
      final sub = ble.receivedData.listen(data.add);

      await ble.handleMethodCallForTest(
        const MethodCall('onDataReceived', {
          'data': [1, 2, 3, 4],
          'centralId': 'test-central',
        }),
      );

      expect(data.length, 1);
      expect(data[0].data, [1, 2, 3, 4]);
      expect(data[0].centralId, 'test-central');
      await sub.cancel();
    });
  });

  // ---------------------------------------------------------------------------
  // ForegroundServiceChannel
  // ---------------------------------------------------------------------------
  group('ForegroundServiceChannel', () {
    test('initial state is not running', () {
      final svc = ForegroundServiceChannel.instance;
      expect(svc.isRunning, false);
    });
  });

  // ---------------------------------------------------------------------------
  // BootReceiverChannel
  // ---------------------------------------------------------------------------
  group('BootReceiverChannel', () {
    test('exists as singleton', () {
      expect(BootReceiverChannel.instance, isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  // PeripheralState
  // ---------------------------------------------------------------------------
  group('PeripheralState', () {
    test('all states accessible', () {
      expect(PeripheralState.values.length, 7);
      expect(PeripheralState.unknown, isNotNull);
      expect(PeripheralState.advertising, isNotNull);
      expect(PeripheralState.connected, isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  // ArtiTorManager
  // ---------------------------------------------------------------------------
  group('ArtiTorManager', () {
    late ArtiTorManager tor;

    setUp(() {
      tor = ArtiTorManager(bootstrapDelay: Duration.zero);
    });

    tearDown(() {
      tor.dispose();
    });

    test('initial state is not initialized', () {
      expect(tor.status, TorFfiStatus.notInitialized);
      expect(tor.isReady, false);
      expect(tor.socksProxyUrl, isNull);
    });

    test('bootstrap lifecycle', () async {
      final statuses = <TorFfiStatus>[];
      tor.statusStream.listen(statuses.add);

      await tor.initialize('/tmp/tor_state');
      expect(tor.status, TorFfiStatus.notInitialized);

      final port = await tor.bootstrap();
      expect(port, 9050);
      expect(tor.status, TorFfiStatus.ready);
      expect(tor.isReady, true);
      expect(tor.socksProxyUrl, 'socks5://127.0.0.1:9050');

      expect(statuses, contains(TorFfiStatus.bootstrapping));
      expect(statuses, contains(TorFfiStatus.ready));
    });

    test('shutdown clears state', () async {
      await tor.initialize('/tmp/tor_state');
      await tor.bootstrap();
      await tor.shutdown();

      expect(tor.status, TorFfiStatus.shutdown);
      expect(tor.isReady, false);
      expect(tor.socksPort, isNull);
      expect(tor.socksProxyUrl, isNull);
    });
  });
}
