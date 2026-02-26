import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Settings screen for identity, theme, and network configuration.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.nickname,
    required this.isDark,
    required this.onThemeToggle,
    required this.onNicknameChanged,
  });

  final String nickname;
  final bool isDark;
  final VoidCallback onThemeToggle;
  final ValueChanged<String> onNicknameChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _nickController;
  bool _editing = false;

  // Placeholder identity values
  final String _peerId = 'a1b2c3d4e5f60718';
  final String _fingerprint = 'AB12 CD34 EF56 7890';

  @override
  void initState() {
    super.initState();
    _nickController = TextEditingController(text: widget.nickname);
  }

  @override
  void dispose() {
    _nickController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colorScheme.primary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // --- Identity ---
          _SectionHeader(title: 'IDENTITY', colorScheme: colorScheme),
          _buildNicknameTile(theme, colorScheme),
          _buildCopyTile(
            icon: Icons.fingerprint,
            label: 'Peer ID',
            value: _peerId,
            theme: theme,
            colorScheme: colorScheme,
          ),
          _buildCopyTile(
            icon: Icons.key,
            label: 'Fingerprint',
            value: _fingerprint,
            theme: theme,
            colorScheme: colorScheme,
          ),

          const SizedBox(height: 16),

          // --- Appearance ---
          _SectionHeader(title: 'APPEARANCE', colorScheme: colorScheme),
          SwitchListTile(
            secondary: Icon(
              widget.isDark ? Icons.dark_mode : Icons.light_mode,
              color: colorScheme.primary,
              size: 20,
            ),
            title: Text(
              'Dark Mode',
              style: TextStyle(fontFamily: 'monospace', fontSize: 14),
            ),
            value: widget.isDark,
            activeColor: colorScheme.primary,
            onChanged: (_) => widget.onThemeToggle(),
          ),

          const SizedBox(height: 16),

          // --- Network ---
          _SectionHeader(title: 'NETWORK', colorScheme: colorScheme),
          _InfoTile(
            icon: Icons.bluetooth,
            label: 'BLE Status',
            value: 'Scanning',
            valueColor: colorScheme.primary,
            colorScheme: colorScheme,
          ),
          _InfoTile(
            icon: Icons.cloud_outlined,
            label: 'Relay',
            value: 'wss://relay.damus.io',
            colorScheme: colorScheme,
          ),
          _InfoTile(
            icon: Icons.cell_tower,
            label: 'Connected Peers',
            value: '0',
            colorScheme: colorScheme,
          ),

          const SizedBox(height: 16),

          // --- About ---
          _SectionHeader(title: 'ABOUT', colorScheme: colorScheme),
          _InfoTile(
            icon: Icons.info_outline,
            label: 'Version',
            value: '0.1.0',
            colorScheme: colorScheme,
          ),
          _InfoTile(
            icon: Icons.developer_board,
            label: 'Protocol',
            value: 'BitChat v2 + NIP-01',
            colorScheme: colorScheme,
          ),
          ListTile(
            leading: Icon(
              Icons.code,
              size: 20,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            title: Text(
              'Source Code',
              style: TextStyle(fontFamily: 'monospace', fontSize: 14),
            ),
            subtitle: Text(
              'github.com/nickshouse/bitchat',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: colorScheme.secondary,
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildNicknameTile(ThemeData theme, ColorScheme colorScheme) {
    if (_editing) {
      return ListTile(
        leading: Icon(Icons.person, size: 20, color: colorScheme.primary),
        title: TextField(
          controller: _nickController,
          autofocus: true,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
          decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: 4),
          ),
          onSubmitted: (val) {
            if (val.trim().isNotEmpty) {
              widget.onNicknameChanged(val.trim());
            }
            setState(() => _editing = false);
          },
        ),
        trailing: IconButton(
          icon: Icon(Icons.check, size: 18, color: colorScheme.primary),
          onPressed: () {
            final val = _nickController.text.trim();
            if (val.isNotEmpty) widget.onNicknameChanged(val);
            setState(() => _editing = false);
          },
        ),
      );
    }

    return ListTile(
      leading: Icon(Icons.person, size: 20, color: colorScheme.primary),
      title: Text(
        widget.nickname,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
      subtitle: Text(
        'Tap to change nickname',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          color: colorScheme.onSurface.withValues(alpha: 0.4),
        ),
      ),
      trailing: Icon(
        Icons.edit,
        size: 16,
        color: colorScheme.onSurface.withValues(alpha: 0.4),
      ),
      onTap: () => setState(() => _editing = true),
    );
  }

  Widget _buildCopyTile({
    required IconData icon,
    required String label,
    required String value,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        size: 20,
        color: colorScheme.onSurface.withValues(alpha: 0.5),
      ),
      title: Text(
        label,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
      ),
      subtitle: Text(
        value,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          color: colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      ),
      trailing: IconButton(
        icon: Icon(Icons.copy, size: 14, color: colorScheme.primary),
        onPressed: () {
          Clipboard.setData(ClipboardData(text: value));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Copied $label'),
              duration: const Duration(seconds: 1),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable section and info tiles
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.colorScheme});

  final String title;
  final ColorScheme colorScheme;

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
          color: colorScheme.onSurface.withValues(alpha: 0.4),
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.colorScheme,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final ColorScheme colorScheme;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(
        icon,
        size: 20,
        color: colorScheme.onSurface.withValues(alpha: 0.5),
      ),
      title: Text(
        label,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
      ),
      trailing: Text(
        value,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: valueColor ?? colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
