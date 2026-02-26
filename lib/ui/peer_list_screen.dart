import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:bitchat/ble/ble_mesh_service.dart';
import 'package:bitchat/ui/app_theme.dart';

/// Full-screen peer list showing discovered and connected BLE mesh peers.
///
/// When [bleService] is provided, the screen subscribes to real-time peer
/// updates from the BLE mesh. When null, shows an "Enable Mesh mode" prompt.
class PeerListScreen extends StatefulWidget {
  const PeerListScreen({super.key, this.bleService});

  final BLEMeshService? bleService;

  @override
  State<PeerListScreen> createState() => _PeerListScreenState();
}

class _PeerListScreenState extends State<PeerListScreen> {
  List<BLEPeerInfo> _peers = [];
  StreamSubscription<List<BLEPeerInfo>>? _peerSub;

  @override
  void initState() {
    super.initState();
    if (widget.bleService != null) {
      _peers = widget.bleService!.peers;
      _peerSub = widget.bleService!.peersStream.listen((peers) {
        if (mounted) setState(() => _peers = peers);
      });
    }
  }

  @override
  void dispose() {
    _peerSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Peers${_peers.isNotEmpty ? ' (${_peers.length})' : ''}'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colorScheme.primary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: widget.bleService == null
          ? _buildNoServiceState(theme, colorScheme)
          : _peers.isEmpty
          ? _buildEmptyState(theme, colorScheme)
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _peers.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, indent: 56, color: colorScheme.surface),
              itemBuilder: (context, index) =>
                  _buildPeerTile(context, _peers[index], theme, colorScheme),
            ),
    );
  }

  Widget _buildNoServiceState(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.bluetooth_disabled,
            size: 40,
            color: colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'BLE Mesh not active',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Switch to Mesh mode to discover peers',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Scanning animation
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colorScheme.primary.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 20),
          Icon(
            Icons.bluetooth_searching,
            size: 40,
            color: colorScheme.primary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No peers discovered',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Scanning for nearby BitChat nodes...',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeerTile(
    BuildContext context,
    BLEPeerInfo peer,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final rssiColor = AppTheme.rssiColor(peer.rssi);
    final peerIdStr = peer.peerID.id;
    final peerIdShort = peer.peerID.shortId;
    final displayName = peer.nickname ?? peerIdShort;

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color:
              (peer.isConnected ? colorScheme.primary : colorScheme.onSurface)
                  .withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Icon(
            peer.isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
            size: 20,
            color: peer.isConnected
                ? colorScheme.primary
                : colorScheme.onSurface.withValues(alpha: 0.4),
          ),
        ),
      ),
      title: Text(
        displayName,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: peer.isConnected
              ? colorScheme.onSurface
              : colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      ),
      subtitle: Text(
        peerIdShort,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          color: colorScheme.onSurface.withValues(alpha: 0.4),
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // RSSI bars
          _RssiBars(rssi: peer.rssi, color: rssiColor),
          const SizedBox(width: 8),
          Text(
            '${peer.rssi}',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              color: rssiColor,
            ),
          ),
        ],
      ),
      onTap: () => _showPeerDetails(
        context,
        peer,
        peerIdStr,
        peerIdShort,
        displayName,
        colorScheme,
      ),
    );
  }

  void _showPeerDetails(
    BuildContext context,
    BLEPeerInfo peer,
    String peerId,
    String peerIdShort,
    String displayName,
    ColorScheme colorScheme,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _DetailRow(
              label: 'Nickname',
              value: displayName,
              colorScheme: colorScheme,
            ),
            _DetailRow(
              label: 'Peer ID',
              value: peerId,
              colorScheme: colorScheme,
              copyable: true,
            ),
            _DetailRow(
              label: 'RSSI',
              value: '${peer.rssi} dBm',
              colorScheme: colorScheme,
            ),
            _DetailRow(
              label: 'Status',
              value: peer.isConnected ? 'Connected' : 'Discovered',
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helper widgets
// ---------------------------------------------------------------------------

class _RssiBars extends StatelessWidget {
  const _RssiBars({required this.rssi, required this.color});

  final int rssi;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final bars = rssi >= -50
        ? 3
        : rssi >= -70
        ? 2
        : 1;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(3, (i) {
        final height = 6.0 + i * 4.0;
        final active = i < bars;
        return Container(
          width: 3,
          height: height,
          margin: const EdgeInsets.only(right: 1),
          decoration: BoxDecoration(
            color: active ? color : color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.colorScheme,
    this.copyable = false,
  });

  final String label;
  final String value;
  final ColorScheme colorScheme;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
          if (copyable)
            IconButton(
              icon: Icon(Icons.copy, size: 14, color: colorScheme.primary),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Copied: $label'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }
}
