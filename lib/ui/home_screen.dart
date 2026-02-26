import 'dart:async';

import 'package:flutter/material.dart';
import 'package:bitchat/services/nostr_chat_service.dart';
import 'package:bitchat/ui/chat_screen.dart';
import 'package:bitchat/ui/peer_list_screen.dart';
import 'package:bitchat/ui/settings_screen.dart';

/// Main navigation shell with a drawer for channels and peers.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.onThemeToggle,
    required this.isDark,
  });

  final VoidCallback onThemeToggle;
  final bool isDark;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _currentChannel = '#general';
  String _nickname = 'anon';

  final List<String> _channels = ['#general', '#random', '#bitcoin', '#nostr'];

  // Nostr integration
  late NostrChatService _chatService;
  NostrConnectionStatus _connectionStatus = NostrConnectionStatus.disconnected;
  StreamSubscription<NostrConnectionStatus>? _statusSub;

  @override
  void initState() {
    super.initState();
    _chatService = NostrChatService(
      channelTag: _channelTagFromName(_currentChannel),
    );
    _initNostr();
  }

  Future<void> _initNostr() async {
    _statusSub = _chatService.statusStream.listen((status) {
      if (mounted) setState(() => _connectionStatus = status);
    });

    await _chatService.initialize(nickname: _nickname);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _chatService.dispose();
    super.dispose();
  }

  /// Convert display channel name to Nostr tag.
  String _channelTagFromName(String channel) =>
      'bitchat-${channel.replaceFirst('#', '')}';

  void _switchChannel(String channel) {
    setState(() => _currentChannel = channel);
    _chatService.switchChannel(_channelTagFromName(channel));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.tag, size: 16, color: colorScheme.primary),
            const SizedBox(width: 4),
            Text(_currentChannel),
            const Spacer(),
            _ConnectionStatusChip(
              status: _connectionStatus,
              colorScheme: colorScheme,
            ),
          ],
        ),
        leading: Builder(
          builder: (context) => IconButton(
            icon: Icon(Icons.menu, color: colorScheme.primary),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      drawer: _buildDrawer(theme, colorScheme),
      body: ChatScreen(
        channel: _currentChannel,
        nickname: _nickname,
        chatService: _chatService,
        onNicknameChanged: (nick) {
          setState(() => _nickname = nick);
          _chatService.setNickname(nick);
        },
      ),
    );
  }

  Widget _buildDrawer(ThemeData theme, ColorScheme colorScheme) {
    return Drawer(
      backgroundColor: colorScheme.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Header ---
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: colorScheme.primary.withValues(alpha: 0.2),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lock, size: 20, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'bitchat',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _chatService.isInitialized
                        ? '$_nickname • ${_chatService.shortPubKey}'
                        : 'Connecting...',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),

            // --- Channels ---
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'CHANNELS',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                  letterSpacing: 1.5,
                ),
              ),
            ),
            ..._channels.map(
              (ch) => _ChannelTile(
                channel: ch,
                isSelected: ch == _currentChannel,
                colorScheme: colorScheme,
                onTap: () {
                  _switchChannel(ch);
                  Navigator.pop(context);
                },
              ),
            ),

            const Spacer(),

            // --- Actions ---
            Divider(
              color: colorScheme.primary.withValues(alpha: 0.15),
              height: 1,
            ),
            _DrawerAction(
              icon: Icons.people_outline,
              label: 'Peers',
              colorScheme: colorScheme,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PeerListScreen()),
                );
              },
            ),
            _DrawerAction(
              icon: Icons.settings_outlined,
              label: 'Settings',
              colorScheme: colorScheme,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SettingsScreen(
                      nickname: _nickname,
                      isDark: widget.isDark,
                      onThemeToggle: widget.onThemeToggle,
                      onNicknameChanged: (nick) {
                        setState(() => _nickname = nick);
                        _chatService.setNickname(nick);
                      },
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Drawer sub-widgets
// ---------------------------------------------------------------------------

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required this.channel,
    required this.isSelected,
    required this.colorScheme,
    required this.onTap,
  });

  final String channel;
  final bool isSelected;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      selected: isSelected,
      selectedTileColor: colorScheme.primary.withValues(alpha: 0.1),
      leading: Icon(
        Icons.tag,
        size: 16,
        color: isSelected
            ? colorScheme.primary
            : colorScheme.onSurface.withValues(alpha: 0.4),
      ),
      title: Text(
        channel.replaceFirst('#', ''),
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 14,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected
              ? colorScheme.primary
              : colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
      onTap: onTap,
    );
  }
}

class _DrawerAction extends StatelessWidget {
  const _DrawerAction({
    required this.icon,
    required this.label,
    required this.colorScheme,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(
        icon,
        size: 20,
        color: colorScheme.onSurface.withValues(alpha: 0.6),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 14,
          color: colorScheme.onSurface.withValues(alpha: 0.8),
        ),
      ),
      onTap: onTap,
    );
  }
}

class _ConnectionStatusChip extends StatelessWidget {
  const _ConnectionStatusChip({
    required this.status,
    required this.colorScheme,
  });

  final NostrConnectionStatus status;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final Color dotColor;
    final String label;

    switch (status) {
      case NostrConnectionStatus.connected:
        dotColor = colorScheme.primary;
        label = 'Online';
      case NostrConnectionStatus.connecting:
        dotColor = const Color(0xFFFFB000);
        label = 'Connecting';
      case NostrConnectionStatus.disconnected:
        dotColor = Colors.redAccent;
        label = 'Offline';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: dotColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              color: dotColor,
            ),
          ),
        ],
      ),
    );
  }
}
