import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chatbot.dart';
import 'reminders.dart';
import 'settings.dart';
import 'settings_provider.dart';
import 'l10n/app_localizations.dart'; // ✅ ADDED

class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  int _selectedIndex = 0;

  void _onItemTapped(int index, VoidCallback navigate) {
    setState(() {
      _selectedIndex = index;
    });
    Navigator.pop(context);
    Future.delayed(const Duration(milliseconds: 200), navigate);
  }

  Future<void> _logout() async {
    Navigator.pop(context);
    await FirebaseAuth.instance.signOut();
  }

  void _increaseFont() {
    final settings = SettingsProvider.of(context);
    if (settings.fontSizeMultiplier < 1.6) {
      settings.updateFontSize(
        (settings.fontSizeMultiplier + 0.1).clamp(0.8, 1.6),
      );
    }
  }

  void _decreaseFont() {
    final settings = SettingsProvider.of(context);
    if (settings.fontSizeMultiplier > 0.8) {
      settings.updateFontSize(
        (settings.fontSizeMultiplier - 0.1).clamp(0.8, 1.6),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final settings = SettingsProvider.of(context);
    final l = AppLocalizations.of(context)!; // ✅ LOCALIZATION

    return Drawer(
      child: Column(
        children: [
          _buildDrawerHeader(user, l),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildDrawerItem(
                  icon: Icons.home_rounded,
                  text: l.home,
                  index: 0,
                  onTap: () {},
                ),

                _buildDrawerItem(
                  icon: Icons.notifications_active_rounded,
                  text: l.reminders,
                  index: 1,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ReminderPage(),
                    ),
                  ),
                ),

                _buildDrawerItem(
                  icon: Icons.chat_bubble_rounded,
                  text: l.chatBuddy,
                  index: 2,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ChatScreen(),
                    ),
                  ),
                ),

                const Divider(),

                /// 🔥 Adjust Text Size
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.adjustTextSize,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF004D40),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            onPressed: _decreaseFont,
                            icon: const Icon(Icons.remove_circle_outline),
                            color: const Color(0xFF2D6A4F),
                            iconSize: 30,
                          ),
                          Text(
                            "${(settings.fontSizeMultiplier * 100).toStringAsFixed(0)}%",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            onPressed: _increaseFont,
                            icon: const Icon(Icons.add_circle_outline),
                            color: const Color(0xFF2D6A4F),
                            iconSize: 30,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const Divider(),

                _buildDrawerItem(
                  icon: Icons.settings_rounded,
                  text: l.settings,
                  index: 3,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SettingsPage(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),

          /// 🔥 LOGOUT
          ListTile(
            leading: const Icon(Icons.logout_rounded),
            title: Text(l.logout),
            onTap: _logout,
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildDrawerHeader(User? user, AppLocalizations l) {
    final String name = user?.displayName ?? "User";

    return UserAccountsDrawerHeader(
      accountName: Text(
        name,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
      accountEmail: Text(""), // You can localize this if needed
      currentAccountPicture: CircleAvatar(
        backgroundColor: Colors.white,
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : "U",
          style: const TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.bold,
            color: Color(0xFF004D40),
          ),
        ),
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2D6A4F), Color(0xFF26A69A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String text,
    required int index,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(text),
      selected: _selectedIndex == index,
      selectedTileColor: Colors.teal.withOpacity(0.1),
      onTap: () => _onItemTapped(index, onTap),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }
}
