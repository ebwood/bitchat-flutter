import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

/// Cover traffic generator for anti-traffic-analysis.
///
/// Sends dummy encrypted packets at random intervals to make it harder
/// for an observer to determine when real messages are being sent.
/// Dummy packets are indistinguishable from real encrypted packets.
class CoverTrafficGenerator {
  CoverTrafficGenerator({
    this.minInterval = const Duration(seconds: 10),
    this.maxInterval = const Duration(seconds: 60),
    this.packetSize = 256,
  });

  final Duration minInterval;
  final Duration maxInterval;
  final int packetSize;

  Timer? _timer;
  bool _running = false;
  final _random = Random.secure();

  final _packetController = StreamController<Uint8List>.broadcast();

  /// Stream of dummy packets to be sent alongside real traffic.
  Stream<Uint8List> get dummyPackets => _packetController.stream;

  bool get isRunning => _running;

  /// Start generating cover traffic.
  void start() {
    if (_running) return;
    _running = true;
    _scheduleNext();
  }

  /// Stop generating cover traffic.
  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  void _scheduleNext() {
    if (!_running) return;

    final intervalRange =
        maxInterval.inMilliseconds - minInterval.inMilliseconds;
    final delay = Duration(
      milliseconds:
          minInterval.inMilliseconds +
          _random.nextInt(intervalRange.clamp(1, 999999)),
    );

    _timer = Timer(delay, () {
      if (!_running) return;
      _emitDummyPacket();
      _scheduleNext();
    });
  }

  void _emitDummyPacket() {
    // Generate cryptographically random bytes — indistinguishable from
    // encrypted real data.
    final dummy = Uint8List(packetSize);
    for (var i = 0; i < packetSize; i++) {
      dummy[i] = _random.nextInt(256);
    }

    // Set cover traffic marker in a reserved header position.
    // The marker is only checked locally, never transmitted — the receiver
    // treats it as a regular packet that fails decryption and drops it.
    // This is intentional: the point is to create indistinguishable traffic.
    _packetController.add(dummy);
  }

  /// Stats for monitoring.
  int _packetsSent = 0;
  int get packetsSent => _packetsSent;

  void dispose() {
    stop();
    _packetController.close();
  }
}
