import 'dart:async';

import 'package:flutter/material.dart';

import 'package:bitchat/services/private_chat_service.dart';

/// Private DM (Direct Message) chat screen.
///
/// One-on-one encrypted conversation with a specific peer via NIP-04.
class DmScreen extends StatefulWidget {
  const DmScreen({
    super.key,
    required this.privateChatService,
    required this.peerPubKey,
    this.peerNickname,
    this.ownNickname = 'me',
  });

  final PrivateChatService privateChatService;
  final String peerPubKey;
  final String? peerNickname;
  final String ownNickname;

  @override
  State<DmScreen> createState() => _DmScreenState();
}

class _DmScreenState extends State<DmScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  final _messages = <DirectMessage>[];
  StreamSubscription<DirectMessage>? _sub;

  String get _peerDisplay =>
      widget.peerNickname ??
      (widget.peerPubKey.length >= 12
          ? '${widget.peerPubKey.substring(0, 6)}..${widget.peerPubKey.substring(widget.peerPubKey.length - 4)}'
          : widget.peerPubKey);

  @override
  void initState() {
    super.initState();

    // Load existing conversation
    _messages.addAll(
      widget.privateChatService.getConversation(widget.peerPubKey),
    );

    // Listen for new DMs from this peer
    _sub = widget.privateChatService.messages.listen((dm) {
      if (dm.senderPubKey == widget.peerPubKey || dm.isOwnMessage) {
        setState(() => _messages.add(dm));
        _scrollToBottom();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();

    widget.privateChatService.sendMessage(widget.peerPubKey, text);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.lock, size: 16, color: colorScheme.primary),
            const SizedBox(width: 6),
            Text('DM: $_peerDisplay'),
          ],
        ),
        backgroundColor: colorScheme.surface,
      ),
      body: Column(
        children: [
          // ---- Encrypted notice ----
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
            color: colorScheme.primary.withValues(alpha: 0.08),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.shield,
                  size: 14,
                  color: colorScheme.primary.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 4),
                Text(
                  'NIP-04 Encrypted',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.primary.withValues(alpha: 0.6),
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),

          // ---- Message list ----
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Text(
                      'No messages yet.\nSend the first encrypted message!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.4),
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) =>
                        _buildMessage(_messages[i], theme, colorScheme),
                  ),
          ),

          // ---- Input bar ----
          Divider(height: 1, color: colorScheme.surface),
          Container(
            color: colorScheme.surface,
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 16,
                    color: colorScheme.primary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      style: theme.textTheme.bodyMedium,
                      decoration: InputDecoration(
                        hintText: 'Encrypted message...',
                        border: InputBorder.none,
                        filled: false,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onSubmitted: (_) => _send(),
                      textInputAction: TextInputAction.send,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.send, color: colorScheme.primary),
                    onPressed: _send,
                    iconSize: 20,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(
    DirectMessage dm,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final time =
        '${dm.timestamp.hour.toString().padLeft(2, '0')}:${dm.timestamp.minute.toString().padLeft(2, '0')}';
    final isSelf = dm.isOwnMessage;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Align(
        alignment: isSelf ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelf
                ? colorScheme.primary.withValues(alpha: 0.15)
                : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: isSelf
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Text(
                dm.plaintext,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${isSelf ? widget.ownNickname : dm.senderNickname} · $time',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  color: colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
