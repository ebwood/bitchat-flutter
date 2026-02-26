import 'dart:async';

import 'package:flutter/material.dart';

import 'package:bitchat/models/bitchat_message.dart';
import 'package:bitchat/services/command_processor.dart';
import 'package:bitchat/services/nostr_chat_service.dart';

/// Terminal-style chat screen for BitChat.
///
/// Features:
/// - Scrolling message list with timestamp + sender formatting
/// - IRC command input field with autocomplete suggestions
/// - System message display (joins, leaves, commands)
/// - Live send/receive via NostrChatService
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    this.channel = '#general',
    this.nickname = 'anon',
    this.chatService,
    this.onNicknameChanged,
  });

  final String channel;
  final String nickname;
  final NostrChatService? chatService;
  final ValueChanged<String>? onNicknameChanged;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messages = <_DisplayMessage>[];
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  late String _nickname;
  String? _lastChannel;
  bool _showSuggestions = false;
  List<String> _filteredCommands = [];

  StreamSubscription<ChatMessage>? _messageSub;

  static const _allCommands = [
    '/help',
    '/nick',
    '/join',
    '/msg',
    '/clear',
    '/slap',
    '/me',
    '/whois',
    '/peers',
    '/fingerprint',
  ];

  @override
  void initState() {
    super.initState();
    _nickname = widget.nickname;
    _lastChannel = widget.channel;
    _addSystemMessage('Welcome to bitchat! 🔐');
    _addSystemMessage('Type /help for available commands.');
    _addSystemMessage('Joined ${widget.channel}');

    _controller.addListener(_onInputChanged);

    // Listen for incoming Nostr messages
    _messageSub = widget.chatService?.messages.listen(_onNostrMessage);
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.channel != _lastChannel) {
      _addSystemMessage('Joined ${widget.channel}');
      _lastChannel = widget.channel;
    }
    if (widget.nickname != _nickname) {
      _nickname = widget.nickname;
    }
    // Re-subscribe if chat service changed
    if (widget.chatService != oldWidget.chatService) {
      _messageSub?.cancel();
      _messageSub = widget.chatService?.messages.listen(_onNostrMessage);
    }
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _controller.removeListener(_onInputChanged);
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onNostrMessage(ChatMessage msg) {
    _addSystemMessage(null); // force a rebuild
    setState(() {
      _messages.add(
        _DisplayMessage.remote(
          sender: msg.senderNickname,
          content: msg.text,
          timestamp: msg.timestamp,
        ),
      );
    });
    _scrollToBottom();
  }

  void _onInputChanged() {
    final text = _controller.text;
    if (text.startsWith('/') && !text.contains(' ')) {
      final matches = _allCommands
          .where((c) => c.startsWith(text.toLowerCase()))
          .toList();
      setState(() {
        _showSuggestions = matches.isNotEmpty && text.length > 1;
        _filteredCommands = matches;
      });
    } else {
      setState(() => _showSuggestions = false);
    }
  }

  void _addSystemMessage(String? text) {
    if (text == null) return;
    setState(() {
      _messages.add(_DisplayMessage.system(text));
    });
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

  void _handleSubmit(String text) {
    if (text.trim().isEmpty) return;
    _controller.clear();
    setState(() => _showSuggestions = false);

    // Try parsing as command
    final cmd = CommandProcessor.parse(text);
    if (cmd != null) {
      _handleCommand(cmd);
      return;
    }

    // Regular message — display locally
    final msg = BitchatMessage(
      sender: _nickname,
      content: text.trim(),
      timestamp: DateTime.now(),
      isRelay: false,
    );
    setState(() {
      _messages.add(_DisplayMessage.chat(msg));
    });
    _scrollToBottom();

    // Send via Nostr relay
    widget.chatService?.sendMessage(text.trim(), senderNickname: _nickname);
  }

  void _handleCommand(CommandResult cmd) {
    switch (cmd.type) {
      case CommandType.joinChannel:
        break;
      case CommandType.clear:
        setState(() => _messages.clear());
        break;
      case CommandType.nick:
        if (cmd.message != null) {
          _nickname = cmd.message!;
          widget.onNicknameChanged?.call(_nickname);
        }
        break;
      case CommandType.privateMessage:
        if (cmd.targetUser != null && cmd.message != null) {
          final msg = BitchatMessage(
            sender: _nickname,
            content: cmd.message!,
            timestamp: DateTime.now(),
            isRelay: false,
            isPrivate: true,
            recipientNickname: cmd.targetUser,
          );
          setState(() {
            _messages.add(_DisplayMessage.chat(msg));
          });
          _scrollToBottom();
        }
        break;
      case CommandType.slap:
        if (cmd.message != null) {
          final msg = BitchatMessage(
            sender: _nickname,
            content: '* $_nickname ${cmd.message}',
            timestamp: DateTime.now(),
            isRelay: false,
          );
          setState(() {
            _messages.add(_DisplayMessage.chat(msg));
          });
          _scrollToBottom();
        }
        break;
      default:
        break;
    }

    if (cmd.systemMessage != null) {
      _addSystemMessage(cmd.systemMessage!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        // --- Message list ---
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final msg = _messages[index];
              return _buildMessageRow(msg, theme, colorScheme);
            },
          ),
        ),

        // --- Command suggestions ---
        if (_showSuggestions)
          Container(
            height: 36,
            color: colorScheme.surface,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _filteredCommands.map((cmd) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    label: Text(
                      cmd,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: colorScheme.primary,
                      ),
                    ),
                    backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
                    side: BorderSide(
                      color: colorScheme.primary.withValues(alpha: 0.3),
                    ),
                    onPressed: () {
                      _controller.text = '$cmd ';
                      _controller.selection = TextSelection.fromPosition(
                        TextPosition(offset: _controller.text.length),
                      );
                      _focusNode.requestFocus();
                    },
                  ),
                );
              }).toList(),
            ),
          ),

        // --- Divider ---
        Divider(height: 1, color: colorScheme.surface),

        // --- Input ---
        Container(
          color: colorScheme.surface,
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Text(
                  '> ',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 16,
                    color: colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    style: theme.textTheme.bodyMedium,
                    decoration: InputDecoration(
                      hintText: 'Type a message or /command...',
                      border: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onSubmitted: _handleSubmit,
                    textInputAction: TextInputAction.send,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send, color: colorScheme.primary),
                  onPressed: () => _handleSubmit(_controller.text),
                  iconSize: 20,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMessageRow(
    _DisplayMessage msg,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    if (msg.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          '  *** ${msg.systemText}',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: colorScheme.tertiary.withValues(alpha: 0.8),
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    // Remote Nostr message
    if (msg.isRemote) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: RichText(
          text: TextSpan(
            style: theme.textTheme.bodyMedium,
            children: [
              TextSpan(
                text: '[${_formatTime(msg.remoteTimestamp!)}] ',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
              TextSpan(
                text: '<${msg.remoteSender}> ',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.secondary,
                ),
              ),
              TextSpan(
                text: msg.remoteContent,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final chatMsg = msg.chatMessage!;
    final isSelf = chatMsg.sender == _nickname;
    final isPrivate = chatMsg.isPrivate;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: RichText(
        text: TextSpan(
          style: theme.textTheme.bodyMedium,
          children: [
            TextSpan(
              text: '[${chatMsg.formattedTimestamp}] ',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
            if (isPrivate)
              const TextSpan(text: '🔒 ', style: TextStyle(fontSize: 11)),
            TextSpan(
              text: '<${chatMsg.sender}> ',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isSelf ? colorScheme.primary : colorScheme.secondary,
              ),
            ),
            TextSpan(
              text: chatMsg.content,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: isPrivate ? colorScheme.tertiary : colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime t) {
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}

// ---------------------------------------------------------------------------
// Display message wrapper
// ---------------------------------------------------------------------------

class _DisplayMessage {
  _DisplayMessage.system(this.systemText)
    : chatMessage = null,
      remoteSender = null,
      remoteContent = null,
      remoteTimestamp = null;

  _DisplayMessage.chat(this.chatMessage)
    : systemText = null,
      remoteSender = null,
      remoteContent = null,
      remoteTimestamp = null;

  _DisplayMessage.remote({
    required String sender,
    required String content,
    required DateTime timestamp,
  }) : remoteSender = sender,
       remoteContent = content,
       remoteTimestamp = timestamp,
       chatMessage = null,
       systemText = null;

  final BitchatMessage? chatMessage;
  final String? systemText;
  final String? remoteSender;
  final String? remoteContent;
  final DateTime? remoteTimestamp;

  bool get isSystem => systemText != null;
  bool get isRemote => remoteSender != null;
}
