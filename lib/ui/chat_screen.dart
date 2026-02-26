import 'dart:async';

import 'package:flutter/material.dart';

import 'package:bitchat/models/bitchat_message.dart';
import 'package:bitchat/services/command_processor.dart';
import 'package:bitchat/services/image_message_service.dart';
import 'package:bitchat/services/message_store.dart';
import 'package:bitchat/services/nostr_chat_service.dart';
import 'package:bitchat/services/rate_limiter.dart';
import 'package:bitchat/services/voice_note_service.dart';
import 'package:bitchat/ui/message_formatter.dart';
import 'package:bitchat/ui/peer_color.dart';
import 'package:bitchat/ui/widgets/image_bubble.dart';
import 'package:bitchat/ui/widgets/voice_note_bubble.dart';

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
  final _imageService = ImageMessageService();
  final _voiceService = VoiceNoteService();
  final _rateLimiter = RateLimiter();

  late String _nickname;
  String? _lastChannel;
  bool _showSuggestions = false;
  List<String> _filteredCommands = [];
  bool _isSendingImage = false;
  bool _isRecording = false;

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
    _addSystemMessage('Welcome to bitchat! \u{1F510}');
    _addSystemMessage('Type /help for available commands.');
    _addSystemMessage('Joined ${widget.channel}');

    _controller.addListener(_onInputChanged);

    // Load persisted history then subscribe to live messages
    _loadHistory();
    _messageSub = widget.chatService?.messages.listen(_onNostrMessage);
  }

  /// Load recent messages from SQLite for the current channel.
  Future<void> _loadHistory() async {
    try {
      await MessageStore.instance.initialize();
      final stored = await MessageStore.instance.loadMessages(
        widget.channel,
        limit: 50,
      );
      if (stored.isNotEmpty && mounted) {
        setState(() {
          for (final msg in stored) {
            if (msg.isImage) {
              _messages.add(
                _DisplayMessage.image(
                  sender: msg.senderNickname,
                  base64Data: msg.imageBase64!,
                  timestamp: msg.timestamp,
                  width: msg.imageWidth,
                  height: msg.imageHeight,
                  isOwn: msg.isOwnMessage,
                ),
              );
            } else {
              _messages.add(
                _DisplayMessage.remote(
                  sender: msg.senderNickname,
                  content: msg.text,
                  timestamp: msg.timestamp,
                ),
              );
            }
          }
        });
        _addSystemMessage(
          '\u{1F4C2} Loaded ${stored.length} messages from history',
        );
        _scrollToBottom();
      }
    } catch (_) {
      // SQLite might not be available in tests — continue gracefully
    }
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
    _voiceService.dispose();
    super.dispose();
  }

  void _onNostrMessage(ChatMessage msg) {
    setState(() {
      if (msg.isImage) {
        _messages.add(
          _DisplayMessage.image(
            sender: msg.senderNickname,
            base64Data: msg.imageBase64!,
            timestamp: msg.timestamp,
            width: msg.imageWidth,
            height: msg.imageHeight,
          ),
        );
      } else if (msg.isVoice) {
        _messages.add(
          _DisplayMessage.voice(
            sender: msg.senderNickname,
            base64Data: msg.voiceBase64!,
            timestamp: msg.timestamp,
            durationSeconds: msg.voiceDuration ?? 0,
            isOwn: msg.isOwnMessage,
          ),
        );
      } else {
        _messages.add(
          _DisplayMessage.remote(
            sender: msg.senderNickname,
            content: msg.text,
            timestamp: msg.timestamp,
          ),
        );
      }
    });
    _scrollToBottom();
    // Persist received message
    _persistMessage(msg);
  }

  /// Save a message to local storage (fire-and-forget).
  void _persistMessage(ChatMessage msg) {
    MessageStore.instance.saveMessage(msg).then((_) {}, onError: (_) {});
  }

  Future<void> _pickAndSendImage({bool fromCamera = false}) async {
    if (_isSendingImage) return;
    setState(() => _isSendingImage = true);

    try {
      final payload = fromCamera
          ? await _imageService.pickFromCamera()
          : await _imageService.pickFromGallery();

      if (payload == null) {
        setState(() => _isSendingImage = false);
        return;
      }

      // Show local preview immediately
      setState(() {
        _messages.add(
          _DisplayMessage.image(
            sender: _nickname,
            base64Data: payload.base64Data,
            timestamp: DateTime.now(),
            width: payload.width,
            height: payload.height,
            isOwn: true,
          ),
        );
      });
      _scrollToBottom();

      // Send via Nostr
      widget.chatService?.sendImageMessage(
        payload.base64Data,
        senderNickname: _nickname,
        width: payload.width,
        height: payload.height,
      );

      // Persist sent image
      _persistMessage(
        ChatMessage(
          text: '[Image]',
          senderNickname: _nickname,
          senderPubKey: widget.chatService?.publicKeyHex ?? '',
          timestamp: DateTime.now(),
          channel: widget.channel,
          isOwnMessage: true,
          messageType: MessageType.image,
          imageBase64: payload.base64Data,
          imageWidth: payload.width,
          imageHeight: payload.height,
        ),
      );

      _addSystemMessage(
        '📷 Image sent (${(payload.sizeBytes / 1024).toStringAsFixed(1)}KB)',
      );
    } catch (e) {
      _addSystemMessage('❌ Failed to send image: $e');
    } finally {
      setState(() => _isSendingImage = false);
    }
  }

  /// Toggle voice recording — start on first tap, stop & send on second.
  void _toggleVoiceRecording() async {
    if (_isRecording) {
      // Stop recording and send
      setState(() => _isRecording = false);
      final payload = await _voiceService.stopRecording();
      if (payload == null) {
        _addSystemMessage('❌ Voice recording failed');
        return;
      }

      // Add to local display
      setState(() {
        _messages.add(
          _DisplayMessage.voice(
            sender: _nickname,
            base64Data: payload.base64Data,
            timestamp: DateTime.now(),
            durationSeconds: payload.durationSeconds,
            isOwn: true,
          ),
        );
      });
      _scrollToBottom();

      // Send via Nostr
      widget.chatService?.sendVoiceMessage(
        payload.base64Data,
        senderNickname: _nickname,
        duration: payload.durationSeconds,
      );

      // Persist
      _persistMessage(
        ChatMessage(
          text: '[Voice Note]',
          senderNickname: _nickname,
          senderPubKey: widget.chatService?.publicKeyHex ?? '',
          timestamp: DateTime.now(),
          channel: widget.channel,
          isOwnMessage: true,
          messageType: MessageType.voice,
          voiceBase64: payload.base64Data,
          voiceDuration: payload.durationSeconds,
        ),
      );

      _addSystemMessage(
        '🎤 Voice note sent (${payload.durationSeconds.toStringAsFixed(1)}s, '
        '${(payload.sizeBytes / 1024).toStringAsFixed(1)}KB)',
      );
    } else {
      // Start recording
      final path = await _voiceService.startRecording();
      if (path != null) {
        setState(() => _isRecording = true);
        _addSystemMessage('🎤 Recording... tap mic again to stop');
      } else {
        _addSystemMessage('❌ Microphone permission denied');
      }
    }
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

    // Input validation
    final validation = InputValidator.validateMessage(text.trim());
    if (!validation.isValid) {
      _addSystemMessage('⚠️ ${validation.error}');
      return;
    }

    _controller.clear();
    setState(() => _showSuggestions = false);

    // Try parsing as command
    final cmd = CommandProcessor.parse(text);
    if (cmd != null) {
      _handleCommand(cmd);
      return;
    }

    // Rate limiting
    if (!_rateLimiter.tryConsume(widget.channel)) {
      final cd = _rateLimiter.remainingCooldown(widget.channel);
      final secs = cd?.inSeconds ?? 3;
      _addSystemMessage('⏳ Slow down! Wait ${secs}s before sending again.');
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

    // Persist sent message
    _persistMessage(
      ChatMessage(
        text: text.trim(),
        senderNickname: _nickname,
        senderPubKey: widget.chatService?.publicKeyHex ?? '',
        timestamp: msg.timestamp,
        channel: widget.channel,
        isOwnMessage: true,
      ),
    );
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
                // Image picker button
                _isSendingImage
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : PopupMenuButton<String>(
                        icon: Icon(
                          Icons.add_photo_alternate_outlined,
                          color: colorScheme.primary,
                          size: 20,
                        ),
                        padding: EdgeInsets.zero,
                        onSelected: (value) {
                          if (value == 'gallery') {
                            _pickAndSendImage();
                          } else {
                            _pickAndSendImage(fromCamera: true);
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'gallery',
                            child: Row(
                              children: [
                                Icon(Icons.photo_library, size: 18),
                                SizedBox(width: 8),
                                Text('Gallery'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'camera',
                            child: Row(
                              children: [
                                Icon(Icons.camera_alt, size: 18),
                                SizedBox(width: 8),
                                Text('Camera'),
                              ],
                            ),
                          ),
                        ],
                      ),
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
                  icon: Icon(
                    _isRecording ? Icons.stop_circle : Icons.mic_none,
                    color: _isRecording ? Colors.red : colorScheme.primary,
                  ),
                  onPressed: _toggleVoiceRecording,
                  iconSize: 20,
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

    // Image message
    if (msg.isImage) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: msg.imageIsOwn
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(
              '[${_formatTime(msg.imageTimestamp!)}] <${msg.imageSender}>',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 2),
            ImageBubble(
              base64Data: msg.imageBase64!,
              width: msg.imageWidth,
              height: msg.imageHeight,
              isOwnMessage: msg.imageIsOwn,
            ),
          ],
        ),
      );
    }

    // Voice message
    if (msg.isVoice) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '[${_formatTime(msg.voiceTimestamp!)}] <${msg.voiceSender}> 🎤',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 2),
            VoiceNoteBubble(
              base64Data: msg.voiceBase64!,
              durationSeconds: msg.voiceDuration,
              isOwn: msg.voiceIsOwn,
            ),
          ],
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
                  color: PeerColor.forNickname(
                    msg.remoteSender!,
                    isDark: theme.brightness == Brightness.dark,
                  ),
                ),
              ),
              ...MessageFormatter.format(
                msg.remoteContent ?? '',
                baseStyle: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: colorScheme.onSurface,
                ),
                codeBackground: colorScheme.surfaceContainerHighest,
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
      remoteTimestamp = null,
      imageBase64 = null,
      imageSender = null,
      imageTimestamp = null,
      imageWidth = null,
      imageHeight = null,
      imageIsOwn = false,
      voiceBase64 = null,
      voiceSender = null,
      voiceTimestamp = null,
      voiceDuration = 0,
      voiceIsOwn = false;

  _DisplayMessage.chat(this.chatMessage)
    : systemText = null,
      remoteSender = null,
      remoteContent = null,
      remoteTimestamp = null,
      imageBase64 = null,
      imageSender = null,
      imageTimestamp = null,
      imageWidth = null,
      imageHeight = null,
      imageIsOwn = false,
      voiceBase64 = null,
      voiceSender = null,
      voiceTimestamp = null,
      voiceDuration = 0,
      voiceIsOwn = false;

  _DisplayMessage.remote({
    required String sender,
    required String content,
    required DateTime timestamp,
  }) : remoteSender = sender,
       remoteContent = content,
       remoteTimestamp = timestamp,
       chatMessage = null,
       systemText = null,
       imageBase64 = null,
       imageSender = null,
       imageTimestamp = null,
       imageWidth = null,
       imageHeight = null,
       imageIsOwn = false,
       voiceBase64 = null,
       voiceSender = null,
       voiceTimestamp = null,
       voiceDuration = 0,
       voiceIsOwn = false;

  _DisplayMessage.image({
    required String sender,
    required String base64Data,
    required DateTime timestamp,
    int? width,
    int? height,
    bool isOwn = false,
  }) : imageSender = sender,
       imageBase64 = base64Data,
       imageTimestamp = timestamp,
       imageWidth = width,
       imageHeight = height,
       imageIsOwn = isOwn,
       chatMessage = null,
       systemText = null,
       remoteSender = null,
       remoteContent = null,
       remoteTimestamp = null,
       voiceBase64 = null,
       voiceSender = null,
       voiceTimestamp = null,
       voiceDuration = 0,
       voiceIsOwn = false;

  _DisplayMessage.voice({
    required String sender,
    required String base64Data,
    required DateTime timestamp,
    double durationSeconds = 0,
    bool isOwn = false,
  }) : voiceSender = sender,
       voiceBase64 = base64Data,
       voiceTimestamp = timestamp,
       voiceDuration = durationSeconds,
       voiceIsOwn = isOwn,
       chatMessage = null,
       systemText = null,
       remoteSender = null,
       remoteContent = null,
       remoteTimestamp = null,
       imageBase64 = null,
       imageSender = null,
       imageTimestamp = null,
       imageWidth = null,
       imageHeight = null,
       imageIsOwn = false;

  final BitchatMessage? chatMessage;
  final String? systemText;
  final String? remoteSender;
  final String? remoteContent;
  final DateTime? remoteTimestamp;

  // Image message fields
  final String? imageBase64;
  final String? imageSender;
  final DateTime? imageTimestamp;
  final int? imageWidth;
  final int? imageHeight;
  final bool imageIsOwn;

  // Voice message fields
  final String? voiceBase64;
  final String? voiceSender;
  final DateTime? voiceTimestamp;
  final double voiceDuration;
  final bool voiceIsOwn;

  bool get isSystem => systemText != null;
  bool get isRemote => remoteSender != null;
  bool get isImage => imageBase64 != null;
  bool get isVoice => voiceBase64 != null;
}
