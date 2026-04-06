import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'settings_provider.dart';

class FamilyMember {
  final String name;
  final String relation;
  final String phoneNumber;
  final String imagePath;
  final bool isAsset;
  final Color color;

  FamilyMember({
    required this.name,
    required this.relation,
    required this.phoneNumber,
    required this.imagePath,
    this.isAsset = true,
    required this.color,
  });
}

class FamilyPage extends StatefulWidget {
  const FamilyPage({super.key});

  @override
  State<FamilyPage> createState() => _FamilyPageState();
}

class _FamilyPageState extends State<FamilyPage> {
  final List<FamilyMember> _family = [];

  final PageController _pageController = PageController(viewportFraction: 0.88);
  final ImagePicker _picker = ImagePicker();

  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _deleteMember(int index) {
    setState(() {
      _family.removeAt(index);
      // If we were on the last card and deleted it, go back one page
      if (_currentPage >= _family.length && _currentPage > 0) {
        _currentPage = _family.length - 1;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _pageController.jumpToPage(_currentPage);
        });
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text("Memory removed"),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: Colors.grey[800],
      ),
    );
  }

  void _nextPage() =>
      _pageController.nextPage(duration: 500.ms, curve: Curves.easeOutQuart);
  void _prevPage() =>
      _pageController.previousPage(duration: 500.ms, curve: Curves.easeOutQuart);

  // ─── FIX: All three text fields now appear in the dialog ───────────────────
  Future<void> _showAddMemberDialog() async {
    final nameController = TextEditingController();
    final relationController = TextEditingController();
    final phoneController = TextEditingController();
    String? pickedImagePath;

    final List<Color> pastelColors = [
      const Color(0xFFF3E5F5),
      const Color(0xFFE8F5E9),
      const Color(0xFFFFF3E0),
      const Color(0xFFE3F2FD),
      const Color(0xFFFCE4EC),
    ];

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28)),
              title: const Text(
                "New Memory",
                style: TextStyle(
                    color: Color(0xFF1F2937), fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Photo picker ──────────────────────────────────────
                    GestureDetector(
                      onTap: () async {
                        final XFile? image = await _picker.pickImage(
                            source: ImageSource.gallery);
                        if (image != null) {
                          setDialogState(
                              () => pickedImagePath = image.path);
                        }
                      },
                      child: Container(
                        height: 100,
                        width: 100,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: const Color(0xFF2D6A4F).withOpacity(0.3),
                              width: 2),
                          image: pickedImagePath != null
                              ? DecorationImage(
                                  image: FileImage(File(pickedImagePath!)),
                                  fit: BoxFit.cover)
                              : null,
                        ),
                        child: pickedImagePath == null
                            ? const Icon(Icons.add_a_photo_rounded,
                                size: 32, color: Color(0xFF2D6A4F))
                            : null,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      pickedImagePath == null
                          ? "Tap to add photo"
                          : "Tap to change photo",
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 20),

                    // ── FIX: Name field ───────────────────────────────────
                    _buildTextField(
                      nameController,
                      "Name *",
                      Icons.person_outline_rounded,
                    ),
                    const SizedBox(height: 12),

                    // ── FIX: Relation field ───────────────────────────────
                    _buildTextField(
                      relationController,
                      "Relation (e.g. Sister)",
                      Icons.favorite_border_rounded,
                    ),
                    const SizedBox(height: 12),

                    // ── FIX: Phone field ──────────────────────────────────
                    _buildTextField(
                      phoneController,
                      "Phone number",
                      Icons.phone_outlined,
                      isPhone: true,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text("Cancel",
                      style: TextStyle(color: Colors.grey[500], fontSize: 16)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D6A4F),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    if (nameController.text.trim().isNotEmpty) {
                      setState(() {
                        _family.add(FamilyMember(
                          name: nameController.text.trim(),
                          relation: relationController.text.trim(),
                          phoneNumber: phoneController.text.trim(),
                          imagePath: pickedImagePath ?? '',
                          isAsset: false,
                          color: pastelColors[
                              Random().nextInt(pastelColors.length)],
                        ));
                      });
                      Navigator.pop(context);
                      Future.delayed(300.ms, () {
                        if (_pageController.hasClients) {
                          _pageController.animateToPage(
                            _family.length - 1,
                            duration: 600.ms,
                            curve: Curves.easeOutQuart,
                          );
                        }
                      });
                    } else {
                      // Shake / highlight the name field by showing a snackbar
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text("Please enter a name"),
                          behavior: SnackBarBehavior.floating,
                          backgroundColor: Colors.redAccent,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      );
                    }
                  },
                  child: const Text("Save Memory",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String hint,
    IconData icon, {
    bool isPhone = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: isPhone ? TextInputType.phone : TextInputType.text,
      textCapitalization: isPhone
          ? TextCapitalization.none
          : TextCapitalization.words,
      decoration: InputDecoration(
        prefixIcon:
            Icon(icon, color: const Color(0xFF9CA3AF), size: 22),
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[400]),
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
                color: Color(0xFF2D6A4F), width: 1.5)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  // ── Page dots indicator ─────────────────────────────────────────────────────
  Widget _buildDots() {
    final total = _family.length + 1; // +1 for Add card
    if (total <= 1) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final isActive = i == _currentPage;
        return AnimatedContainer(
          duration: 300.ms,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 20 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFF2D6A4F)
                : const Color(0xFFD1D5DB),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsProvider.of(context);
    final double fontScale = max(settings.fontSizeMultiplier, 1.0);

    return Scaffold(
      backgroundColor: const Color(0xFFFDFDFD),
      extendBodyBehindAppBar: true,
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
          // ── Ambient background blobs ──────────────────────────────────────
          Positioned(
            top: -100,
            right: -100,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
              child: Container(
                width: 400,
                height: 400,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFE0F2F1).withOpacity(0.6),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            left: -50,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFF3E0).withOpacity(0.6),
                ),
              ),
            ),
          ),

          // ── Main content ──────────────────────────────────────────────────
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.72,
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _family.length + 1,
                  physics: const BouncingScrollPhysics(),
                  onPageChanged: (index) =>
                      setState(() => _currentPage = index),
                  itemBuilder: (context, index) {
                    return AnimatedBuilder(
                      animation: _pageController,
                      builder: (context, child) {
                        double value = 1.0;
                        if (_pageController.position.haveDimensions) {
                          value = _pageController.page! - index;
                          value =
                              (1 - (value.abs() * 0.18)).clamp(0.82, 1.0);
                        }
                        return Transform.scale(scale: value, child: child);
                      },
                      child: index == _family.length
                          ? Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 10),
                              child: AddMemoryCard(
                                  onTap: _showAddMemberDialog,
                                  fontScale: fontScale),
                            )
                          : Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 10),
                              child: PremiumFamilyCard(
                                member: _family[index],
                                fontScale: fontScale,
                                onDelete: () => _deleteMember(index),
                              ),
                            ),
                    );
                  },
                ),
              ),

              // ── Dots indicator ────────────────────────────────────────────
              const SizedBox(height: 16),
              _buildDots(),
              const SizedBox(height: 8),
            ],
          ),

          // ── Arrow: previous ───────────────────────────────────────────────
          if (_currentPage > 0)
            Positioned(
              left: 8,
              top: 0,
              bottom: 80,
              child: Center(
                child: _buildGlassArrow(
                    Icons.arrow_back_ios_new_rounded, _prevPage),
              ),
            ),

          // ── Arrow: next ───────────────────────────────────────────────────
          if (_currentPage < _family.length)
            Positioned(
              right: 8,
              top: 0,
              bottom: 80,
              child: Center(
                child: _buildGlassArrow(
                    Icons.arrow_forward_ios_rounded, _nextPage),
              ),
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
// Add Memory Card
// ─────────────────────────────────────────────────────────────────────────────

class AddMemoryCard extends StatelessWidget {
  final VoidCallback onTap;
  final double fontScale;

  const AddMemoryCard(
      {super.key, required this.onTap, required this.fontScale});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
              color: const Color(0xFFE5E7EB).withOpacity(0.8), width: 1.5),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFFE5E7EB).withOpacity(0.5),
                blurRadius: 20,
                offset: const Offset(0, 8)),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 10,
                      spreadRadius: 5),
                ],
              ),
              child: const Icon(Icons.add_rounded,
                  size: 40, color: Color(0xFF9CA3AF)),
            ),
            const SizedBox(height: 24),
            Text(
              "New Memory",
              style: TextStyle(
                fontSize: 22 * fontScale,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF374151),
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Add a loved one",
              style: TextStyle(
                  fontSize: 16 * fontScale, color: const Color(0xFF9CA3AF)),
            ),
          ],
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
    final String cleanNumber =
        member.phoneNumber.replaceAll(RegExp(r'\s+'), '');
    if (cleanNumber.isEmpty) return;
    final Uri launchUri = Uri(scheme: 'tel', path: cleanNumber);
    if (await canLaunchUrl(launchUri)) await launchUrl(launchUri);
  }

  Future<void> _openWhatsApp() async {
    final String cleanNumber =
        member.phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
    if (cleanNumber.isEmpty) return;
    final Uri url = Uri.parse("https://wa.me/$cleanNumber");
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  Widget _buildImageContent(double fontScale) {
    final bool hasImage =
        member.imagePath.isNotEmpty;

    if (!hasImage) {
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
      tag: member.name,
      child: Image(
        image: member.isAsset
            ? AssetImage(member.imagePath) as ImageProvider
            : FileImage(File(member.imagePath)),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
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
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text("Delete Memory?",
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          "Are you sure you want to remove ${member.name}?",
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Keep",
                style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onDelete();
            },
            child: const Text("Remove",
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
            // ── Photo / Initials area ─────────────────────────────────────
            Expanded(
              flex: 55,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildImageContent(fontScale),

                  // Delete button (top-right)
                  Positioned(
                    top: 16,
                    right: 16,
                    child: ClipOval(
                      child: BackdropFilter(
                        filter:
                            ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: GestureDetector(
                          onTap: () => _confirmDelete(context),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                                Icons.delete_outline_rounded,
                                color: Colors.white,
                                size: 20),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Info + buttons area ───────────────────────────────────────
            Expanded(
              flex: 45,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
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
                        const SizedBox(height: 8),
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

                    // Call + WhatsApp buttons
                    Row(
                      children: [
                        // Call button
                        Expanded(
                          child: SizedBox(
                            height: 58,
                            child: ElevatedButton.icon(
                              onPressed: member.phoneNumber.isNotEmpty
                                  ? _makePhoneCall
                                  : null,
                              icon: const Icon(Icons.call_rounded, size: 22),
                              label: Text(
                                "Call",
                                style: TextStyle(
                                    fontSize: 15 * fontScale,
                                    fontWeight: FontWeight.w600),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2D6A4F),
                                foregroundColor: Colors.white,
                                disabledBackgroundColor:
                                    Colors.grey.shade300,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(18)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // WhatsApp button
                        Expanded(
                          child: SizedBox(
                            height: 58,
                            child: ElevatedButton.icon(
                              onPressed: member.phoneNumber.isNotEmpty
                                  ? _openWhatsApp
                                  : null,
                              icon: const Icon(
                                  Icons.chat_bubble_rounded, size: 20),
                              label: Text(
                                "WhatsApp",
                                style: TextStyle(
                                    fontSize: 15 * fontScale,
                                    fontWeight: FontWeight.w600),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF25D366),
                                foregroundColor: Colors.white,
                                disabledBackgroundColor:
                                    Colors.grey.shade300,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(18)),
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