import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'about_page.dart';
import 'chatbot.dart';
import 'reminders.dart';
import 'settings.dart';
import 'settings_provider.dart';
import 'l10n/app_localizations.dart';

class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  int _selectedIndex = 0;

  void _onItemTapped(int index, VoidCallback navigate) {
    setState(() => _selectedIndex = index);
    Navigator.pop(context);
    Future.delayed(const Duration(milliseconds: 200), navigate);
  }

  Future<void> _logout() async {
    Navigator.pop(context);
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final user     = FirebaseAuth.instance.currentUser;
    final settings = SettingsProvider.of(context);
    final l        = AppLocalizations.of(context)!;

    return Drawer(
      child: Column(
        children: [
          _buildDrawerHeader(user, l),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [

                // ── Home ─────────────────────────────────────────────────
                _buildDrawerItem(
                  icon: Icons.home_rounded,
                  text: l.home,
                  index: 0,
                  onTap: () {},
                ),

                // ── Reminders ────────────────────────────────────────────
                _buildDrawerItem(
                  icon: Icons.notifications_active_rounded,
                  text: l.reminders,
                  index: 1,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ReminderPage()),
                  ),
                ),

                // ── Chat Buddy ───────────────────────────────────────────
                _buildDrawerItem(
                  icon: Icons.chat_bubble_rounded,
                  text: l.chatBuddy,
                  index: 2,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ChatScreen()),
                  ),
                ),

                const Divider(),

                // ── Adjust Text Size (slider) ─────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Label row with live percentage
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            l.adjustTextSize,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF004D40),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2D6A4F).withOpacity(0.10),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              "${(settings.fontSizeMultiplier * 100).toStringAsFixed(0)}%",
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2D6A4F),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 6),

                      // Small / Large end-labels
                      Row(
                        children: [
                          const Text("A",
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF78909C))),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: const Color(0xFF2D6A4F),
                                inactiveTrackColor:
                                    const Color(0xFF2D6A4F).withOpacity(0.20),
                                thumbColor: const Color(0xFF2D6A4F),
                                overlayColor:
                                    const Color(0xFF2D6A4F).withOpacity(0.12),
                                trackHeight: 4,
                                thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 8),
                              ),
                              child: Slider(
                                value: settings.fontSizeMultiplier,
                                min: 0.8,
                                max: 1.6,
                                divisions: 8,   // steps: 0.8 0.9 1.0 … 1.6
                                onChanged: (v) =>
                                    settings.updateFontSize(v),
                              ),
                            ),
                          ),
                          const Text("A",
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF78909C))),
                        ],
                      ),
                    ],
                  ),
                ),

                const Divider(),

                // ── Settings ─────────────────────────────────────────────
                _buildDrawerItem(
                  icon: Icons.settings_rounded,
                  text: l.settings,
                  index: 3,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsPage()),
                  ),
                ),

                // ── About ────────────────────────────────────────────────
                _buildDrawerItem(
                  icon: Icons.info_outline_rounded,
                  text: 'About',
                  index: 4,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AboutPage()),
                  ),
                ),
              ],
            ),
          ),

          const Divider(),

          // ── Logout ───────────────────────────────────────────────────
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

  // ── Drawer header ─────────────────────────────────────────────────────────
  Widget _buildDrawerHeader(User? user, AppLocalizations l) {
    final String name = user?.displayName ?? "User";

    return UserAccountsDrawerHeader(
      accountName: Text(
        name,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      ),
      accountEmail: const Text(""),
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

  // ── Item builder ─────────────────────────────────────────────────────────
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