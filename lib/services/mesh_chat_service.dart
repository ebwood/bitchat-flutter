import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:bitchat/ble/ble_mesh_service.dart';
import 'package:bitchat/models/bitchat_message.dart';
import 'package:bitchat/models/bitchat_packet.dart';
import 'package:bitchat/models/message_type.dart' as proto;
import 'package:bitchat/models/peer_id.dart';
import 'package:bitchat/services/nostr_chat_service.dart';

/// Mesh chat connection status.
enum MeshConnectionStatus { disconnected, scanning, connected }

/// Adapter that bridges [BLEMeshService] into a [ChatMessage] stream
/// compatible with the chat UI.
///
/// Converts outgoing text/image/voice into [BitchatPacket] broadcasts,
/// and incoming packets into [ChatMessage] objects.
class MeshChatService {
  MeshChatService({String? nickname})
    : _nickname = nickname ?? 'anon',
      _myPeerID = PeerID.generate();

  final PeerID _myPeerID;
  String _nickname;

  late final BLEMeshService _bleService = BLEMeshService(
    myPeerID: _myPeerID,
    nickname: _nickname,
  );

  /// Expose BLE service for peer list, etc.
  BLEMeshService get bleService => _bleService;

  // --- Streams ---
  final _messageController = StreamController<ChatMessage>.broadcast();
  final _statusController = StreamController<MeshConnectionStatus>.broadcast();

  Stream<ChatMessage> get messages => _messageController.stream;
  Stream<MeshConnectionStatus> get statusStream => _statusController.stream;
  Stream<List<BLEPeerInfo>> get peersStream => _bleService.peersStream;

  MeshConnectionStatus _status = MeshConnectionStatus.disconnected;
  MeshConnectionStatus get status => _status;

  StreamSubscription? _packetSub;
  StreamSubscription? _bleStatusSub;

  /// Current connected peer count.
  int get connectedPeerCount => _bleService.connectedPeerCount;

  /// Current peer list.
  List<BLEPeerInfo> get peers => _bleService.peers;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Request BLE permissions and start scanning.
  Future<bool> start() async {
    // Check adapter state — on macOS, the first value may be `unknown`
    // so we wait up to 5 seconds for a definitive state.
    try {
      final adapterState = await FlutterBluePlus.adapterState
          .where((s) => s != BluetoothAdapterState.unknown)
          .first
          .timeout(const Duration(seconds: 5));
      if (adapterState != BluetoothAdapterState.on) {
        debugPrint(
          '[mesh-chat] Bluetooth is not enabled (state: $adapterState)',
        );
        _updateStatus(MeshConnectionStatus.disconnected);
        return false;
      }
    } catch (e) {
      debugPrint('[mesh-chat] Failed to check Bluetooth state: $e');
      _updateStatus(MeshConnectionStatus.disconnected);
      return false;
    }

    // Listen to BLE status changes
    _bleStatusSub = _bleService.statusStream.listen((bleStatus) {
      switch (bleStatus) {
        case BLEMeshStatus.idle:
          _updateStatus(MeshConnectionStatus.disconnected);
        case BLEMeshStatus.scanning:
          _updateStatus(MeshConnectionStatus.scanning);
        case BLEMeshStatus.connected:
          _updateStatus(MeshConnectionStatus.connected);
        case BLEMeshStatus.error:
          _updateStatus(MeshConnectionStatus.disconnected);
      }
    });

    // Listen to incoming packets
    _packetSub = _bleService.packetStream.listen(_handlePacket);

    // Reduce FBP log noise — only warnings and above
    FlutterBluePlus.setLogLevel(LogLevel.warning);

    // Start BLE scanning
    _updateStatus(MeshConnectionStatus.scanning);
    await _bleService.start();
    return true;
  }

  /// Stop BLE mesh.
  Future<void> stop() async {
    _packetSub?.cancel();
    _packetSub = null;
    _bleStatusSub?.cancel();
    _bleStatusSub = null;
    await _bleService.stop();
    _updateStatus(MeshConnectionStatus.disconnected);
  }

  /// Dispose all resources.
  void dispose() {
    _packetSub?.cancel();
    _packetSub = null;
    _bleStatusSub?.cancel();
    _bleStatusSub = null;
    _bleService.dispose();
    _messageController.close();
    _statusController.close();
  }

  // ---------------------------------------------------------------------------
  // Sending
  // ---------------------------------------------------------------------------

  /// Send a text message via BLE broadcast.
  Future<void> sendMessage(String text, {String? senderNickname}) async {
    final nick = senderNickname ?? _nickname;
    final msg = BitchatMessage(
      sender: nick,
      content: text,
      timestamp: DateTime.now(),
      isRelay: false,
    );

    final payload = msg.toBinaryPayload();
    if (payload == null) return;

    final packet = BitchatPacket.create(
      type: proto.MessageType.message.value,
      ttl: BLEConstants.defaultTTL,
      senderPeerID: _myPeerID,
      payload: payload,
    );

    await _bleService.broadcastPacket(packet);
  }

  /// Send an image message via BLE broadcast.
  Future<void> sendImageMessage(
    String base64Data, {
    String? senderNickname,
    int? width,
    int? height,
  }) async {
    final nick = senderNickname ?? _nickname;
    // Build a JSON-encoded image payload
    final imagePayload = jsonEncode({
      'type': 'image',
      'sender': nick,
      'data': base64Data,
      'w': width,
      'h': height,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });

    final packet = BitchatPacket.create(
      type: proto.MessageType.fileTransfer.value,
      ttl: BLEConstants.defaultTTL,
      senderPeerID: _myPeerID,
      payload: Uint8List.fromList(utf8.encode(imagePayload)),
    );

    await _bleService.broadcastPacket(packet);
  }

  /// Send a voice note via BLE broadcast.
  Future<void> sendVoiceMessage(
    String base64Data, {
    String? senderNickname,
    double? duration,
  }) async {
    final nick = senderNickname ?? _nickname;
    final voicePayload = jsonEncode({
      'type': 'voice',
      'sender': nick,
      'data': base64Data,
      'duration': duration,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });

    final packet = BitchatPacket.create(
      type: proto.MessageType.fileTransfer.value,
      ttl: BLEConstants.defaultTTL,
      senderPeerID: _myPeerID,
      payload: Uint8List.fromList(utf8.encode(voicePayload)),
    );

    await _bleService.broadcastPacket(packet);
  }

  // ---------------------------------------------------------------------------
  // Receiving
  // ---------------------------------------------------------------------------

  void _handlePacket(BitchatPacket packet) {
    // Skip our own packets
    final senderPeerId = PeerID.fromBytes(packet.senderID);
    if (senderPeerId.id == _myPeerID.id) return;

    if (packet.type == proto.MessageType.message.value) {
      _handleChatPacket(packet);
    } else if (packet.type == proto.MessageType.fileTransfer.value) {
      _handleFileTransferPacket(packet);
    }
    // Announce (0x01) and other types are handled by BLEMeshService internally
  }

  void _handleChatPacket(BitchatPacket packet) {
    try {
      final msg = BitchatMessage.fromBinaryPayload(packet.payload);
      if (msg == null) return;

      _messageController.add(
        ChatMessage(
          text: msg.content,
          senderNickname: msg.sender,
          senderPubKey: PeerID.fromBytes(packet.senderID).id,
          timestamp: msg.timestamp,
          channel: 'mesh',
          isOwnMessage: false,
        ),
      );
    } catch (e) {
      debugPrint('[mesh-chat] Failed to decode chat packet: $e');
    }
  }

  void _handleFileTransferPacket(BitchatPacket packet) {
    try {
      final jsonStr = utf8.decode(packet.payload, allowMalformed: true);
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final type = data['type'] as String?;
      final sender = data['sender'] as String? ?? 'anon';
      final ts = data['ts'] as int?;
      final timestamp = ts != null
          ? DateTime.fromMillisecondsSinceEpoch(ts)
          : DateTime.now();

      if (type == 'image') {
        _messageController.add(
          ChatMessage(
            text: '[Image]',
            senderNickname: sender,
            senderPubKey: PeerID.fromBytes(packet.senderID).id,
            timestamp: timestamp,
            channel: 'mesh',
            isOwnMessage: false,
            messageType: MessageType.image,
            imageBase64: data['data'] as String?,
            imageWidth: data['w'] as int?,
            imageHeight: data['h'] as int?,
          ),
        );
      } else if (type == 'voice') {
        _messageController.add(
          ChatMessage(
            text: '[Voice Note]',
            senderNickname: sender,
            senderPubKey: PeerID.fromBytes(packet.senderID).id,
            timestamp: timestamp,
            channel: 'mesh',
            isOwnMessage: false,
            messageType: MessageType.voice,
            voiceBase64: data['data'] as String?,
            voiceDuration: (data['duration'] as num?)?.toDouble(),
          ),
        );
      }
    } catch (e) {
      debugPrint('[mesh-chat] Failed to decode file transfer: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _updateStatus(MeshConnectionStatus s) {
    if (_status != s) {
      _status = s;
      _statusController.add(s);
    }
  }

  /// Set nickname.
  void setNickname(String nick) {
    _nickname = nick;
    _bleService.nickname = nick;
  }
}
