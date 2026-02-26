import 'package:flutter/material.dart';

/// Onboarding welcome screen — first-run experience.
///
/// Multi-step walkthrough:
/// 1. Welcome + app description
/// 2. Set nickname
/// 3. Permission explanations (BLE, Location, Mic)
/// 4. Ready to go
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onComplete});

  /// Called when onboarding is finished with the chosen nickname.
  final ValueChanged<String> onComplete;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  final _nicknameController = TextEditingController(text: 'anon');
  int _currentPage = 0;
  static const _totalPages = 4;

  @override
  void dispose() {
    _pageController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      widget.onComplete(
        _nicknameController.text.trim().isEmpty
            ? 'anon'
            : _nicknameController.text.trim(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark
        ? const Color(0xFF32D74B) // green
        : const Color(0xFF248A3D);

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Page content
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentPage = i),
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _WelcomePage(accentColor: accentColor, isDark: isDark),
                  _NicknamePage(
                    controller: _nicknameController,
                    accentColor: accentColor,
                    isDark: isDark,
                  ),
                  _PermissionsPage(accentColor: accentColor, isDark: isDark),
                  _ReadyPage(accentColor: accentColor, isDark: isDark),
                ],
              ),
            ),

            // Bottom: dots + next button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Row(
                children: [
                  // Page dots
                  Row(
                    children: List.generate(_totalPages, (i) {
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(right: 6),
                        width: i == _currentPage ? 20 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == _currentPage
                              ? accentColor
                              : accentColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                  const Spacer(),
                  // Next / Get Started button
                  FilledButton(
                    onPressed: _nextPage,
                    style: FilledButton.styleFrom(
                      backgroundColor: accentColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      _currentPage == _totalPages - 1 ? 'Get Started' : 'Next',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Page 1: Welcome
// ---------------------------------------------------------------------------
class _WelcomePage extends StatelessWidget {
  const _WelcomePage({required this.accentColor, required this.isDark});
  final Color accentColor;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('🔐', style: const TextStyle(fontSize: 64)),
          const SizedBox(height: 24),
          Text(
            'Welcome to BitChat',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: accentColor,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Secure, decentralized messaging.\n'
            'No servers. No phone numbers.\n'
            'Just encrypted peer-to-peer communication.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.6,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          const SizedBox(height: 32),
          _FeatureRow(icon: '📡', text: 'Bluetooth Mesh + Nostr Relays'),
          _FeatureRow(icon: '🔒', text: 'End-to-end encrypted'),
          _FeatureRow(icon: '🌍', text: 'Works without internet'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Page 2: Set Nickname
// ---------------------------------------------------------------------------
class _NicknamePage extends StatelessWidget {
  const _NicknamePage({
    required this.controller,
    required this.accentColor,
    required this.isDark,
  });
  final TextEditingController controller;
  final Color accentColor;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('👤', style: const TextStyle(fontSize: 64)),
          const SizedBox(height: 24),
          Text(
            'Choose Your Name',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: accentColor,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'This is how others will see you.\n'
            'You can change it anytime in Settings.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: controller,
            autofocus: true,
            textAlign: TextAlign.center,
            maxLength: 24,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: accentColor,
            ),
            decoration: InputDecoration(
              hintText: 'anon',
              hintStyle: TextStyle(
                fontFamily: 'monospace',
                fontSize: 20,
                color: accentColor.withValues(alpha: 0.3),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: accentColor.withValues(alpha: 0.3),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: accentColor),
              ),
              counterStyle: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: isDark ? Colors.white38 : Colors.black26,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Page 3: Permissions
// ---------------------------------------------------------------------------
class _PermissionsPage extends StatelessWidget {
  const _PermissionsPage({required this.accentColor, required this.isDark});
  final Color accentColor;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('⚙️', style: const TextStyle(fontSize: 64)),
          const SizedBox(height: 24),
          Text(
            'Permissions',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: accentColor,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'BitChat may request these permissions:',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
          const SizedBox(height: 24),
          _PermissionTile(
            icon: Icons.bluetooth,
            title: 'Bluetooth',
            desc: 'Peer-to-peer mesh networking',
            color: const Color(0xFF007AFF),
          ),
          const SizedBox(height: 12),
          _PermissionTile(
            icon: Icons.location_on_outlined,
            title: 'Location',
            desc: 'Required for BLE scanning on Android',
            color: const Color(0xFFFF9500),
          ),
          const SizedBox(height: 12),
          _PermissionTile(
            icon: Icons.mic_outlined,
            title: 'Microphone',
            desc: 'Voice note recording',
            color: const Color(0xFFFF3B30),
          ),
          const SizedBox(height: 24),
          Text(
            'You can manage permissions anytime\nin your device settings.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              color: isDark ? Colors.white30 : Colors.black26,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Page 4: Ready
// ---------------------------------------------------------------------------
class _ReadyPage extends StatelessWidget {
  const _ReadyPage({required this.accentColor, required this.isDark});
  final Color accentColor;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('🚀', style: const TextStyle(fontSize: 64)),
          const SizedBox(height: 24),
          Text(
            'You\'re Ready!',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: accentColor,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Start chatting on #general or\ncreate encrypted private channels.\n\n'
            'Use /help to see available commands.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.6,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          const SizedBox(height: 32),
          _FeatureRow(icon: '💬', text: 'Join channels with /join #topic'),
          _FeatureRow(icon: '🔐', text: 'Send DMs via the drawer menu'),
          _FeatureRow(icon: '📸', text: 'Share images and voice notes'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable widgets
// ---------------------------------------------------------------------------
class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.text});
  final String icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.icon,
    required this.title,
    required this.desc,
    required this.color,
  });
  final IconData icon;
  final String title;
  final String desc;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.1 : 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                Text(
                  desc,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
