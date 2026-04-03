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
  final List<FamilyMember> _family = [
    FamilyMember(
      name: 'Rohan',
      relation: 'Son',
      phoneNumber: '+91 98765 43210',
      imagePath: '',
      color: const Color(0xFFE0F2F1),
    ),
    FamilyMember(
      name: 'Priya',
      relation: 'Granddaughter',
      phoneNumber: '+91 91234 56789',
      imagePath: 'assets/images/daughter.jpg',
      color: const Color(0xFFFFF3E0),
    ),
    FamilyMember(
      name: 'Dr. Mehta',
      relation: 'Doctor',
      phoneNumber: '+91 11 2345 6789',
      imagePath: 'assets/images/doctor.jpeg',
      color: const Color(0xFFE3F2FD),
    ),
  ];

  final PageController _pageController = PageController(viewportFraction: 0.85);
  final ImagePicker _picker = ImagePicker();

  int _currentPage=0;

  void _deleteMember(int index) {
    setState(() {
      _family.removeAt(index);
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

  void _nextPage() => _pageController.nextPage(duration: 500.ms, curve: Curves.easeOutQuart);
  void _prevPage() => _pageController.previousPage(duration: 500.ms, curve: Curves.easeOutQuart);

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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              title: const Text("New Memory", style: TextStyle(color: Color(0xFF1F2937), fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () async {
                        final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
                        if (image != null) {
                          setDialogState(() => pickedImagePath = image.path);
                        }
                      },
                      child: Container(
                        height: 110,
                        width: 110,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF2D6A4F).withOpacity(0.3), width: 2),
                          image: pickedImagePath != null
                              ? DecorationImage(image: FileImage(File(pickedImagePath!)), fit: BoxFit.cover)
                              : null,
                        ),
                        child: pickedImagePath == null
                            ? const Icon(Icons.add_a_photo_rounded, size: 35, color: Color(0xFF2D6A4F))
                            : null,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildTextField(nameController, "Name (e.g. Rohan)", Icons.person_rounded),
                    const SizedBox(height: 12),
                    _buildTextField(relationController, "Who is this? (e.g. Son)", Icons.favorite_rounded),
                    const SizedBox(height: 12),
                    _buildTextField(phoneController, "Phone Number", Icons.phone_rounded, isPhone: true),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text("Cancel", style: TextStyle(color: Colors.grey[500], fontSize: 16)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D6A4F),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    if (nameController.text.isNotEmpty && pickedImagePath != null) {
                      setState(() {
                        _family.add(FamilyMember(
                          name: nameController.text,
                          relation: relationController.text,
                          phoneNumber: phoneController.text,
                          imagePath: pickedImagePath!,
                          isAsset: false,
                          color: pastelColors[Random().nextInt(pastelColors.length)],
                        ));
                      });
                      Navigator.pop(context);
                      Future.delayed(300.ms, () {
                        _pageController.animateToPage(_family.length - 1, duration: 600.ms, curve: Curves.easeOutQuart);
                      });
                    }
                  },
                  child: const Text("Save Memory"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, IconData icon, {bool isPhone = false}) {
    return TextField(
      controller: controller,
      keyboardType: isPhone ? TextInputType.phone : TextInputType.text,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: const Color(0xFF9CA3AF), size: 22),
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[400]),
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF2D6A4F), width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
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
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1F2937), size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [

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

          // Main Carousel
          Center(
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.75,
              child: PageView.builder(
                controller: _pageController,
                itemCount: _family.length + 1,
                physics: const BouncingScrollPhysics(),
                onPageChanged: (int index)=>setState(()=>_currentPage=index),
                itemBuilder: (context, index) {
                  return AnimatedBuilder(
                    animation: _pageController,
                    builder: (context, child) {
                      double value = 1.0;
                      if (_pageController.position.haveDimensions) {
                        value = _pageController.page! - index;
                        value = (1 - (value.abs() * 0.2)).clamp(0.8, 1.0);
                      }
                      return Transform.scale(
                        scale: value,
                        child: child,
                      );
                    },
                    child: index == _family.length
                        ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
                      child: AddMemoryCard(onTap: _showAddMemberDialog, fontScale: fontScale),
                    )
                        : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
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
          ),

          if(_currentPage>0)
            Positioned(
              left: 16,
              top: 0,
              bottom: 0,
              child: Center(child: _buildGlassArrow(
                  Icons.arrow_back_ios_new_rounded, _prevPage)),
            ),
          if(_currentPage<_family.length)
            Positioned(
              right: 16,
              top: 0,
              bottom: 0,
              child: Center(child: _buildGlassArrow(Icons.arrow_forward_ios_rounded, _nextPage)),
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
              color: Colors.white.withOpacity(0.4),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.6), width: 1.5),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, spreadRadius: 2),
              ],
            ),
            child: Icon(icon, color: const Color(0xFF1F2937), size: 24),
          ),
        ),
      ),
    );
  }
}

class AddMemoryCard extends StatelessWidget {
  final VoidCallback onTap;
  final double fontScale;

  const AddMemoryCard({super.key, required this.onTap, required this.fontScale});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: const Color(0xFFE5E7EB), width: 2),
          boxShadow: [
            BoxShadow(color: const Color(0xFFE5E7EB).withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 8)),
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
                  BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, spreadRadius: 5),
                ],
              ),
              child: const Icon(Icons.add_rounded, size: 40, color: Color(0xFF9CA3AF)),
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
              style: TextStyle(fontSize: 16 * fontScale, color: const Color(0xFF9CA3AF)),
            ),
          ],
        ),
      ),
    );
  }
}

// class PremiumFamilyCard extends StatelessWidget {
//   final FamilyMember member;
//   final double fontScale;
//   final VoidCallback onDelete;
//
//   const PremiumFamilyCard({
//     super.key,
//     required this.member,
//     required this.fontScale,
//     required this.onDelete,
//   });
//
//   //  Phone call
//   Future<void> _makePhoneCall() async {
//     final String cleanNumber = member.phoneNumber.replaceAll(RegExp(r'\s+'), '');
//     final Uri launchUri = Uri(scheme: 'tel', path: cleanNumber);
//     if (await canLaunchUrl(launchUri)) await launchUrl(launchUri);
//   }
//
//   // whatsApp Logic
//   Future<void> _openWhatsApp() async {
//     // just the digits (no +, spaces, or dashes)
//     final String cleanNumber = member.phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
//
//     final Uri url = Uri.parse("https://wa.me/$cleanNumber");
//
//     if (await canLaunchUrl(url)) {
//       await launchUrl(url, mode: LaunchMode.externalApplication);
//     }
//   }
//
//   void _confirmDelete(BuildContext context) {
//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         backgroundColor: Colors.white,
//         surfaceTintColor: Colors.white,
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
//         title: const Text("Delete Memory?", style: TextStyle(fontWeight: FontWeight.bold)),
//         content: Text("Are you sure you want to remove ${member.name}?", style: const TextStyle(color: Colors.grey)),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(context),
//             child: const Text("Keep", style: TextStyle(color: Colors.grey)),
//           ),
//           TextButton(
//             onPressed: () {
//               Navigator.pop(context);
//               onDelete();
//             },
//             child: const Text("Remove", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
//           ),
//         ],
//       ),
//     );
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(32),
//         boxShadow: [
//           BoxShadow(
//             color: const Color(0xFF1F2937).withOpacity(0.08),
//             blurRadius: 25,
//             offset: const Offset(0, 10),
//             spreadRadius: 2,
//           ),
//         ],
//       ),
//       child: ClipRRect(
//         borderRadius: BorderRadius.circular(32),
//         child: Column(
//           children: [
//             Expanded(
//               flex: 55,
//               child: Stack(
//                 fit: StackFit.expand,
//                 children: [
//                   Hero(
//                     tag: member.name,
//                     child: Image(
//                       image: member.isAsset ? AssetImage(member.imagePath) as ImageProvider : FileImage(File(member.imagePath)),
//                       fit: BoxFit.cover,
//                       errorBuilder: (_, __, ___) => Container(color: Colors.grey[200], child: const Icon(Icons.person, size: 80, color: Colors.grey)),
//                     ),
//                   ),
//                   Positioned(
//                     top: 16,
//                     right: 16,
//                     child: ClipOval(
//                       child: BackdropFilter(
//                         filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
//                         child: GestureDetector(
//                           onTap: () => _confirmDelete(context),
//                           child: Container(
//                             padding: const EdgeInsets.all(10),
//                             decoration: BoxDecoration(
//                               color: Colors.black.withOpacity(0.2),
//                               shape: BoxShape.circle,
//                             ),
//                             child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 20),
//                           ),
//                         ),
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//
//             Expanded(
//               flex: 45,
//               child: Container(
//                 padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
//                 color: Colors.white,
//                 child: Column(
//                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                   children: [
//                     Column(
//                       children: [
//                         Text(
//                           member.name,
//                           style: TextStyle(
//                             fontSize: 26 * fontScale,
//                             fontWeight: FontWeight.w800,
//                             color: const Color(0xFF1F2937),
//                             letterSpacing: -0.5,
//                             height: 1.1,
//                           ),
//                           textAlign: TextAlign.center,
//                           maxLines: 1,
//                           overflow: TextOverflow.ellipsis,
//                         ),
//                         const SizedBox(height: 8),
//                         Container(
//                           padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
//                           decoration: BoxDecoration(
//                             color: member.color.withOpacity(0.5),
//                             borderRadius: BorderRadius.circular(20),
//                           ),
//                           child: Text(
//                             member.relation,
//                             style: TextStyle(
//                               fontSize: 16 * fontScale,
//                               color: const Color(0xFF4B5563),
//                               fontWeight: FontWeight.w600,
//                             ),
//                           ),
//                         ),
//                       ],
//                     ),
//
//                     // --- NEW: DUAL BUTTON ROW ---
//                     Row(
//                       children: [
//                         // CALL BUTTON
//                         Expanded(
//                           child: SizedBox(
//                             height: 60,
//                             child: ElevatedButton(
//                               onPressed: _makePhoneCall,
//                               style: ElevatedButton.styleFrom(
//                                 backgroundColor: const Color(0xFF2D6A4F),
//                                 foregroundColor: Colors.white,
//                                 elevation: 4,
//                                 shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
//                                 padding: EdgeInsets.zero,
//                               ),
//                               child: const Icon(Icons.call_rounded, size: 30),
//                             ),
//                           ),
//                         ),
//                         const SizedBox(width: 12), // Spacing between buttons
//
//                         // WHATSAPP BUTTON
//                         Expanded(
//                           child: SizedBox(
//                             height: 60,
//                             child: ElevatedButton(
//                               onPressed: _openWhatsApp,
//                               style: ElevatedButton.styleFrom(
//                                 backgroundColor: const Color(0xFF25D366), // Official WhatsApp Green
//                                 foregroundColor: Colors.white,
//                                 elevation: 4,
//                                 shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
//                                 padding: EdgeInsets.zero,
//                               ),
//                               child: const Icon(Icons.chat_bubble_rounded, size: 28),
//                             ),
//                           ),
//                         ),
//                       ],
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

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
    final String cleanNumber = member.phoneNumber.replaceAll(RegExp(r'\s+'), '');
    final Uri launchUri = Uri(scheme: 'tel', path: cleanNumber);
    if (await canLaunchUrl(launchUri)) await launchUrl(launchUri);
  }

  // whatsApp Logic
  Future<void> _openWhatsApp() async {
    final String cleanNumber = member.phoneNumber.replaceAll(RegExp(r'[^\d]'), '');

    final Uri url = Uri.parse("https://wa.me/$cleanNumber");

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  String _getInitials(String name) {
    if (name.isEmpty) return "??";
    List<String> names = name.split(" ");
    if (names.length > 1) {
      return "${names[0][0]}${names[1][0]}".toUpperCase();
    }
    return name[0].toUpperCase();
  }

  Widget _buildImageContent() {
    bool hasImage = member.imagePath.isNotEmpty;

    if (!hasImage) {
      // PREMIUM FALLBACK UI
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              member.color,
              member.color.withBlue(200).withOpacity(0.8), // Dynamic shade
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Stylized Initial
              Text(
                _getInitials(member.name),
                style: TextStyle(
                  fontSize: 80 * fontScale,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF1F2937).withOpacity(0.2),
                  letterSpacing: -2,
                ),
              ),
              // Soft icon overlay
              Transform.translate(
                offset: const Offset(0, -20),
                child: Icon(
                  Icons.face_retouching_natural_rounded,
                  size: 40,
                  color: const Color(0xFF1F2937).withOpacity(0.3),
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
        errorBuilder: (context, error, stackTrace) => _buildErrorState(),
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      color: const Color(0xFFF3F4F6),
      child: const Icon(Icons.broken_image_rounded, size: 50, color: Colors.grey),
    );
  }

  // ... (keep your _makePhoneCall and _openWhatsApp methods here)
  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text("Delete Memory?", style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text("Are you sure you want to remove ${member.name}?", style: const TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Keep", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onDelete();
            },
            child: const Text("Remove", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
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
            Expanded(
              flex: 55,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildImageContent(), // Our new smart image/initials builder
                  Positioned(
                    top: 16,
                    right: 16,
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
            Expanded(
              flex: 45,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                color: Colors.white,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
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
                              fontSize: 16 * fontScale,
                              color: const Color(0xFF4B5563),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        // CALL BUTTON
                        Expanded(
                          child: SizedBox(
                            height: 60,
                            child: ElevatedButton(
                              onPressed: _makePhoneCall,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2D6A4F),
                                foregroundColor: Colors.white,
                                elevation: 0, // Flat premium look
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18)),
                              ),
                              child: const Icon(Icons.call_rounded, size: 30),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // WHATSAPP BUTTON
                        Expanded(
                          child: SizedBox(
                            height: 60,
                            child: ElevatedButton(
                              onPressed: _openWhatsApp,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF25D366),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18)),
                              ),
                              child: const Icon(Icons.chat_bubble_rounded,
                                  size: 28),
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

// Note: Add your confirmDelete, makePhoneCall, and openWhatsApp logic here
// exactly as you had them in your original code.
}