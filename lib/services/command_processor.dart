import 'package:bitchat/models/bitchat_message.dart';

/// Result of processing an IRC-style command.
class CommandResult {
  const CommandResult({
    required this.type,
    this.channel,
    this.targetUser,
    this.message,
    this.systemMessage,
  });

  final CommandType type;
  final String? channel;
  final String? targetUser;
  final String? message;
  final String? systemMessage;
}

enum CommandType {
  joinChannel,
  privateMessage,
  who,
  channels,
  block,
  unblock,
  clear,
  setPassword,
  transferOwnership,
  toggleSave,
  nick,
  help,
  slap,
  unknown,
}

/// IRC-style command processor for BitChat.
///
/// Supports: /j, /msg, /w, /who, /channels, /block, /unblock,
/// /clear, /pass, /transfer, /save, /nick, /help, /slap
class CommandProcessor {
  CommandProcessor._();

  /// Returns a [CommandResult] if the input is a command, or null if it's
  /// a regular message.
  static CommandResult? parse(String input) {
    final trimmed = input.trim();
    if (!trimmed.startsWith('/')) return null;

    final parts = trimmed.split(RegExp(r'\s+'));
    final cmd = parts[0].toLowerCase();

    switch (cmd) {
      case '/j':
      case '/join':
        final channel = parts.length > 1
            ? parts[1].startsWith('#')
                  ? parts[1]
                  : '#${parts[1]}'
            : null;
        return CommandResult(
          type: CommandType.joinChannel,
          channel: channel,
          systemMessage: channel != null
              ? 'Joining $channel...'
              : 'Usage: /j #channel',
        );

      case '/m':
      case '/msg':
        if (parts.length < 3) {
          return const CommandResult(
            type: CommandType.privateMessage,
            systemMessage: 'Usage: /msg @name message',
          );
        }
        final target = parts[1].startsWith('@')
            ? parts[1].substring(1)
            : parts[1];
        final msg = parts.sublist(2).join(' ');
        return CommandResult(
          type: CommandType.privateMessage,
          targetUser: target,
          message: msg,
        );

      case '/w':
      case '/who':
        return const CommandResult(
          type: CommandType.who,
          systemMessage: 'Listing online users...',
        );

      case '/channels':
        return const CommandResult(
          type: CommandType.channels,
          systemMessage: 'Listing discovered channels...',
        );

      case '/block':
        final target = parts.length > 1
            ? (parts[1].startsWith('@') ? parts[1].substring(1) : parts[1])
            : null;
        return CommandResult(
          type: CommandType.block,
          targetUser: target,
          systemMessage: target != null
              ? 'Blocked @$target'
              : 'Blocked peers: (none)',
        );

      case '/unblock':
        if (parts.length < 2) {
          return const CommandResult(
            type: CommandType.unblock,
            systemMessage: 'Usage: /unblock @name',
          );
        }
        final target = parts[1].startsWith('@')
            ? parts[1].substring(1)
            : parts[1];
        return CommandResult(
          type: CommandType.unblock,
          targetUser: target,
          systemMessage: 'Unblocked @$target',
        );

      case '/clear':
        return const CommandResult(
          type: CommandType.clear,
          systemMessage: 'Chat cleared.',
        );

      case '/pass':
        final password = parts.length > 1 ? parts.sublist(1).join(' ') : null;
        return CommandResult(
          type: CommandType.setPassword,
          message: password,
          systemMessage: password != null
              ? 'Channel password updated.'
              : 'Channel password removed.',
        );

      case '/transfer':
        if (parts.length < 2) {
          return const CommandResult(
            type: CommandType.transferOwnership,
            systemMessage: 'Usage: /transfer @name',
          );
        }
        final target = parts[1].startsWith('@')
            ? parts[1].substring(1)
            : parts[1];
        return CommandResult(
          type: CommandType.transferOwnership,
          targetUser: target,
          systemMessage: 'Transferring ownership to @$target...',
        );

      case '/save':
        return const CommandResult(
          type: CommandType.toggleSave,
          systemMessage: 'Message retention toggled.',
        );

      case '/nick':
        if (parts.length < 2) {
          return const CommandResult(
            type: CommandType.nick,
            systemMessage: 'Usage: /nick newname',
          );
        }
        return CommandResult(
          type: CommandType.nick,
          message: parts[1],
          systemMessage: 'Nickname changed to ${parts[1]}',
        );

      case '/slap':
        if (parts.length < 2) {
          return const CommandResult(
            type: CommandType.slap,
            systemMessage: 'Usage: /slap @name',
          );
        }
        final target = parts[1].startsWith('@')
            ? parts[1].substring(1)
            : parts[1];
        return CommandResult(
          type: CommandType.slap,
          targetUser: target,
          message: 'slaps $target around a bit with a large trout 🐟',
        );

      case '/help':
        return const CommandResult(
          type: CommandType.help,
          systemMessage: '''Available commands:
/j #channel   — Join or create a channel
/msg @name message — Send a private message
/w            — List online users
/channels     — Show discovered channels
/block @name  — Block a peer
/unblock @name — Unblock a peer
/clear        — Clear chat messages
/pass [pw]    — Set/remove channel password
/transfer @name — Transfer channel ownership
/save         — Toggle message retention
/nick name    — Change nickname
/slap @name   — Slap someone with a trout''',
        );

      default:
        return CommandResult(
          type: CommandType.unknown,
          systemMessage: 'Unknown command: $cmd. Type /help for commands.',
        );
    }
  }
}
