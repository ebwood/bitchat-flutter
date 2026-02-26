import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Debug settings panel — extensive debug UI for mesh stats,
/// protocol info, relay status, and experimental toggles.
///
/// Matches Android `DebugSettingsSheet.kt` design:
/// - Network stats (relay connection, peers, messages)
/// - Protocol info (Noise state, encryption)
/// - Experimental feature toggles
/// - Log viewer
class DebugPanel extends StatefulWidget {
  const DebugPanel({
    super.key,
    this.relayUrl = 'wss://relay.damus.io',
    this.relayStatus = 'Connected',
    this.connectedPeers = 0,
    this.messagesSent = 0,
    this.messagesReceived = 0,
    this.bleStatus = 'Scanning',
    this.noiseState = 'XX Handshake Complete',
    this.publicKeyHex = '',
    this.powDifficulty = 0,
    this.powEnabled = false,
    this.coverTrafficEnabled = false,
    this.compressionEnabled = true,
    this.onPowToggle,
    this.onCoverTrafficToggle,
    this.onCompressionToggle,
  });

  final String relayUrl;
  final String relayStatus;
  final int connectedPeers;
  final int messagesSent;
  final int messagesReceived;
  final String bleStatus;
  final String noiseState;
  final String publicKeyHex;
  final int powDifficulty;
  final bool powEnabled;
  final bool coverTrafficEnabled;
  final bool compressionEnabled;
  final ValueChanged<bool>? onPowToggle;
  final ValueChanged<bool>? onCoverTrafficToggle;
  final ValueChanged<bool>? onCompressionToggle;

  @override
  State<DebugPanel> createState() => _DebugPanelState();
}

class _DebugPanelState extends State<DebugPanel> {
  late bool _powEnabled;
  late bool _coverTraffic;
  late bool _compression;

  @override
  void initState() {
    super.initState();
    _powEnabled = widget.powEnabled;
    _coverTraffic = widget.coverTrafficEnabled;
    _compression = widget.compressionEnabled;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = isDark
        ? const Color(0xFF32D74B)
        : const Color(0xFF248A3D);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.bug_report, size: 18, color: accentColor),
            const SizedBox(width: 8),
            const Text(
              'Debug Panel',
              style: TextStyle(fontFamily: 'monospace', fontSize: 16),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // --- Network Stats ---
          _SectionHeader('NETWORK', accentColor),
          _StatRow('Relay', widget.relayUrl, colorScheme),
          _StatRow(
            'Status',
            widget.relayStatus,
            colorScheme,
            valueColor: widget.relayStatus == 'Connected'
                ? Colors.green
                : Colors.orange,
          ),
          _StatRow('BLE', widget.bleStatus, colorScheme),
          _StatRow('Connected Peers', '${widget.connectedPeers}', colorScheme),
          _StatRow('Messages Sent', '${widget.messagesSent}', colorScheme),
          _StatRow(
            'Messages Received',
            '${widget.messagesReceived}',
            colorScheme,
          ),

          const SizedBox(height: 12),

          // --- Encryption ---
          _SectionHeader('ENCRYPTION', accentColor),
          _StatRow('Noise Protocol', 'XX_25519_ChaChaPoly_SHA256', colorScheme),
          _StatRow('Handshake', widget.noiseState, colorScheme),
          _CopyRow(
            label: 'Public Key',
            value: widget.publicKeyHex.isEmpty
                ? '(not yet generated)'
                : '${widget.publicKeyHex.substring(0, 16)}…',
            fullValue: widget.publicKeyHex,
            colorScheme: colorScheme,
          ),

          const SizedBox(height: 12),

          // --- Feature Toggles ---
          _SectionHeader('EXPERIMENTAL', accentColor),
          _ToggleRow(
            icon: Icons.security,
            label: 'Proof of Work',
            subtitle: 'Difficulty: ${widget.powDifficulty} bits',
            value: _powEnabled,
            onChanged: (v) {
              setState(() => _powEnabled = v);
              widget.onPowToggle?.call(v);
            },
            colorScheme: colorScheme,
            accentColor: accentColor,
          ),
          _ToggleRow(
            icon: Icons.shuffle,
            label: 'Cover Traffic',
            subtitle: 'Random dummy packets',
            value: _coverTraffic,
            onChanged: (v) {
              setState(() => _coverTraffic = v);
              widget.onCoverTrafficToggle?.call(v);
            },
            colorScheme: colorScheme,
            accentColor: accentColor,
          ),
          _ToggleRow(
            icon: Icons.compress,
            label: 'Compression',
            subtitle: 'Zlib message compression',
            value: _compression,
            onChanged: (v) {
              setState(() => _compression = v);
              widget.onCompressionToggle?.call(v);
            },
            colorScheme: colorScheme,
            accentColor: accentColor,
          ),

          const SizedBox(height: 12),

          // --- Protocol Info ---
          _SectionHeader('PROTOCOL', accentColor),
          _StatRow('Packet v2 Header', '16 bytes', colorScheme),
          _StatRow('Byte Order', 'Big-endian', colorScheme),
          _StatRow('Padding', 'PKCS#7', colorScheme),
          _StatRow('Nostr NIPs', 'NIP-01, NIP-04', colorScheme),
          _StatRow('BLE UUIDs', 'BitChat Standard', colorScheme),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, this.accentColor);
  final String title;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: accentColor.withValues(alpha: 0.7),
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow(this.label, this.value, this.colorScheme, {this.valueColor});
  final String label;
  final String value;
  final ColorScheme colorScheme;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: valueColor ?? colorScheme.onSurface.withValues(alpha: 0.8),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({
    required this.label,
    required this.value,
    required this.fullValue,
    required this.colorScheme,
  });
  final String label;
  final String value;
  final String fullValue;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
          if (fullValue.isNotEmpty)
            IconButton(
              icon: Icon(Icons.copy, size: 12, color: colorScheme.primary),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: fullValue));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Copied public key'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.colorScheme,
    required this.accentColor,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final ColorScheme colorScheme;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      dense: true,
      secondary: Icon(
        icon,
        size: 18,
        color: colorScheme.onSurface.withValues(alpha: 0.5),
      ),
      title: Text(
        label,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 10,
          color: colorScheme.onSurface.withValues(alpha: 0.4),
        ),
      ),
      value: value,
      activeColor: accentColor,
      onChanged: onChanged,
    );
  }
}
