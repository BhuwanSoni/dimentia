import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

// ═══════════════════════════════════════════════════════════════
// 🚨 EMERGENCY SERVICE  — MethodChannel bridge to Android
// ═══════════════════════════════════════════════════════════════

class EmergencyService {
  static const MethodChannel _channel = MethodChannel('emergency_channel');

  /// Triggers the native Android emergency lock screen.
  /// [phoneNumber] is the caregiver's number stored in user profile.
  static Future<void> triggerEmergency({required String phoneNumber}) async {
    try {
      await _channel.invokeMethod('startEmergency', {
        'phoneNumber': phoneNumber,
      });
    } on PlatformException catch (e) {
      debugPrint("Emergency channel error: ${e.message}");
    } catch (e) {
      debugPrint("Emergency error: $e");
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// 🚨 EMERGENCY BUTTON WIDGET
// Drop this anywhere in your UI — matches Memoir AI green theme
// ═══════════════════════════════════════════════════════════════

class EmergencyButton extends StatelessWidget {
  /// Caregiver phone number — pull from SettingsProvider or Firestore
  final String caregiverPhone;
  final bool isHindi;

  const EmergencyButton({
    super.key,
    required this.caregiverPhone,
    this.isHindi = false,
  });

  String get _label       => isHindi ? '🚨 आपातकाल'        : '🚨 EMERGENCY';
  String get _dialogTitle => isHindi ? 'आपातकालीन कॉल'     : 'Emergency Call';
  String get _dialogBody  => isHindi
      ? 'क्या आप अपने देखभालकर्ता को कॉल करना चाहते हैं?\n📞 $caregiverPhone'
      : 'Do you want to call your caregiver?\n📞 $caregiverPhone';
  String get _cancel      => isHindi ? 'रद्द करें'          : 'Cancel';
  String get _call        => isHindi ? 'कॉल करें'           : 'Call';

  Future<void> _handleEmergency(BuildContext context) async {
    // ✅ Step 1: Show confirmation dialog (Play Store requirement for elderly UX)
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Text('🚨', style: TextStyle(fontSize: 24)),
            const SizedBox(width: 8),
            Text(_dialogTitle,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Color(0xFF1F2937))),
          ],
        ),
        content: Text(
          _dialogBody,
          style: const TextStyle(fontSize: 16, color: Color(0xFF374151), height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_cancel,
                style: const TextStyle(color: Colors.grey, fontSize: 15)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: Text(_call,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // ✅ Step 2: Check PHONE permission (only needed if using ACTION_CALL)
    // With ACTION_DIAL this is optional, but good practice
    final status = await Permission.phone.request();
    if (!status.isGranted && !status.isLimited) {
      // Still proceed — ACTION_DIAL doesn't need permission
      debugPrint("Phone permission not granted, proceeding with ACTION_DIAL");
    }

    // ✅ Step 3: Trigger native emergency screen
    await EmergencyService.triggerEmergency(phoneNumber: caregiverPhone);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _handleEmergency(context),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFD32F2F), Color(0xFFB71C1C)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD32F2F).withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🚨', style: TextStyle(fontSize: 32)),
            const SizedBox(height: 6),
            Text(
              _label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isHindi ? 'देखभालकर्ता को कॉल करें' : 'Call Caregiver Instantly',
              style: TextStyle(
                color: Colors.white.withOpacity(0.85),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}