import 'package:flutter/material.dart';

import 'package:bitchat/services/identity_service.dart';
import 'package:bitchat/ui/fingerprint_screen.dart';
import 'package:bitchat/ui/peer_color.dart';

/// Contacts screen — list of known peers with trust badges, favorites, and
/// fingerprint verification access.
class ContactsScreen extends StatefulWidget {
  const ContactsScreen({
    super.key,
    required this.identityService,
    required this.myPublicKeyHex,
  });

  final IdentityService identityService;
  final String myPublicKeyHex;

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final contacts = widget.identityService.contacts;
    final blocked = widget.identityService.blockedPeers;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '📒 Contacts (${contacts.length})',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
        ),
      ),
      body: contacts.isEmpty && blocked.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.people_outline,
                    size: 48,
                    color: colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No contacts yet',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Start chatting to discover peers',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: colorScheme.onSurface.withValues(alpha: 0.3),
                    ),
                  ),
                ],
              ),
            )
          : ListView(
              children: [
                // Favorites section
                if (contacts.any((c) => c.isFavorite)) ...[
                  _SectionLabel('⭐ FAVORITES', colorScheme),
                  ...contacts
                      .where((c) => c.isFavorite)
                      .map((c) => _buildContactTile(c, isDark, colorScheme)),
                  const Divider(height: 1),
                ],

                // All contacts
                _SectionLabel('ALL CONTACTS', colorScheme),
                ...contacts.map(
                  (c) => _buildContactTile(c, isDark, colorScheme),
                ),

                // Blocked
                if (blocked.isNotEmpty) ...[
                  const Divider(height: 1),
                  _SectionLabel('🚫 BLOCKED', colorScheme),
                  ...blocked.map(
                    (c) => _buildContactTile(
                      c,
                      isDark,
                      colorScheme,
                      isBlocked: true,
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildContactTile(
    PeerIdentity peer,
    bool isDark,
    ColorScheme colorScheme, {
    bool isBlocked = false,
  }) {
    final peerColor = PeerColor.forNickname(peer.displayName, isDark: isDark);
    final trustIcon = _trustIcon(peer.trustLevel);
    final trustLabel = _trustLabel(peer.trustLevel);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: peerColor.withValues(alpha: 0.3),
        radius: 18,
        child: Text(
          peer.displayName[0].toUpperCase(),
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: peerColor,
          ),
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              peer.displayName,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isBlocked
                    ? colorScheme.onSurface.withValues(alpha: 0.4)
                    : colorScheme.onSurface,
                decoration: isBlocked ? TextDecoration.lineThrough : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (peer.isFavorite)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Text('⭐', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
      subtitle: Row(
        children: [
          Icon(trustIcon, size: 12, color: _trustColor(peer.trustLevel)),
          const SizedBox(width: 4),
          Text(
            trustLabel,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              color: _trustColor(peer.trustLevel),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            peer.shortFingerprint,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              color: colorScheme.onSurface.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
      trailing: PopupMenuButton<String>(
        itemBuilder: (ctx) => [
          PopupMenuItem(
            value: 'fingerprint',
            child: _menuItem(Icons.fingerprint, 'Verify Fingerprint'),
          ),
          PopupMenuItem(
            value: 'favorite',
            child: _menuItem(
              peer.isFavorite ? Icons.star : Icons.star_border,
              peer.isFavorite ? 'Remove Favorite' : 'Add Favorite',
            ),
          ),
          PopupMenuItem(
            value: 'petname',
            child: _menuItem(Icons.edit, 'Set Petname'),
          ),
          if (!isBlocked)
            PopupMenuItem(
              value: 'block',
              child: _menuItem(Icons.block, 'Block'),
            ),
          if (isBlocked)
            PopupMenuItem(
              value: 'unblock',
              child: _menuItem(Icons.check_circle_outline, 'Unblock'),
            ),
        ],
        onSelected: (action) => _handleAction(action, peer),
      ),
    );
  }

  Widget _menuItem(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
      ],
    );
  }

  void _handleAction(String action, PeerIdentity peer) {
    switch (action) {
      case 'fingerprint':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FingerprintScreen(
              myPublicKeyHex: widget.myPublicKeyHex,
              peerIdentity: peer,
              onVerify: () {
                setState(() => widget.identityService.verify(peer.fingerprint));
              },
              onUnverify: () {
                setState(
                  () => widget.identityService.unverify(peer.fingerprint),
                );
              },
            ),
          ),
        );
      case 'favorite':
        setState(() => widget.identityService.toggleFavorite(peer.fingerprint));
      case 'petname':
        _showPetnameDialog(peer);
      case 'block':
        setState(() => widget.identityService.block(peer.fingerprint));
      case 'unblock':
        setState(() => widget.identityService.unblock(peer.fingerprint));
    }
  }

  void _showPetnameDialog(PeerIdentity peer) {
    final controller = TextEditingController(text: peer.petname ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Set Petname',
          style: TextStyle(fontFamily: 'monospace', fontSize: 16),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
          decoration: const InputDecoration(
            hintText: 'Your name for this peer',
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim().isEmpty
                  ? null
                  : controller.text.trim();
              setState(
                () => widget.identityService.setPetname(peer.fingerprint, name),
              );
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  IconData _trustIcon(TrustLevel level) {
    switch (level) {
      case TrustLevel.unknown:
        return Icons.help_outline;
      case TrustLevel.casual:
        return Icons.handshake_outlined;
      case TrustLevel.trusted:
        return Icons.shield_outlined;
      case TrustLevel.verified:
        return Icons.verified_user;
    }
  }

  String _trustLabel(TrustLevel level) {
    switch (level) {
      case TrustLevel.unknown:
        return 'Unknown';
      case TrustLevel.casual:
        return 'Casual';
      case TrustLevel.trusted:
        return 'Trusted';
      case TrustLevel.verified:
        return 'Verified';
    }
  }

  Color _trustColor(TrustLevel level) {
    switch (level) {
      case TrustLevel.unknown:
        return Colors.grey;
      case TrustLevel.casual:
        return Colors.blue;
      case TrustLevel.trusted:
        return Colors.orange;
      case TrustLevel.verified:
        return Colors.green;
    }
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, this.colorScheme);

  final String label;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label,
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
