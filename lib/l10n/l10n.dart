/// Localization support for BitChat.
///
/// Provides a simple i18n foundation that can be extended with
/// flutter_localizations and .arb files.

/// Supported locales.
enum AppLocale { en, zh, ja, ko, es, fr, de, pt, ru, ar }

/// Localized string manager.
class L10n {
  L10n._();

  static AppLocale _currentLocale = AppLocale.en;

  static AppLocale get currentLocale => _currentLocale;

  static void setLocale(AppLocale locale) {
    _currentLocale = locale;
  }

  /// Get a localized string by key.
  static String tr(String key) {
    final strings = _strings[_currentLocale] ?? _strings[AppLocale.en]!;
    return strings[key] ?? _strings[AppLocale.en]![key] ?? key;
  }

  /// All available locales with display names.
  static const localeNames = <AppLocale, String>{
    AppLocale.en: 'English',
    AppLocale.zh: '中文',
    AppLocale.ja: '日本語',
    AppLocale.ko: '한국어',
    AppLocale.es: 'Español',
    AppLocale.fr: 'Français',
    AppLocale.de: 'Deutsch',
    AppLocale.pt: 'Português',
    AppLocale.ru: 'Русский',
    AppLocale.ar: 'العربية',
  };

  // --- String tables ---
  static const _strings = <AppLocale, Map<String, String>>{
    AppLocale.en: {
      'app_name': 'BitChat',
      'welcome': 'Welcome to BitChat',
      'choose_name': 'Choose Your Name',
      'get_started': 'Get Started',
      'next': 'Next',
      'settings': 'Settings',
      'contacts': 'Contacts',
      'debug': 'Debug Panel',
      'channels': 'Channels',
      'join_channel': 'Join Channel',
      'send_message': 'Send a message...',
      'nickname': 'Nickname',
      'theme': 'Theme',
      'dark_mode': 'Dark Mode',
      'light_mode': 'Light Mode',
      'fingerprint': 'Fingerprint',
      'verify': 'Verify',
      'reject': 'Reject',
      'block': 'Block',
      'unblock': 'Unblock',
      'favorites': 'Favorites',
      'all_contacts': 'All Contacts',
      'no_messages': 'No messages yet',
      'encryption': 'Encryption',
      'peers': 'Peers',
      'connected': 'Connected',
      'disconnected': 'Disconnected',
      'mining': 'Mining…',
      'pow_label': 'PoW',
      'bluetooth': 'Bluetooth',
      'location': 'Location',
      'microphone': 'Microphone',
      'permissions': 'Permissions',
      'share': 'Share',
      'photo': 'Photo',
      'file': 'File',
      'voice': 'Voice',
      'cancel': 'Cancel',
      'confirm': 'Confirm',
      'delete': 'Delete',
      'copy': 'Copy',
      'copied': 'Copied!',
      'error': 'Error',
      'retry': 'Retry',
      'sent': 'Sent',
      'delivered': 'Delivered',
      'read': 'Read',
      'failed': 'Failed',
    },
    AppLocale.zh: {
      'app_name': 'BitChat',
      'welcome': '欢迎使用 BitChat',
      'choose_name': '选择你的名字',
      'get_started': '开始使用',
      'next': '下一步',
      'settings': '设置',
      'contacts': '联系人',
      'debug': '调试面板',
      'channels': '频道',
      'join_channel': '加入频道',
      'send_message': '发送消息...',
      'nickname': '昵称',
      'theme': '主题',
      'dark_mode': '深色模式',
      'light_mode': '浅色模式',
      'fingerprint': '指纹',
      'verify': '验证',
      'reject': '拒绝',
      'block': '屏蔽',
      'unblock': '取消屏蔽',
      'favorites': '收藏',
      'all_contacts': '所有联系人',
      'no_messages': '暂无消息',
      'encryption': '加密',
      'peers': '对等节点',
      'connected': '已连接',
      'disconnected': '未连接',
      'mining': '挖矿中…',
      'pow_label': '工作量证明',
      'bluetooth': '蓝牙',
      'location': '位置',
      'microphone': '麦克风',
      'permissions': '权限',
      'share': '分享',
      'photo': '照片',
      'file': '文件',
      'voice': '语音',
      'cancel': '取消',
      'confirm': '确认',
      'delete': '删除',
      'copy': '复制',
      'copied': '已复制！',
      'error': '错误',
      'retry': '重试',
      'sent': '已发送',
      'delivered': '已送达',
      'read': '已读',
      'failed': '失败',
    },
    AppLocale.ja: {
      'app_name': 'BitChat',
      'welcome': 'BitChatへようこそ',
      'choose_name': '名前を選択',
      'get_started': '始める',
      'next': '次へ',
      'settings': '設定',
      'contacts': '連絡先',
      'channels': 'チャンネル',
      'send_message': 'メッセージを送信...',
      'nickname': 'ニックネーム',
      'verify': '確認',
      'cancel': 'キャンセル',
      'delete': '削除',
      'copy': 'コピー',
    },
    AppLocale.ko: {
      'app_name': 'BitChat',
      'welcome': 'BitChat에 오신 것을 환영합니다',
      'choose_name': '이름 선택',
      'get_started': '시작하기',
      'next': '다음',
      'settings': '설정',
      'contacts': '연락처',
      'send_message': '메시지를 보내세요...',
    },
  };
}
