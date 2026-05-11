import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  AboutPage — Upgraded (Startup-Level, Accessibility-First)
//
//  New in this version:
//  ✅ Read Aloud (TTS) via flutter_tts
//  ✅ Simple / Full mode toggle
//  ✅ Emoji visuals on feature rows
//  ✅ Emergency Help card (Call Family, Share Location, Panic Button)
//  ✅ Personalised greeting  ("Hello Bhuwan 👋")
//  ✅ "How It Helps You Daily" section (morning/afternoon/evening)
//  ✅ Language quick-toggle (Hindi ↔ English)
//  ✅ CTA button → "Start Using App ❤️"
//  ✅ Privacy copy improved for elderly trust
//  ✅ FadeIn animation on body cards
//  ✅ Feature model class instead of raw tuples
//  ✅ Semantics labels throughout
//  ✅ const optimisations
//
//  DEPENDENCIES — add to pubspec.yaml:
//    flutter_tts: ^4.0.2
//
//  HOW TO OPEN IT (unchanged)
//  ──────────────
//    Navigator.push(context,
//      MaterialPageRoute(builder: (_) => AboutPage(userName: "Bhuwan")));
// ─────────────────────────────────────────────────────────────────────────────

// ── Feature model ────────────────────────────────────────────────────────────
class Feature {
  const Feature({
    required this.icon,
    required this.emoji,
    required this.title,
    required this.desc,
    this.simpleMode = false,
  });
  final IconData icon;
  final String emoji;
  final String title;
  final String desc;
  /// true → shown in Simple Mode too
  final bool simpleMode;
}

// ── Daily rhythm model ────────────────────────────────────────────────────────
class _DailySlot {
  const _DailySlot(this.emoji, this.time, this.activity);
  final String emoji, time, activity;
}

// ─────────────────────────────────────────────────────────────────────────────
class AboutPage extends StatefulWidget {
  const AboutPage({super.key, this.userName = 'Friend'});
  final String userName;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage>
    with SingleTickerProviderStateMixin {
  // ── Palette ────────────────────────────────────────────────────────────────
  static const Color _kGreen     = Color(0xFF2D6A4F);
  static const Color _kTeal      = Color(0xFF26A69A);
  static const Color _kDarkGreen = Color(0xFF004D40);
  static const Color _kBg        = Color(0xFFF4F6F5);
  static const Color _kCard      = Colors.white;
  static const Color _kSubText   = Color(0xFF546E7A);
  static const Color _kRed       = Color(0xFFD32F2F);

  // ── Features ───────────────────────────────────────────────────────────────
  static const _features = [
    Feature(
      icon: Icons.psychology_rounded,
      emoji: '🧠',
      title: 'Smart AI Companion',
      desc: 'Remembers your habits and talks like a friend — anytime you need.',
      simpleMode: true,
    ),
    Feature(
      icon: Icons.alarm_rounded,
      emoji: '💊',
      title: 'Smart Reminders',
      desc: 'Never miss medicine, water, or an important task.',
      simpleMode: true,
    ),
    Feature(
      icon: Icons.chat_bubble_rounded,
      emoji: '💬',
      title: 'Chat Buddy',
      desc: 'A friendly chat companion available any time of day.',
      simpleMode: true,
    ),
    Feature(
      icon: Icons.text_fields_rounded,
      emoji: '🔤',
      title: 'Adjustable Text Size',
      desc: 'Make the words bigger or smaller — whatever feels comfortable.',
    ),
    Feature(
      icon: Icons.translate_rounded,
      emoji: '🌐',
      title: 'Multiple Languages',
      desc: 'Use the app in the language you are most comfortable with.',
    ),
    Feature(
      icon: Icons.lock_outline_rounded,
      emoji: '🔐',
      title: 'Private & Secure',
      desc: 'Your data stays only on your phone. No one else can see it.',
    ),
  ];

  // ── Daily rhythm ───────────────────────────────────────────────────────────
  static const _dailySlots = [
    _DailySlot('🌅', 'Morning',   'Medicine reminder & good-morning message'),
    _DailySlot('☀️', 'Afternoon', 'Water reminder & gentle activity nudge'),
    _DailySlot('🌙', 'Evening',   'Chat companion & end-of-day check-in'),
  ];

  // ── TTS ────────────────────────────────────────────────────────────────────
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;

  // ── Simple / Full mode ─────────────────────────────────────────────────────
  bool _isSimpleMode = false;

  // ── Language toggle ────────────────────────────────────────────────────────
  bool _isHindi = false;

  // ── Animation ─────────────────────────────────────────────────────────────
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
  }

  @override
  void dispose() {
    _tts.stop();
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── TTS helpers ────────────────────────────────────────────────────────────
  String get _pageNarration => _isHindi
      ? 'नमस्ते ${widget.userName}। यह Memoir ऐप आपकी दैनिक यादों में मदद करता है।'
          ' इसमें AI सहायक, दवाई रिमाइंडर, चैट बडी और आपातकाल सहायता है।'
      : 'Hello ${widget.userName}. Memoir is your caring memory companion. '
          'It helps you with daily reminders, has an AI assistant, a chat buddy, '
          'and emergency help if you ever need it. Your data stays only on your phone.';

  Future<void> _toggleTts() async {
    if (_isSpeaking) {
      await _tts.stop();
      setState(() => _isSpeaking = false);
    } else {
      setState(() => _isSpeaking = true);
      await _tts.setLanguage(_isHindi ? 'hi-IN' : 'en-IN');
      await _tts.setSpeechRate(0.45);
      await _tts.speak(_pageNarration);
      setState(() => _isSpeaking = false);
    }
  }

  // ── Filtered feature list ──────────────────────────────────────────────────
  List<Feature> get _visibleFeatures =>
      _isSimpleMode ? _features.where((f) => f.simpleMode).toList() : _features;

  // ── Localised label helper ─────────────────────────────────────────────────
  String _t(String en, String hi) => _isHindi ? hi : en;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [

          // ── Gradient hero AppBar ──────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            stretch: true,
            backgroundColor: _kGreen,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 22),
              tooltip: 'Go back',
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              // ── Language toggle ──
              Semantics(
                label: 'Switch language',
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  icon: const Text('🌐', style: TextStyle(fontSize: 16)),
                  label: Text(
                    _isHindi ? 'EN' : 'हि',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  onPressed: () => setState(() => _isHindi = !_isHindi),
                ),
              ),
              // ── Read Aloud ──
              Semantics(
                label: 'Read page aloud',
                child: IconButton(
                  icon: Icon(
                    _isSpeaking ? Icons.stop_circle_rounded : Icons.volume_up_rounded,
                    color: Colors.white,
                  ),
                  tooltip: _isSpeaking ? 'Stop reading' : 'Read aloud',
                  onPressed: _toggleTts,
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [StretchMode.zoomBackground],
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_kGreen, _kTeal],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 40),
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white.withOpacity(0.40), width: 2),
                        ),
                        child: const Icon(Icons.favorite_rounded,
                            color: Colors.white, size: 38),
                      ),
                      const SizedBox(height: 12),
                      // ── Personalised greeting ──
                      Text(
                        'Hello ${widget.userName} 👋',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Caring for memory, one day at a time',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.82),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              title: const Text(
                ' ',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              centerTitle: false,
            ),
          ),

          // ── Body (FadeIn) ─────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
            sliver: SliverList(
              delegate: SliverChildListDelegate([

                // ── Simple / Full toggle ─────────────────────────────────
                _ModeToggleBar(
                  isSimple: _isSimpleMode,
                  simpleLabel: _t('Simple Mode', 'सरल मोड'),
                  fullLabel: _t('Full Mode', 'पूरा मोड'),
                  onChanged: (v) => setState(() => _isSimpleMode = v),
                ),

                const SizedBox(height: 16),

                // ── Mission card ─────────────────────────────────────────
                FadeTransition(
                  opacity: _fadeAnim,
                  child: _SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionHeader(
                          icon: Icons.info_outline_rounded,
                          label: _t('What is Memoir?', 'Memoir क्या है?'),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _t(
                            'Memoir is a caring companion app made specially '
                            'for people who need a little help remembering '
                            'day-to-day things.\n\n'
                            'It is simple, clear, and easy to use — even if '
                            'you have never used a smartphone app before.',
                            'Memoir एक देखभाल करने वाला ऐप है जो आपकी रोज़ की '
                            'यादों में मदद करता है।\n\nयह बहुत सरल है — '
                            'स्मार्टफोन की जानकारी न हो तो भी चलेगा।',
                          ),
                          style: const TextStyle(
                              fontSize: 16, color: _kSubText, height: 1.65),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Emergency card ───────────────────────────────────────
                FadeTransition(
                  opacity: _fadeAnim,
                  child: _EmergencyCard(isHindi: _isHindi),
                ),

                const SizedBox(height: 16),

                // ── How It Helps You Daily ───────────────────────────────
                FadeTransition(
                  opacity: _fadeAnim,
                  child: _SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionHeader(
                          icon: Icons.wb_sunny_rounded,
                          label: _t(
                              'How It Helps You Daily',
                              'यह हर दिन कैसे मदद करता है'),
                        ),
                        const SizedBox(height: 8),
                        ..._dailySlots.map((s) => _DailySlotRow(
                              emoji: s.emoji,
                              time: _t(s.time, _hindiTime(s.time)),
                              activity: _t(s.activity, _hindiActivity(s.time)),
                            )),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Features card ────────────────────────────────────────
                FadeTransition(
                  opacity: _fadeAnim,
                  child: _SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionHeader(
                          icon: Icons.star_rounded,
                          label: _t('What can this app do?',
                              'यह ऐप क्या कर सकता है?'),
                        ),
                        const SizedBox(height: 6),
                        ..._visibleFeatures.map((f) => _FeatureRow(
                              icon: f.icon,
                              emoji: f.emoji,
                              title: f.title,
                              description: f.desc,
                            )),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Tips card ────────────────────────────────────────────
                if (!_isSimpleMode)
                  FadeTransition(
                    opacity: _fadeAnim,
                    child: _SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SectionHeader(
                            icon: Icons.lightbulb_outline_rounded,
                            label: _t(
                                'Tips for getting started',
                                'शुरुआत के लिए सुझाव'),
                          ),
                          const SizedBox(height: 6),
                          _TipRow(
                            number: '1',
                            text: _t(
                              'Tap the 🔔 Reminders button to set up your medicine or water reminders first.',
                              '🔔 रिमाइंडर बटन दबाएं और पहले दवाई या पानी का रिमाइंडर सेट करें।',
                            ),
                          ),
                          _TipRow(
                            number: '2',
                            text: _t(
                              'Use the 💬 Chat Buddy if you feel lonely or need someone to talk to.',
                              'अकेलापन महसूस हो तो 💬 चैट बडी से बात करें।',
                            ),
                          ),
                          _TipRow(
                            number: '3',
                            text: _t(
                              'Go to ⚙️ Settings to make text bigger or switch to your preferred language.',
                              '⚙️ सेटिंग्स में जाकर टेक्स्ट बड़ा करें या भाषा बदलें।',
                            ),
                          ),
                          _TipRow(
                            number: '4',
                            text: _t(
                              'Ask a family member or caregiver to help you set up the app the first time.',
                              'पहली बार सेटअप के लिए परिवार के किसी सदस्य की मदद लें।',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                if (!_isSimpleMode) const SizedBox(height: 16),

                // ── App info card ─────────────────────────────────────────
                if (!_isSimpleMode)
                  FadeTransition(
                    opacity: _fadeAnim,
                    child: _SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SectionHeader(
                            icon: Icons.apps_rounded,
                            label: _t('App information', 'ऐप की जानकारी'),
                          ),
                          const SizedBox(height: 12),
                          _InfoRow(
                              label: _t('App name', 'ऐप का नाम'),
                              value: 'Memoir'),
                          _InfoRow(
                              label: _t('Version', 'संस्करण'),
                              value: '1.0.0'),
                          _InfoRow(
                              label: _t('Made for', 'बना है'),
                              value: _t('Dementia care support',
                                  'डिमेंशिया देखभाल')),
                          // ── Improved privacy copy ──
                          _InfoRow(
                            label: _t('Privacy', 'गोपनीयता'),
                            value: _t(
                              'Your data stays only on your phone. No one else can see it.',
                              'आपका डेटा सिर्फ आपके फोन में रहता है। कोई और नहीं देख सकता।',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 28),

                // ── CTA button ───────────────────────────────────────────
                Semantics(
                  label: 'Start using the app',
                  button: true,
                  child: SizedBox(
                    width: double.infinity,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [_kGreen, _kTeal]),
                          borderRadius: BorderRadius.circular(35),
                          boxShadow: [
                            BoxShadow(
                              color: _kGreen.withOpacity(0.30),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('❤️', style: TextStyle(fontSize: 20)),
                            SizedBox(width: 10),
                            Text(
                              'Start Using App',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // Hindi translations for daily slots
  String _hindiTime(String en) {
    switch (en) {
      case 'Morning':   return 'सुबह';
      case 'Afternoon': return 'दोपहर';
      case 'Evening':   return 'शाम';
      default:          return en;
    }
  }

  String _hindiActivity(String en) {
    switch (en) {
      case 'Morning':   return 'दवाई रिमाइंडर और सुप्रभात संदेश';
      case 'Afternoon': return 'पानी का रिमाइंडर और हल्की गतिविधि';
      case 'Evening':   return 'चैट साथी और दिन का अंत चेक-इन';
      default:          return '';
    }
  }
}

// ─── Mode toggle bar ──────────────────────────────────────────────────────────
class _ModeToggleBar extends StatelessWidget {
  const _ModeToggleBar({
    required this.isSimple,
    required this.simpleLabel,
    required this.fullLabel,
    required this.onChanged,
  });
  final bool isSimple;
  final String simpleLabel, fullLabel;
  final ValueChanged<bool> onChanged;

  static const Color _kGreen = Color(0xFF2D6A4F);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Toggle between Simple and Full mode',
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(50),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            _ToggleChip(
              label: '🟢  $simpleLabel',
              selected: isSimple,
              onTap: () => onChanged(true),
            ),
            _ToggleChip(
              label: '📋  $fullLabel',
              selected: !isSimple,
              onTap: () => onChanged(false),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  static const Color _kGreen = Color(0xFF2D6A4F);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? _kGreen : Colors.transparent,
            borderRadius: BorderRadius.circular(46),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFF546E7A),
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Emergency card ───────────────────────────────────────────────────────────
class _EmergencyCard extends StatelessWidget {
  const _EmergencyCard({required this.isHindi});
  final bool isHindi;

  String _t(String en, String hi) => isHindi ? hi : en;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Emergency Help section',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3F3),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFFFCDD2), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withOpacity(0.07),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD32F2F).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.emergency_rounded,
                      color: Color(0xFFD32F2F), size: 22),
                ),
                const SizedBox(width: 12),
                Text(
                  _t('🚨 Emergency Help', '🚨 आपातकाल सहायता'),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFB71C1C),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _EmergencyButton(
              icon: Icons.call_rounded,
              label: _t('Call Family', 'परिवार को कॉल करें'),
              onTap: () {/* launch:tel: */},
            ),
            const SizedBox(height: 10),
            _EmergencyButton(
              icon: Icons.location_on_rounded,
              label: _t('Share My Location', 'मेरी लोकेशन भेजें'),
              onTap: () {/* share location */},
            ),
            const SizedBox(height: 10),
            _EmergencyButton(
              icon: Icons.warning_amber_rounded,
              label: _t('Panic Button — I need help!', 'मुझे मदद चाहिए!'),
              isPanic: true,
              onTap: () {/* trigger SOS */},
            ),
          ],
        ),
      ),
    );
  }
}

class _EmergencyButton extends StatelessWidget {
  const _EmergencyButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isPanic = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isPanic;

  @override
  Widget build(BuildContext context) {
    final bg = isPanic ? const Color(0xFFD32F2F) : const Color(0xFFFFEBEE);
    final fg = isPanic ? Colors.white : const Color(0xFFB71C1C);

    return Semantics(
      label: label,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(icon, color: fg, size: 22),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w700,
                    fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Daily slot row ───────────────────────────────────────────────────────────
class _DailySlotRow extends StatelessWidget {
  const _DailySlotRow({
    required this.emoji,
    required this.time,
    required this.activity,
  });
  final String emoji, time, activity;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$time: $activity',
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    time,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF004D40),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    activity,
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: Color(0xFF546E7A),
                      height: 1.4,
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

// ─── Shared sub-widgets ───────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.label});
  final IconData icon;
  final String label;

  static const Color _kGreen     = Color(0xFF2D6A4F);
  static const Color _kDarkGreen = Color(0xFF004D40);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _kGreen.withOpacity(0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _kGreen, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: _kDarkGreen,
            ),
          ),
        ),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.emoji,
    required this.title,
    required this.description,
  });
  final IconData icon;
  final String emoji, title, description;

  static const Color _kTeal      = Color(0xFF26A69A);
  static const Color _kDarkGreen = Color(0xFF004D40);
  static const Color _kSubText   = Color(0xFF546E7A);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$title: $description',
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: _kTeal.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: _kTeal, size: 24),
                ),
                Positioned(
                  right: -4,
                  top: -4,
                  child: Text(emoji,
                      style: const TextStyle(fontSize: 14)),
                ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _kDarkGreen,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: _kSubText,
                      height: 1.5,
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

class _TipRow extends StatelessWidget {
  const _TipRow({required this.number, required this.text});
  final String number, text;

  static const Color _kGreen   = Color(0xFF2D6A4F);
  static const Color _kSubText = Color(0xFF546E7A);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Tip $number: $text',
      child: Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(
                color: _kGreen,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  number,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  text,
                  style: const TextStyle(
                    fontSize: 14.5,
                    color: _kSubText,
                    height: 1.55,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label, value;

  static const Color _kSubText   = Color(0xFF546E7A);
  static const Color _kDarkGreen = Color(0xFF004D40);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: _kSubText,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: _kDarkGreen,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}