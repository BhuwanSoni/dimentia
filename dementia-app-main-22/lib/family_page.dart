import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'settings_provider.dart';
import 'family_firestore_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FamilyPage
// ─────────────────────────────────────────────────────────────────────────────

class FamilyPage extends StatefulWidget {
  const FamilyPage({super.key});

  @override
  State<FamilyPage> createState() => _FamilyPageState();
}

class _FamilyPageState extends State<FamilyPage> {
  final FamilyFirestoreService _service = FamilyFirestoreService();
  final PageController _pageController = PageController(viewportFraction: 0.88);
  final ImagePicker _picker = ImagePicker();

  int _currentPage = 0;
  bool _isSaving = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() =>
      _pageController.nextPage(duration: 500.ms, curve: Curves.easeOutQuart);
  void _prevPage() =>
      _pageController.previousPage(duration: 500.ms, curve: Curves.easeOutQuart);

  // ── Delete ─────────────────────────────────────────────────────────────────
  Future<void> _deleteMember(String docId, int familyLength) async {
    await _service.deleteFamilyMember(docId);

    if (_currentPage >= familyLength - 1 && _currentPage > 0) {
      final target = familyLength - 2;
      setState(() => _currentPage = target);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients) _pageController.jumpToPage(target);
      });
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Memory removed'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          backgroundColor: Colors.grey[800],
        ),
      );
    }
  }

  // ── Add-member bottom sheet (replaces AlertDialog — no overflow) ────────────
  Future<void> _showAddMemberSheet() async {
    final nameController = TextEditingController();
    final relationController = TextEditingController();
    final phoneController = TextEditingController();

    const pastelColors = [
      Color(0xFFF3E5F5),
      Color(0xFFE8F5E9),
      Color(0xFFFFF3E0),
      Color(0xFFE3F2FD),
      Color(0xFFFCE4EC),
    ];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,   // ← lets it resize above keyboard
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        String? pickedImagePath;
        bool saving = false;

        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              // ── KEY FIX: pushes sheet above keyboard ──────────────────────
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Handle bar ──────────────────────────────────────────
                    const SizedBox(height: 12),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5E7EB),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Header ──────────────────────────────────────────────
                    const Text(
                      'New Memory',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1F2937),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Add someone special to your circle',
                      style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 24),

                    // ── Photo picker row ────────────────────────────────────
                    GestureDetector(
                      onTap: saving
                          ? null
                          : () async {
                              final XFile? img = await _picker.pickImage(
                                source: ImageSource.gallery,
                                imageQuality: 85,
                              );
                              if (img != null) {
                                setSheetState(() => pickedImagePath = img.path);
                              }
                            },
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          Container(
                            width: 90,
                            height: 90,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFFF3F4F6),
                              border: Border.all(
                                color: pickedImagePath != null
                                    ? const Color(0xFF2D6A4F)
                                    : const Color(0xFFE5E7EB),
                                width: 2,
                              ),
                              image: pickedImagePath != null
                                  ? DecorationImage(
                                      image: FileImage(File(pickedImagePath!)),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: pickedImagePath == null
                                ? const Icon(Icons.person_rounded,
                                    size: 40, color: Color(0xFFD1D5DB))
                                : null,
                          ),
                          // Camera badge
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Color(0xFF2D6A4F),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt_rounded,
                                size: 14, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── Fields ──────────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        children: [
                          _buildSheetField(
                            nameController, 'Name *',
                            Icons.person_outline_rounded,
                          ),
                          const SizedBox(height: 12),
                          _buildSheetField(
                            relationController, 'Relation (e.g. Sister)',
                            Icons.favorite_border_rounded,
                          ),
                          const SizedBox(height: 12),
                          _buildSheetField(
                            phoneController, 'Phone number',
                            Icons.phone_outlined,
                            isPhone: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── Action buttons ──────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          // Cancel
                          Expanded(
                            child: OutlinedButton(
                              onPressed: saving
                                  ? null
                                  : () => Navigator.pop(sheetContext),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                    color: Color(0xFFE5E7EB)),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                              ),
                              child: Text('Cancel',
                                  style: TextStyle(
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.w600)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Save
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              onPressed: saving
                                  ? null
                                  : () async {
                                      if (nameController.text.trim().isEmpty) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: const Text(
                                                'Please enter a name'),
                                            behavior:
                                                SnackBarBehavior.floating,
                                            backgroundColor: Colors.redAccent,
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10)),
                                          ),
                                        );
                                        return;
                                      }

                                      setSheetState(() => saving = true);
                                      setState(() => _isSaving = true);

                                      try {
                                        final member = FamilyMember(
                                          name: nameController.text.trim(),
                                          relation:
                                              relationController.text.trim(),
                                          phoneNumber:
                                              phoneController.text.trim(),
                                          imageUrl: '',
                                          color: pastelColors[Random()
                                              .nextInt(pastelColors.length)],
                                        );

                                        await _service.addFamilyMember(
                                          member,
                                          localImagePath: pickedImagePath ?? '',
                                        );

                                        if (mounted) {
                                          Navigator.pop(sheetContext);
                                        }

                                        // Scroll back to member cards (not Add card)
                                        Future.delayed(400.ms, () {
                                          if (_pageController.hasClients &&
                                              mounted) {
                                            _pageController.animateToPage(
                                              0,
                                              duration: 600.ms,
                                              curve: Curves.easeOutQuart,
                                            );
                                          }
                                        });
                                      } catch (e) {
                                        if (mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                  'Failed to save: $e'),
                                              behavior:
                                                  SnackBarBehavior.floating,
                                              backgroundColor:
                                                  Colors.redAccent,
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          10)),
                                            ),
                                          );
                                        }
                                      } finally {
                                        if (mounted) {
                                          setState(() => _isSaving = false);
                                        }
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2D6A4F),
                                foregroundColor: Colors.white,
                                disabledBackgroundColor:
                                    const Color(0xFF2D6A4F).withOpacity(0.5),
                                elevation: 0,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
                              ),
                              child: saving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white),
                                    )
                                  : const Text(
                                      'Save Memory',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── Safe area bottom padding ─────────────────────────────
                    SizedBox(
                        height: MediaQuery.of(sheetContext).padding.bottom +
                            16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSheetField(
    TextEditingController controller,
    String hint,
    IconData icon, {
    bool isPhone = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: isPhone ? TextInputType.phone : TextInputType.text,
      textCapitalization:
          isPhone ? TextCapitalization.none : TextCapitalization.words,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: const Color(0xFF9CA3AF), size: 20),
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                const BorderSide(color: Color(0xFF2D6A4F), width: 1.5)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  // ── Dots indicator ─────────────────────────────────────────────────────────
  Widget _buildDots(int total) {
    if (total <= 1) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final active = i == _currentPage;
        return AnimatedContainer(
          duration: 300.ms,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 20 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFF2D6A4F)
                : const Color(0xFFD1D5DB),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  // ── Empty state ────────────────────────────────────────────────────────────
  Widget _buildEmptyState(double fontScale) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(28),
          decoration: const BoxDecoration(
            color: Color(0xFFF3F4F6),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.people_outline_rounded,
              size: 52, color: Color(0xFF9CA3AF)),
        ),
        const SizedBox(height: 20),
        Text(
          'No loved ones added yet',
          style: TextStyle(
            fontSize: 20 * fontScale,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Tap the + button to add your first memory',
          style: TextStyle(
              fontSize: 14 * fontScale, color: const Color(0xFF9CA3AF)),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final settings = SettingsProvider.of(context);
    final double fontScale = max(settings.fontSizeMultiplier, 1.0);

    return Scaffold(
      backgroundColor: const Color(0xFFFDFDFD),
      extendBodyBehindAppBar: true,

      // ── FAB: always-visible add button ─────────────────────────────────────
      // FIX #3: removed Add card from PageView entirely.
      // The FAB triggers the sheet from anywhere — no need to swipe to a card.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isSaving ? null : _showAddMemberSheet,
        backgroundColor: const Color(0xFF2D6A4F),
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Add',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),

      appBar: AppBar(
        title: Text(
          'My Loved Ones',
          style: TextStyle(
            color: const Color(0xFF1F2937),
            fontFamily: 'Raleway',
            fontSize: 24 * fontScale,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white.withOpacity(0.8),
        elevation: 0,
        toolbarHeight: 70,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: CircleAvatar(
            backgroundColor: Colors.white,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Color(0xFF1F2937), size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
      ),

      body: Stack(
        children: [
          // ── Background blobs ────────────────────────────────────────────────
          Positioned(
            top: -100, right: -100,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
              child: Container(
                width: 400, height: 400,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFE0F2F1).withOpacity(0.6),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -50, left: -50,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: Container(
                width: 300, height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFF3E0).withOpacity(0.6),
                ),
              ),
            ),
          ),

          // ── StreamBuilder ───────────────────────────────────────────────────
          StreamBuilder<List<FamilyMember>>(
            stream: _service.getFamilyMembers(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.wifi_off_rounded,
                            size: 48, color: Color(0xFF9CA3AF)),
                        const SizedBox(height: 16),
                        Text(
                          'Could not load family members.\nPlease check your connection.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 15 * fontScale,
                              color: const Color(0xFF6B7280)),
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final family = snapshot.data ?? [];

              // ── Empty state ─────────────────────────────────────────────────
              if (family.isEmpty) {
                return Center(child: _buildEmptyState(fontScale));
              }

              // ── PageView — only member cards, no Add card inside ─────────────
              // FIX #3: Add card removed from PageView.
              // itemCount = family.length (no +1)
              return LayoutBuilder(
                builder: (context, constraints) {
                  // dots row ~28px (dot 8 + margins 20), rest goes to PageView
                  final pageViewHeight = constraints.maxHeight - 28;
                  return Stack(
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        height: pageViewHeight,
                        child: PageView.builder(
                          controller: _pageController,
                          itemCount: family.length,
                          physics: const BouncingScrollPhysics(),
                          onPageChanged: (i) =>
                              setState(() => _currentPage = i),
                          itemBuilder: (context, index) {
                            return AnimatedBuilder(
                              animation: _pageController,
                              builder: (context, child) {
                                double scale = 1.0;
                                if (_pageController
                                    .position.haveDimensions) {
                                  scale = _pageController.page! - index;
                                  scale = (1 - (scale.abs() * 0.18))
                                      .clamp(0.82, 1.0);
                                }
                                return Transform.scale(
                                    scale: scale, child: child);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 10),
                                child: PremiumFamilyCard(
                                  member: family[index],
                                  fontScale: fontScale,
                                  onDelete: () => _deleteMember(
                                      family[index].docId, family.length),
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      // Dots
                      const SizedBox(height: 12),
                      _buildDots(family.length),
                      const SizedBox(height: 8),
                    ],
                  ),

                  // Prev arrow
                  if (_currentPage > 0)
                    Positioned(
                      left: 8, top: 0, bottom: 80,
                      child: Center(
                        child: _buildGlassArrow(
                            Icons.arrow_back_ios_new_rounded, _prevPage),
                      ),
                    ),

                  // Next arrow
                  if (_currentPage < family.length - 1)
                    Positioned(
                      right: 8, top: 0, bottom: 80,
                      child: Center(
                        child: _buildGlassArrow(
                            Icons.arrow_forward_ios_rounded, _nextPage),
                      ),
                    ),
                ],
              ); // Stack
                }, // LayoutBuilder builder
              ); // LayoutBuilder
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGlassArrow(IconData icon, VoidCallback onTap) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.45),
              shape: BoxShape.circle,
              border: Border.all(
                  color: Colors.white.withOpacity(0.6), width: 1.5),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    spreadRadius: 2),
              ],
            ),
            child: Icon(icon, color: const Color(0xFF1F2937), size: 22),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Premium Family Card
// ─────────────────────────────────────────────────────────────────────────────

class PremiumFamilyCard extends StatelessWidget {
  final FamilyMember member;
  final double fontScale;
  final VoidCallback onDelete;

  const PremiumFamilyCard({
    super.key,
    required this.member,
    required this.fontScale,
    required this.onDelete,
  });

  Future<void> _makePhoneCall() async {
    final clean = member.phoneNumber.replaceAll(RegExp(r'\s+'), '');
    if (clean.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: clean);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _openWhatsApp() async {
    final clean = member.phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
    if (clean.isEmpty) return;
    final uri = Uri.parse('https://wa.me/$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    return parts.length >= 2
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : name[0].toUpperCase();
  }

  Widget _buildImageContent(double fontScale) {
    if (member.imageUrl.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              member.color,
              member.color.withBlue(200).withOpacity(0.8),
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _getInitials(member.name),
                style: TextStyle(
                  fontSize: 80 * fontScale,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF1F2937).withOpacity(0.2),
                  letterSpacing: -2,
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -20),
                child: Icon(
                  Icons.face_retouching_natural_rounded,
                  size: 40,
                  color: const Color(0xFF1F2937).withOpacity(0.25),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Hero(
      tag: 'family_${member.docId}',
      child: CachedNetworkImage(
        imageUrl: member.imageUrl,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          color: member.color,
          child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        errorWidget: (_, __, ___) => Container(
          color: const Color(0xFFF3F4F6),
          child: const Icon(Icons.broken_image_rounded,
              size: 50, color: Colors.grey),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24)),
        title: const Text('Delete Memory?',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to remove ${member.name}?',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep',
                style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onDelete();
            },
            child: const Text('Remove',
                style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1F2937).withOpacity(0.08),
            blurRadius: 25,
            offset: const Offset(0, 10),
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Column(
          children: [
            // ── Photo / Initials ──────────────────────────────────────────────
            Expanded(
              flex: 55,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildImageContent(fontScale),
                  // Delete button
                  Positioned(
                    top: 16, right: 16,
                    child: ClipOval(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: GestureDetector(
                          onTap: () => _confirmDelete(context),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.delete_outline_rounded,
                                color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Info + buttons ────────────────────────────────────────────────
            Expanded(
              flex: 45,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                color: Colors.white,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Name + relation
                    Column(
                      children: [
                        Text(
                          member.name,
                          style: TextStyle(
                            fontSize: 26 * fontScale,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF1F2937),
                            letterSpacing: -0.5,
                            height: 1.1,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        if (member.relation.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: member.color.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              member.relation,
                              style: TextStyle(
                                fontSize: 15 * fontScale,
                                color: const Color(0xFF4B5563),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),

                    // Call + WhatsApp — label text won't wrap now
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: ElevatedButton.icon(
                              onPressed: member.phoneNumber.isNotEmpty
                                  ? _makePhoneCall
                                  : null,
                              icon: const Icon(Icons.call_rounded, size: 18),
                              label: const Text('Call',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2D6A4F),
                                foregroundColor: Colors.white,
                                disabledBackgroundColor:
                                    Colors.grey.shade300,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(16)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: ElevatedButton.icon(
                              onPressed: member.phoneNumber.isNotEmpty
                                  ? _openWhatsApp
                                  : null,
                              icon: const Icon(Icons.chat_bubble_rounded,
                                  size: 16),
                              label: const Text('WhatsApp',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF25D366),
                                foregroundColor: Colors.white,
                                disabledBackgroundColor:
                                    Colors.grey.shade300,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(16)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
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