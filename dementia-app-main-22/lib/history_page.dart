import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'questionnaire_page.dart';

// ─── Design Tokens ────────────────────────────────────────────────────────────
// Warm clinical palette — deep navy canvas, amber pulse accent, cream text
const Color _kBg         = Color(0xFF0A0C14);
const Color _kBgWarm     = Color(0xFF0D0F1A);
const Color _kSurface    = Color(0xFF12152200);
const Color _kCard       = Color(0xFF141824);
const Color _kCardHover  = Color(0xFF191E2E);
const Color _kBorder     = Color(0xFF1E2438);
const Color _kBorderSoft = Color(0xFF252C42);

// Accent — amber pulse
const Color _kAmber      = Color(0xFFF5A623);
const Color _kAmberDim   = Color(0xFF2A1E08);
const Color _kAmberSoft  = Color(0xFF3D2B0C);

// Text
const Color _kText       = Color(0xFFF2EDE4);
const Color _kTextWarm   = Color(0xFFBFB8A8);
const Color _kTextMuted  = Color(0xFF525870);
const Color _kTextFaint  = Color(0xFF2E3450);

// Risk palette
const Color _kLowFg      = Color(0xFF34D399);
const Color _kLowBg      = Color(0xFF0A2018);
const Color _kMedFg      = Color(0xFFFBBF24);
const Color _kMedBg      = Color(0xFF261B06);
const Color _kHighFg     = Color(0xFFFC8181);
const Color _kHighBg     = Color(0xFF260C0C);
const Color _kCritFg     = Color(0xFFFF4D4D);
const Color _kCritBg     = Color(0xFF1F0606);

// ─── Risk Helpers ─────────────────────────────────────────────────────────────
Color _riskFg(String level) {
  switch (level.toLowerCase()) {
    case 'low':      return _kLowFg;
    case 'medium':   return _kMedFg;
    case 'high':     return _kHighFg;
    case 'critical': return _kCritFg;
    default:         return _kTextMuted;
  }
}

Color _riskBg(String level) {
  switch (level.toLowerCase()) {
    case 'low':      return _kLowBg;
    case 'medium':   return _kMedBg;
    case 'high':     return _kHighBg;
    case 'critical': return _kCritBg;
    default:         return Color(0xFF1A1E2C);
  }
}

IconData _riskIcon(String level) {
  switch (level.toLowerCase()) {
    case 'low':      return Icons.check_circle_outline_rounded;
    case 'medium':   return Icons.remove_circle_outline_rounded;
    case 'high':     return Icons.error_outline_rounded;
    case 'critical': return Icons.dangerous_outlined;
    default:         return Icons.help_outline_rounded;
  }
}

String _riskLabel(String level) {
  switch (level.toLowerCase()) {
    case 'low':      return 'Low Risk';
    case 'medium':   return 'Moderate';
    case 'high':     return 'High Risk';
    case 'critical': return 'Critical';
    default:         return level;
  }
}

String _formatDate(dynamic raw) {
  DateTime? dt;
  if (raw is Timestamp) {
    dt = raw.toDate().toLocal();
  } else if (raw is String && raw.isNotEmpty) {
    dt = DateTime.tryParse(raw)?.toLocal();
  }
  if (dt == null) return raw?.toString() ?? '—';
  const months = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '${months[dt.month]} ${dt.day}, ${dt.year} · $h:$m';
}

String _shortDate(dynamic raw) {
  DateTime? dt;
  if (raw is Timestamp) {
    dt = raw.toDate().toLocal();
  } else if (raw is String && raw.isNotEmpty) {
    dt = DateTime.tryParse(raw)?.toLocal();
  }
  if (dt == null) return '—';
  const months = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${months[dt.month]} ${dt.day}';
}

ThemeData get _theme => ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: _kBg,
  colorScheme: const ColorScheme.dark(surface: _kCard, primary: _kAmber),
  fontFamily: 'Helvetica Neue',
);

// ════════════════════════════════════════════════════════════════════════════
//  HomePage
// ════════════════════════════════════════════════════════════════════════════
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkAndRedirect();
  }

  Future<void> _checkAndRedirect() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _checking = false);
      return;
    }
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (!mounted) return;
    if (doc.exists && doc.data()?['last_test'] != null) {
      await Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const TestHistoryPage()));
      return;
    }
    setState(() => _checking = false);
  }

  Future<void> _goToTest() async {
    final result = await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const QuestionnairePage()));
    if (result != false && mounted) _checkAndRedirect();
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return Theme(
        data: _theme,
        child: const Scaffold(
          backgroundColor: _kBg,
          body: Center(
            child: CircularProgressIndicator(
              color: _kAmber,
              strokeWidth: 1.5,
            ),
          ),
        ),
      );
    }
    return Theme(
      data: _theme,
      child: Scaffold(
        backgroundColor: _kBg,
        body: Stack(
          children: [
            // Ambient glow background
            Positioned(
              top: -120,
              left: -80,
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _kAmber.withValues(alpha: 0.06),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _HomeTopBar(),
                    const SizedBox(height: 32),
                    _HeroSection(),
                    const SizedBox(height: 20),
                    _StatsStrip(),
                    const SizedBox(height: 20),
                    _FeaturePillRow(),
                    const SizedBox(height: 24),
                    _BeginCard(onStart: _goToTest),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Home Top Bar ─────────────────────────────────────────────────────────────
class _HomeTopBar extends StatelessWidget {
  const _HomeTopBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Logo mark
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: _kAmberDim,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: _kAmber.withValues(alpha: 0.25)),
          ),
          child: const Center(
            child: Icon(Icons.psychology_rounded, color: _kAmber, size: 19),
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CogniCheck',
                style: TextStyle(
                  color: _kText,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                'Cognitive Health Platform',
                style: TextStyle(
                  color: _kTextMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: _kAmberDim,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _kAmber.withValues(alpha: 0.30)),
          ),
          child: const Text(
            'BETA',
            style: TextStyle(
              color: _kAmber,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Hero Section ─────────────────────────────────────────────────────────────
class _HeroSection extends StatelessWidget {
  const _HeroSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
            color: _kAmber.withValues(alpha: 0.04),
            blurRadius: 60,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: _kAmber,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'EARLY COGNITIVE SCREENING',
                style: TextStyle(
                  color: _kAmber,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'Know your\ncognitive\nbaseline.',
            style: TextStyle(
              color: _kText,
              fontSize: 36,
              fontWeight: FontWeight.w800,
              height: 1.1,
              letterSpacing: -1.2,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'A clinically-informed screening that builds a personal timeline of cognitive health. Track scores, detect trends, take action.',
            style: TextStyle(
              color: _kTextWarm,
              fontSize: 13.5,
              height: 1.7,
            ),
          ),
          const SizedBox(height: 20),
          // Progress indicator strip - decorative
          Row(
            children: [
              _MiniBar(fraction: 1.0, color: _kLowFg),
              const SizedBox(width: 4),
              _MiniBar(fraction: 0.6, color: _kMedFg),
              const SizedBox(width: 4),
              _MiniBar(fraction: 0.3, color: _kHighFg),
              const Spacer(),
              const Text(
                'ML-backed model',
                style: TextStyle(
                  color: _kTextMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniBar extends StatelessWidget {
  const _MiniBar({required this.fraction, required this.color});
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38 * fraction,
      height: 3,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

// ─── Stats Strip ─────────────────────────────────────────────────────────────
class _StatsStrip extends StatelessWidget {
  const _StatsStrip();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _StatBox(value: '< 5m', label: 'To complete')),
        const SizedBox(width: 10),
        Expanded(child: _StatBox(value: '100%', label: 'Private')),
        const SizedBox(width: 10),
        Expanded(child: _StatBox(value: 'ML', label: 'Powered')),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.value, required this.label});
  final String value, label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: _kText,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              color: _kTextMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Feature Pill Row ─────────────────────────────────────────────────────────
class _FeaturePillRow extends StatelessWidget {
  const _FeaturePillRow();

  static const _items = [
    (Icons.timeline_rounded, 'Timeline tracking'),
    (Icons.lock_outline_rounded, 'Encrypted'),
    (Icons.insights_rounded, 'Trend analysis'),
    (Icons.verified_rounded, 'Validated'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _items.map((item) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _kBorderSoft),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.$1, color: _kTextMuted, size: 13),
              const SizedBox(width: 6),
              Text(
                item.$2,
                style: const TextStyle(
                  color: _kTextWarm,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ─── Begin Card ───────────────────────────────────────────────────────────────
class _BeginCard extends StatelessWidget {
  const _BeginCard({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: _kAmberDim,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _kAmber.withValues(alpha: 0.2)),
                ),
                child: const Icon(Icons.play_circle_outline_rounded,
                    color: _kAmber, size: 24),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Start your first screening',
                      style: TextStyle(
                        color: _kText,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Establish your cognitive baseline',
                      style: TextStyle(
                        color: _kTextMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(color: _kBorder, height: 1),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: onStart,
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: _kAmber,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: _kAmber.withValues(alpha: 0.30),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.arrow_forward_rounded,
                        color: Color(0xFF1A0E00), size: 19),
                    SizedBox(width: 10),
                    Text(
                      'Begin Screening',
                      style: TextStyle(
                        color: Color(0xFF1A0E00),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  TestHistoryPage
// ════════════════════════════════════════════════════════════════════════════
class TestHistoryPage extends StatefulWidget {
  const TestHistoryPage({super.key});

  @override
  State<TestHistoryPage> createState() => _TestHistoryPageState();
}

class _TestHistoryPageState extends State<TestHistoryPage> {
  final User? _user = FirebaseAuth.instance.currentUser;

  Future<void> _deleteRecord(String docId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => Theme(
        data: _theme,
        child: AlertDialog(
          backgroundColor: _kCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: _kBorder),
          ),
          title: const Text(
            'Remove this record?',
            style: TextStyle(
              color: _kText,
              fontWeight: FontWeight.w700,
              fontSize: 17,
              letterSpacing: -0.3,
            ),
          ),
          content: const Text(
            'This screening result will be permanently deleted and cannot be recovered.',
            style: TextStyle(color: _kTextWarm, height: 1.65, fontSize: 13.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: _kTextMuted, fontWeight: FontWeight.w600),
              ),
            ),
            GestureDetector(
              onTap: () => Navigator.pop(context, true),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color: _kHighBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kHighFg.withValues(alpha: 0.20)),
                ),
                child: const Text(
                  'Delete',
                  style: TextStyle(
                    color: _kHighFg,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 2),
          ],
        ),
      ),
    );

    final user = _user;
    if (confirmed != true || user == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('predictions')
        .doc(docId)
        .delete();

    final remaining = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('predictions')
        .limit(1)
        .get();

    if (remaining.docs.isEmpty && mounted) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'last_test': FieldValue.delete()});
      await Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const HomePage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    if (user == null) {
      return Theme(
        data: _theme,
        child: const Scaffold(
          backgroundColor: _kBg,
          body: Center(
            child: Text(
              'Not signed in',
              style: TextStyle(color: _kTextMuted),
            ),
          ),
        ),
      );
    }

    final predictionsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('predictions')
        .orderBy('timestamp', descending: true);

    return Theme(
      data: _theme,
      child: Scaffold(
        backgroundColor: _kBg,
        body: Stack(
          children: [
            // ambient glow
            Positioned(
              top: -100,
              right: -100,
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _kAmber.withValues(alpha: 0.05),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: predictionsRef.snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: _kCard,
                              shape: BoxShape.circle,
                              border: Border.all(color: _kBorder),
                            ),
                            child: const Icon(Icons.cloud_off_rounded,
                                color: _kTextMuted, size: 26),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Could not load history',
                            style: TextStyle(color: _kTextWarm, fontSize: 15),
                          ),
                        ],
                      ),
                    );
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                          color: _kAmber, strokeWidth: 1.5),
                    );
                  }

                  final docs = snapshot.data?.docs ?? [];

                  return CustomScrollView(
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: _HistoryHeader(
                          totalTests: docs.length,
                          docs: docs,
                        ),
                      ),
                      if (docs.isEmpty)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: _EmptyState(),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (ctx, i) {
                                final doc = docs[i];
                                final data = doc.data();
                                return _TimelineEntry(
                                  docId: doc.id,
                                  data: data,
                                  index: docs.length - i,
                                  isFirst: i == 0,
                                  isLast: i == docs.length - 1,
                                  onDelete: () => _deleteRecord(doc.id),
                                );
                              },
                              childCount: docs.length,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── History Header ───────────────────────────────────────────────────────────
class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader({
    required this.totalTests,
    required this.docs,
  });
  final int totalTests;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  @override
  Widget build(BuildContext context) {
    // Compute average risk %
    double avgPct = 0;
    if (docs.isNotEmpty) {
      final sum = docs.fold<double>(0.0, (acc, d) {
        final p = (d.data()['probability'] as num?)?.toDouble() ?? 0.0;
        return acc + p.clamp(0.0, 1.0);
      });
      avgPct = sum / docs.length * 100;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top nav bar
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.maybePop(context),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _kCard,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: _kBorder),
                  ),
                  child: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: _kTextMuted, size: 14),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'CogniCheck',
                style: TextStyle(
                  color: _kTextMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                decoration: BoxDecoration(
                  color: _kAmberDim,
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: _kAmber.withValues(alpha: 0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.history_rounded,
                        color: _kAmber, size: 12),
                    const SizedBox(width: 5),
                    Text(
                      '$totalTests ${totalTests == 1 ? 'record' : 'records'}',
                      style: const TextStyle(
                        color: _kAmber,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 28),

        // Summary panel
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _kBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'HEALTH TIMELINE',
                  style: TextStyle(
                    color: _kTextFaint,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.8,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Screening\nHistory',
                  style: TextStyle(
                    color: _kText,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    letterSpacing: -0.8,
                  ),
                ),
                if (docs.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Container(height: 1, color: _kBorder),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _SummaryPill(
                        label: 'TESTS',
                        value: '$totalTests',
                        color: _kAmber,
                      ),
                      const SizedBox(width: 10),
                      _SummaryPill(
                        label: 'AVG RISK',
                        value: '${avgPct.round()}%',
                        color: avgPct < 33
                            ? _kLowFg
                            : avgPct < 66
                                ? _kMedFg
                                : _kHighFg,
                      ),
                      const SizedBox(width: 10),
                      _SummaryPill(
                        label: 'LATEST',
                        value: _shortDate(docs.first.data()['timestamp']),
                        color: _kTextWarm,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              const Text(
                'ALL SCREENINGS',
                style: TextStyle(
                  color: _kTextFaint,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.8,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Container(height: 1, color: _kBorder)),
            ],
          ),
        ),

        const SizedBox(height: 16),
      ],
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill(
      {required this.label, required this.value, required this.color});
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: _kBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: _kTextFaint,
                fontSize: 8.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _kCard,
                shape: BoxShape.circle,
                border: Border.all(color: _kBorder),
              ),
              child: const Icon(
                Icons.timeline_rounded,
                size: 30,
                color: _kTextMuted,
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'No records yet',
              style: TextStyle(
                color: _kText,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Complete a screening to begin\nyour cognitive health timeline.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _kTextMuted,
                fontSize: 13.5,
                height: 1.65,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Timeline Entry  (replaces _HistoryCard)
// ════════════════════════════════════════════════════════════════════════════
class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({
    required this.docId,
    required this.data,
    required this.index,
    required this.isFirst,
    required this.isLast,
    required this.onDelete,
  });

  final String docId;
  final Map<String, dynamic> data;
  final int index;
  final bool isFirst, isLast;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final riskLevel = (data['risk_level'] ?? 'Unknown').toString();
    final probability = (data['probability'] as num?)?.toDouble() ?? 0.0;
    final safeProb = probability.clamp(0.0, 1.0);
    final percentage = (safeProb * 100).round();
    final timestamp = data['timestamp'];
    final prediction = (data['prediction'] ?? '').toString();
    final questionnaire = Map<String, dynamic>.from(
        data['questionnaire'] ?? <String, dynamic>{});

    final chipData = <MapEntry<String, String>>[
      if (questionnaire['AGE'] != null)
        MapEntry('Age', '${questionnaire['AGE']}'),
      if (questionnaire['MMSE'] != null)
        MapEntry('MMSE', '${questionnaire['MMSE']}'),
      if (questionnaire['EDUCATION'] != null)
        MapEntry('Edu', '${questionnaire['EDUCATION']}'),
      if (questionnaire['YEARS_OF_EDUCATION'] != null)
        MapEntry('Yrs', '${questionnaire['YEARS_OF_EDUCATION']}'),
      if (questionnaire['SES'] != null)
        MapEntry('SES', '${questionnaire['SES']}'),
      if (questionnaire['GENDER'] != null)
        MapEntry('Sex',
            questionnaire['GENDER'] == 0 ? 'M' : 'F'),
    ];

    final fg = _riskFg(riskLevel);
    final bg = _riskBg(riskLevel);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline rail
          SizedBox(
            width: 32,
            child: Column(
              children: [
                // Top line
                if (!isFirst)
                  Expanded(
                    flex: 1,
                    child: Center(
                      child: Container(
                        width: 1,
                        color: _kBorder,
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 12),

                // Node dot
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: fg,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: fg.withValues(alpha: 0.40),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),

                // Bottom line
                if (!isLast)
                  Expanded(
                    flex: 4,
                    child: Center(
                      child: Container(
                        width: 1,
                        color: _kBorder,
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 8),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // Card body
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Container(
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _kBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Risk color header strip
                    Container(
                      height: 2.5,
                      decoration: BoxDecoration(
                        color: fg,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(20)),
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 14, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title row
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Screening #$index',
                                      style: const TextStyle(
                                        color: _kText,
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      _formatDate(timestamp),
                                      style: const TextStyle(
                                        color: _kTextMuted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Delete button
                              GestureDetector(
                                onTap: onDelete,
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: _kHighBg,
                                    borderRadius: BorderRadius.circular(9),
                                    border: Border.all(
                                      color: _kHighFg.withValues(alpha: 0.15),
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 15,
                                    color: _kHighFg,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 14),

                          // Risk Score row
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Big percentage
                              Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$percentage%',
                                    style: TextStyle(
                                      color: fg,
                                      fontSize: 28,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -1.0,
                                    ),
                                  ),
                                  Text(
                                    'risk score',
                                    style: TextStyle(
                                      color: _kTextMuted,
                                      fontSize: 10.5,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    // Progress bar
                                    ClipRRect(
                                      borderRadius:
                                          BorderRadius.circular(999),
                                      child: LinearProgressIndicator(
                                        value: safeProb,
                                        backgroundColor: _kBorder,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                fg),
                                        minHeight: 5,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    // Risk label badge
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: bg,
                                        borderRadius:
                                            BorderRadius.circular(999),
                                        border: Border.all(
                                          color: fg.withValues(alpha: 0.22),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(_riskIcon(riskLevel),
                                              size: 11, color: fg),
                                          const SizedBox(width: 5),
                                          Text(
                                            _riskLabel(riskLevel),
                                            style: TextStyle(
                                              color: fg,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          // Prediction tag
                          if (prediction.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 9),
                              decoration: BoxDecoration(
                                color: _kBg,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _kBorderSoft),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.biotech_outlined,
                                      size: 13, color: _kTextMuted),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Prediction  ',
                                    style: TextStyle(
                                      color: _kTextMuted,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      prediction,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: _kTextWarm,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          // Detail chips
                          if (chipData.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: chipData
                                  .map((e) => _DetailChip(
                                      label: e.key, value: e.value))
                                  .toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Detail Chip ──────────────────────────────────────────────────────────────
class _DetailChip extends StatelessWidget {
  const _DetailChip({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: _kBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kBorder),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label  ',
              style: const TextStyle(
                color: _kTextMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: _kTextWarm,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}