import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'reminders.dart';
import 'chatbot.dart';
import 'package:intl/intl.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'settings_provider.dart';

class SquareCard extends StatelessWidget {
  const SquareCard({
    Key? key,
    required this.iconWidget,
    required this.label,
    required this.onTap,
    this.cardColor = const Color(0xFFD3FFED),
    this.fontSizeMultiplier = 1.0,
  }) : super(key: key);

  final Widget iconWidget;
  final String label;
  final VoidCallback onTap;
  final Color cardColor;
  final double fontSizeMultiplier;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 2 / 1.5,
      child: Card(
        color: cardColor,
        elevation: 6,
        shadowColor: cardColor.withOpacity(0.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              iconWidget,
              const SizedBox(height: 12),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: (16 * fontSizeMultiplier).toDouble(),
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF004D40),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late DateTime _now;
  late final Timer _timer;

  void _showFontSizeSlider() {
    final settings = SettingsProvider.of(context);

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              padding: const EdgeInsets.all(24),
              height: 200,
              color: Colors.white,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Adjust Font Size',
                    style: TextStyle(
                        fontSize: (20 * settings.fontSizeMultiplier).toDouble(),
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF004D40)),
                  ),
                  const SizedBox(height: 16),
                  Slider(
                    value: settings.fontSizeMultiplier,
                    min: 0.8,
                    max: 1.5,
                    divisions: 7,
                    label:
                    '${(settings.fontSizeMultiplier * 100).toStringAsFixed(0)}%',
                    activeColor: const Color(0xFF004D40),
                    inactiveColor: Colors.grey[300],
                    onChanged: (newValue) {
                      setModalState(() {
                        settings.updateFontSize(newValue);
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Hello!',
                    style: TextStyle(
                      fontSize: (16 * settings.fontSizeMultiplier).toDouble(),
                      color: const Color(0xFF004D40),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      setState(() {
        _now = DateTime.now();
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String _getDaySuffix(int day) {
    if (day >= 11 && day <= 13) {
      return 'th';
    }
    switch (day % 10) {
      case 1:
        return 'st';
      case 2:
        return 'nd';
      case 3:
        return 'rd';
      default:
        return 'th';
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) {
      return 'Good Morning';
    } else if (hour >= 12 && hour < 17) {
      return 'Good Afternoon';
    } else if (hour >= 17 && hour < 21) {
      return 'Good Evening';
    } else {
      return 'Good Night';
    }
  }

  String _formattedDate() {
    String dayOfWeekMonth = DateFormat('EEEE, MMMM').format(_now);
    String dayNumber = _now.day.toString();
    String suffix = _getDaySuffix(_now.day);
    return '$dayOfWeekMonth ${dayNumber}$suffix';
  }

  String _formattedTime() {
    return DateFormat('hh:mm a').format(_now);
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsProvider.of(context);

    const Color primaryTextColor = Color(0xFF004D40);
    const Color lightGreenCard = Color(0xFFC8E6C9);
    const Color lightTealCard = Color(0xFFA6E4D9);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      extendBodyBehindAppBar: true,
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF2D6A4F),
                    Color(0xFF26A69A),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              accountName: Padding(
                padding: const EdgeInsets.only(top: 26.0),
                child: Text(
                  'Sanskriti Gupta',
                  style: TextStyle(
                      fontSize: (20 * settings.fontSizeMultiplier).toDouble(),
                      fontWeight: FontWeight.w600),
                ),
              ),
              accountEmail: Row(
                children: [
                  const Icon(Icons.call, size: 18, color: Colors.white70),
                  const SizedBox(width: 6),
                  Text(
                    '+91 012345678',
                    style: TextStyle(
                        fontSize: (16 * settings.fontSizeMultiplier).toDouble(),
                        color: const Color(0xFFF3F3E8)),
                  ),
                ],
              ),
              currentAccountPicture: const CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.person, color: Color(0xFF2D6A4F), size: 44),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home),
              title: Text('Home', style: TextStyle(fontSize: (16 * settings.fontSizeMultiplier).toDouble())),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.chat),
              title: Text('Chatbot', style: TextStyle(fontSize: (16 * settings.fontSizeMultiplier).toDouble())),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ChatScreen()),
                );
              },
            ),
            ListTile(
              leading: SvgPicture.asset(
                'assets/images/fontsize.svg',
                width: 24,
                height: 24,
              ),
              title: Text('Font Size', style: TextStyle(fontSize: (16 * settings.fontSizeMultiplier).toDouble())),
              onTap: () {
                _showFontSizeSlider();
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: Text('Settings', style: TextStyle(fontSize: (16 * settings.fontSizeMultiplier).toDouble())),
              onTap: () {
                // logout logic
              },
            ),
            ListTile(
              leading: const Icon(Icons.exit_to_app),
              title: Text('Logout', style: TextStyle(fontSize: (16 * settings.fontSizeMultiplier).toDouble())),
              onTap: () {
                // logout logic
              },
            ),
          ],
        ),
      ),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(65),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(12),
            bottomRight: Radius.circular(12),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF2D6A4F),
                    Color(0xFF26A69A),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                centerTitle: true,
                iconTheme: const IconThemeData(
                  color: Colors.white,
                ),
                title: Text(
                  'Memoir',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: (30 * settings.fontSizeMultiplier).toDouble(),
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Raleway',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 120.0, left: 16.0, right: 16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            '${_getGreeting()}, Sanskriti!',
                            style: TextStyle(
                              fontSize: (26.0 * settings.fontSizeMultiplier)
                                  .toDouble(),
                              fontWeight: FontWeight.bold,
                              color: primaryTextColor,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ),
                        const CircleAvatar(
                          radius: 28,
                          backgroundColor: lightGreenCard,
                          child: Icon(Icons.person,
                              color: primaryTextColor, size: 36),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Today is ${_formattedDate()}',
                      style: TextStyle(
                        fontSize: (18 * settings.fontSizeMultiplier).toDouble(),
                        fontWeight: FontWeight.w500,
                        color: primaryTextColor,
                        fontFamily: 'Inter',
                      ),
                    ),
                    Text(
                      _formattedTime(),
                      style: TextStyle(
                        fontSize: (19 * settings.fontSizeMultiplier).toDouble(),
                        fontWeight: FontWeight.w500,
                        color: primaryTextColor,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: SquareCard(
                      iconWidget: const Icon(
                        Icons.notifications_outlined,
                        size: 48,
                        color: primaryTextColor,
                      ),
                      label: 'Reminders',
                      fontSizeMultiplier: settings.fontSizeMultiplier,
                      cardColor: lightTealCard,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const ReminderPage()),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SquareCard(
                      iconWidget: SvgPicture.asset(
                        'assets/images/chat.svg',
                        height: 48,
                        width: 48,
                        colorFilter: const ColorFilter.mode(
                            primaryTextColor, BlendMode.srcIn),
                      ),
                      label: 'Chat Buddy',
                      fontSizeMultiplier: settings.fontSizeMultiplier,
                      cardColor: lightGreenCard,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const ChatScreen()),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: SquareCard(
                      iconWidget: SvgPicture.asset('assets/images/photos.svg',
                          height: 48,
                          width: 48,
                          colorFilter: const ColorFilter.mode(
                              primaryTextColor, BlendMode.srcIn)),
                      label: 'Memories',
                      fontSizeMultiplier: settings.fontSizeMultiplier,
                      cardColor: lightGreenCard,
                      onTap: () {
                        // Navigate logic here
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SquareCard(
                      iconWidget: SvgPicture.asset('assets/images/games.svg',
                          height: 48,
                          width: 48,
                          colorFilter: const ColorFilter.mode(
                              primaryTextColor, BlendMode.srcIn)),
                      label: 'Games',
                      fontSizeMultiplier: settings.fontSizeMultiplier,
                      cardColor: lightTealCard,
                      onTap: () {
                        // games logic
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}