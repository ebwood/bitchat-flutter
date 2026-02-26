import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:geolocator/geolocator.dart';

import 'package:flutter/material.dart';
import 'package:bitchat/nostr/geohash.dart';
import 'package:bitchat/services/identity_service.dart';
import 'package:bitchat/services/nostr_chat_service.dart';
import 'package:bitchat/services/private_chat_service.dart';
import 'package:bitchat/ui/chat_screen.dart';
import 'package:bitchat/ui/contacts_screen.dart';
import 'package:bitchat/ui/debug_panel.dart';
import 'package:bitchat/ui/dm_screen.dart';
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
  String _currentChannel = '#loading...';
  String _nickname = 'anon';
  String? _myGeohash; // Auto-computed from IP location
  bool _isMeshMode = false; // true = Mesh (BLE), false = Location (geohash)

  // Separate channel lists for each mode
  List<String> _meshChannels = ['#general', '#random', '#bitcoin', '#nostr'];
  List<String> _locationChannels = ['#loading...'];

  List<String> get _channels => _isMeshMode ? _meshChannels : _locationChannels;

  // Nostr integration
  late NostrChatService _chatService;
  PrivateChatService? _privateChatService;
  final IdentityService _identityService = IdentityService();
  NostrConnectionStatus _connectionStatus = NostrConnectionStatus.disconnected;
  StreamSubscription<NostrConnectionStatus>? _statusSub;

  @override
  void initState() {
    super.initState();
    // Start with placeholder, then upgrade to geo-channel
    _chatService = NostrChatService(channelTag: 'bitchat-general');
    _initNostr();
  }

  Future<void> _initNostr() async {
    _statusSub = _chatService.statusStream.listen((status) {
      if (mounted) setState(() => _connectionStatus = status);
    });

    // Get location and compute geohash
    try {
      final (lat, lon) = await _fetchLocation();
      final fullGeohash = Geohash.encode(lat, lon, precision: 7);
      _myGeohash = fullGeohash.substring(0, 5); // City level
      debugPrint('[bitchat] Geohash: $_myGeohash (lat=$lat, lon=$lon)');

      // Build location channels at different precision levels (like original)
      _locationChannels = [
        // Region (precision 2) — widest
        '🌍 Region • #${fullGeohash.substring(0, 2)}',
        // Province (precision 4)
        '🗺️ Province • #${fullGeohash.substring(0, 4)}',
        // City (precision 5) — default
        '🏙️ City • #${fullGeohash.substring(0, 5)}',
        // Neighborhood (precision 6)
        '🏘️ Neighborhood • #${fullGeohash.substring(0, 6)}',
        // Block (precision 7)
        '🏠 Block • #${fullGeohash.substring(0, 7)}',
      ];
      _currentChannel = _locationChannels[2]; // Default to City

      // Create geo-based chat service
      final geoService = await NostrChatService.fromLocation(
        latitude: lat,
        longitude: lon,
        channelTag: _myGeohash!,
      );
      _chatService = geoService;

      // Log selected relays for debugging interop
      final relayUrls = _chatService.relayManager.relayUrls;
      debugPrint('[bitchat] Connected to ${relayUrls.length} relays:');
      for (final url in relayUrls) {
        debugPrint('[bitchat]   $url');
      }

      _statusSub?.cancel();
      _statusSub = _chatService.statusStream.listen((status) {
        if (mounted) setState(() => _connectionStatus = status);
      });
    } catch (e) {
      debugPrint('[bitchat] Geo init failed: $e');
      _locationChannels = ['#general'];
      _currentChannel = '#general';
    }

    await _chatService.initialize(nickname: _nickname);

    // Initialize private DM service
    if (_chatService.isInitialized) {
      _privateChatService = PrivateChatService(
        relayManager: _chatService.relayManager,
        privateKeyHex: _chatService.privateKeyHex,
        publicKeyHex: _chatService.publicKeyHex,
        nickname: _nickname,
      );
      _privateChatService!.subscribe();
    }

    if (mounted) setState(() {});
  }

  (double, double)? _cachedLocation;

  /// Get device location — GPS on iOS/Android/macOS, IP fallback.
  Future<(double, double)> _fetchLocation() async {
    if (_cachedLocation != null) return _cachedLocation!;

    // Try GPS/CoreLocation first (matches original bitchat behavior)
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      debugPrint('[bitchat] Location service enabled: $serviceEnabled');
      if (serviceEnabled) {
        LocationPermission perm = await Geolocator.checkPermission();
        debugPrint('[bitchat] Location permission: $perm');
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
          debugPrint('[bitchat] After request: $perm');
        }
        if (perm == LocationPermission.whileInUse ||
            perm == LocationPermission.always) {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low,
              timeLimit: Duration(seconds: 10),
            ),
          );
          debugPrint(
            '[bitchat] GPS location: ${pos.latitude}, ${pos.longitude}',
          );
          _cachedLocation = (pos.latitude, pos.longitude);
          return _cachedLocation!;
        } else {
          debugPrint(
            '[bitchat] Location permission denied, falling back to IP',
          );
        }
      }
    } catch (e) {
      debugPrint('[bitchat] GPS failed: $e, falling back to IP');
    }

    // IP-based fallback
    try {
      final uri = Uri.parse('https://ipapi.co/json/');
      final client = HttpClient();
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 5));
      request.headers.set('User-Agent', 'bitchat-flutter/1.0');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final lat = (json['latitude'] as num).toDouble();
      final lon = (json['longitude'] as num).toDouble();
      debugPrint('[bitchat] IP location: $lat, $lon');
      _cachedLocation = (lat, lon);
      client.close();
      return _cachedLocation!;
    } catch (e) {
      debugPrint('[bitchat] IP fallback also failed: $e');
      return (39.9, -77.0);
    }
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _privateChatService?.dispose();
    _chatService.dispose();
    super.dispose();
  }

  /// Convert display channel name to Nostr tag.
  String _channelTagFromName(String channel) =>
      'bitchat-${channel.replaceFirst('#', '')}';

  /// Extract geohash from location channel display name.
  /// e.g. '🏙️ City • #ws0bp' → 'ws0bp'
  String _geohashFromChannel(String channel) {
    final hashIdx = channel.indexOf('#');
    if (hashIdx >= 0) return channel.substring(hashIdx + 1);
    return channel.replaceFirst('#', '');
  }

  void _switchChannel(String channel) {
    setState(() => _currentChannel = channel);
    if (_isMeshMode) {
      _chatService.switchChannel(_channelTagFromName(channel));
    } else {
      _chatService.switchChannel(_geohashFromChannel(channel));
    }
  }

  /// Switch between Mesh (BLE) and Location (GPS geohash) modes.
  void _switchMode(bool meshMode) {
    if (_isMeshMode == meshMode) return;
    setState(() {
      _isMeshMode = meshMode;
      if (meshMode) {
        _currentChannel = _meshChannels.first;
        _chatService.useGeohashMode = false;
        _chatService.switchChannel(_channelTagFromName(_currentChannel));
      } else {
        // Default to City level (index 2)
        final idx = _locationChannels.length > 2 ? 2 : 0;
        _currentChannel = _locationChannels.isNotEmpty
            ? _locationChannels[idx]
            : '#general';
        _chatService.useGeohashMode = true;
        _chatService.switchChannel(_geohashFromChannel(_currentChannel));
      }
    });
  }

  /// Show dialog to enter a peer's public key and start a DM.
  void _startDmDialog(BuildContext context) {
    if (_privateChatService == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Nostr not connected yet')));
      return;
    }

    final pubkeyController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New DM'),
        content: TextField(
          controller: pubkeyController,
          decoration: const InputDecoration(
            labelText: 'Peer public key (hex)',
            hintText: '64 character hex...',
            border: OutlineInputBorder(),
          ),
          maxLength: 64,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final pubkey = pubkeyController.text.trim();
              if (pubkey.length == 64) {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DmScreen(
                      privateChatService: _privateChatService!,
                      peerPubKey: pubkey,
                      ownNickname: _nickname,
                    ),
                  ),
                );
              }
            },
            child: const Text('Start Chat'),
          ),
        ],
      ),
    );
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

            // --- Mode Switcher ---
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    label: Text('Mesh'),
                    icon: Icon(Icons.bluetooth, size: 16),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text('Location'),
                    icon: Icon(Icons.location_on, size: 16),
                  ),
                ],
                selected: {_isMeshMode},
                onSelectionChanged: (val) {
                  _switchMode(val.first);
                },
                style: SegmentedButton.styleFrom(
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            // --- Channels ---
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Text(
                _isMeshMode ? 'MESH CHANNELS' : 'LOCATION CHANNELS',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                  letterSpacing: 1.5,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: _channels
                    .map(
                      (ch) => _ChannelTile(
                        channel: ch,
                        isSelected: ch == _currentChannel,
                        colorScheme: colorScheme,
                        onTap: () {
                          _switchChannel(ch);
                          Navigator.pop(context);
                        },
                      ),
                    )
                    .toList(),
              ),
            ),

            // --- Actions ---
            Divider(
              color: colorScheme.primary.withValues(alpha: 0.15),
              height: 1,
            ),
            _DrawerAction(
              icon: Icons.mail_lock_outlined,
              label: 'Direct Messages',
              colorScheme: colorScheme,
              onTap: () {
                Navigator.pop(context);
                _startDmDialog(context);
              },
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
              icon: Icons.contacts_outlined,
              label: 'Contacts',
              colorScheme: colorScheme,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ContactsScreen(
                      identityService: _identityService,
                      myPublicKeyHex: _chatService.publicKeyHex,
                    ),
                  ),
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
            _DrawerAction(
              icon: Icons.bug_report_outlined,
              label: 'Debug',
              colorScheme: colorScheme,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DebugPanel(
                      relayStatus: _connectionStatus.name,
                      publicKeyHex: _chatService.publicKeyHex,
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
