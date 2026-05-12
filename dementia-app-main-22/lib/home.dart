import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'app_drawer.dart';
import 'reminders.dart';
import 'chatbot.dart';
import 'chatbot_service.dart';
import 'family_page.dart';
import 'settings_provider.dart';
import 'questionnaire_page.dart';
import 'l10n/app_localizations.dart';
import 'l10n/app_localizations_en.dart';

// ── A single turn in the conversation ──
class _ConversationTurn {
  final String userText;
  final String botText;
  _ConversationTurn({required this.userText, required this.botText});
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late DateTime _now;
  late final Timer _timer;

  // ── Speech-to-text ──
  final SpeechToText _speech = SpeechToText();
  bool _isListening = false;
  bool _speechInitialized = false;
  Timer? _silenceTimer;           // auto-submits after user stops speaking
  int _retryCount = 0;            // prevents infinite error loops
  static const int _maxRetries = 3;

  // ── Text-to-speech ──
  final FlutterTts _tts = FlutterTts();

  // ── Chatbot ──
  final ChatbotService _chatbotService = ChatbotService();

  // ── ValueNotifiers shared with the voice sheet ──
  final ValueNotifier<String> _liveText = ValueNotifier('');
  final ValueNotifier<bool> _aiLoading = ValueNotifier(false);
  final ValueNotifier<bool> _isSpeaking = ValueNotifier(false);
  final ValueNotifier<List<_ConversationTurn>> _history = ValueNotifier([]);
  final ValueNotifier<double> _micVolume = ValueNotifier(0.0); // 0.0–1.0

  String _accumulatedText = '';
  bool _processingVoice = false;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _now = DateTime.now()),
    );

    _tts.setLanguage('en-US');
    _tts.setSpeechRate(0.45);
    _tts.setPitch(1.0);
    setMaleVoice();

    _tts.setCompletionHandler(() async {
      _isSpeaking.value = false;
      _processingVoice = false;
      _accumulatedText = '';
      // Only restart mic if user has the voice popup open (isListening flag
      // was set back to true by _openVoicePopup's onMicTap, not here)
      if (_isListening) {
        await _startListenSession();
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _silenceTimer?.cancel();
    _speech.stop();
    _tts.stop();
    _liveText.dispose();
    _aiLoading.dispose();
    _isSpeaking.dispose();
    _history.dispose();
    _micVolume.dispose();
    super.dispose();
  }

  // ── Male TTS voice ──
  Future<void> setMaleVoice() async {
    var voices = await _tts.getVoices;
    for (var voice in voices) {
      if (voice["locale"] == "en-US" &&
          voice["name"].toString().toLowerCase().contains("male")) {
        await _tts.setVoice(voice);
        break;
      }
    }
  }

  // ── Greeting ──
  String _getGreeting(AppLocalizations l) {
    final hour = _now.hour;
    if (hour >= 5 && hour < 12) return l.goodMorning;
    if (hour >= 12 && hour < 17) return l.goodAfternoon;
    if (hour >= 17 && hour < 21) return l.goodEvening;
    return l.goodNight;
  }

  // ═══════════════════════════════════════
  // 🚨 EMERGENCY LOGIC
  // ═══════════════════════════════════════

  /// Returns a clickable Google Maps link for the user's current position.
  /// Returns a plain-text fallback string if permission or GPS is unavailable.
  Future<String> _getLocationLink() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return "Location unavailable";
    }

    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return "Location services OFF";
    }

    final Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    return "https://www.google.com/maps?q=${position.latitude},${position.longitude}";
  }

  /// Strips all non-digits, removes leading 0, prepends India country code (91)
  /// so WhatsApp always gets a clean international number e.g. "919876543210".
  /// Change the country code prefix if your users are outside India.
  String _formatNumber(String number) {
    number = number.replaceAll(RegExp(r'\D'), ''); // remove non-digits
    if (number.startsWith('0')) number = number.substring(1); // drop leading 0
    if (!number.startsWith('91')) number = '91$number'; // add country code
    return number;
  }

  /// Opens WhatsApp for [number] with [message] pre-filled.
  /// Falls back to the native SMS app if WhatsApp is not installed.
  Future<void> _sendWhatsApp(String number, String message) async {
    final Uri whatsappUrl = Uri.parse(
      "https://wa.me/$number?text=${Uri.encodeComponent(message)}",
    );

    if (await canLaunchUrl(whatsappUrl)) {
      await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
    } else {
      // WhatsApp not installed — fall back to native SMS app
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("WhatsApp not installed — opening SMS instead"),
          ),
        );
      }
      final Uri smsUrl = Uri.parse(
        "sms:$number?body=${Uri.encodeComponent(message)}",
      );
      await launchUrl(smsUrl);
    }
  }

  /// Writes an emergency document to Firestore so the family app can listen
  /// and trigger a push notification in real time.
  Future<void> _sendFirebaseAlert(String location) async {
    try {
      await FirebaseFirestore.instance.collection('emergencies').add({
        'userId': FirebaseAuth.instance.currentUser?.uid,
        'location': location,
        'status': 'EMERGENCY',
        'timestamp': FieldValue.serverTimestamp(), // server time, not device
      });
      debugPrint("Firebase alert sent ✅");
    } catch (e) {
      debugPrint("Firebase alert failed: $e");
      // Non-fatal — call and WhatsApp still proceed
    }
  }

  Future<void> _handleEmergency(AppLocalizations l) async {
    final prefs = await SharedPreferences.getInstance();

    // ── Collect all saved emergency numbers ──────────────────────────────────
    final String? primaryRaw = prefs.getString('emergency_number');
    final List<String> extraRaw =
        (prefs.getStringList('emergency_numbers') ?? []);

    final List<String> allRaw = [
      if (primaryRaw != null && primaryRaw.isNotEmpty) primaryRaw,
      ...extraRaw,
    ];

    if (!mounted) return;

    if (allRaw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.noEmergencyNumber)),
      );
      return;
    }

    final List<String> numbers =
        allRaw.map(_formatNumber).toSet().toList(); // deduplicate

    // ── Show loading spinner while fetching location ─────────────────────────
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    await Permission.location.request();
    final String location = await _getLocationLink();

    // ── Dismiss spinner ──────────────────────────────────────────────────────
    if (mounted) Navigator.pop(context);

    // ── Build WhatsApp message — graceful text if location failed ────────────
    final String waMessage = location.startsWith("http")
        ? "🚨 EMERGENCY!\nI need help.\n\n📍 My location:\n$location"
        : "🚨 EMERGENCY!\nI need help.\n\n⚠️ Location not available.\nPlease contact me immediately!";

    // ── STEP 1: Voice feedback ───────────────────────────────────────────────
    await _tts.speak("Calling your emergency contact now");

    // ── STEP 2: Call immediately — top priority ──────────────────────────────
    await FlutterPhoneDirectCaller.callNumber(numbers.first);

    // ── STEP 3: Firebase alert — runs in background, no UI conflict ──────────
    //    unawaited intentionally: don't block WhatsApp on network latency
    _sendFirebaseAlert(location);

    // ── STEP 4: Wait for dialler to settle, then send WhatsApp backup ────────
    await Future.delayed(const Duration(seconds: 5));

    for (final num in numbers) {
      await _sendWhatsApp(num, waMessage);
    }
  }

  Future<void> _confirmAndCall(AppLocalizations l) async {
    final confirm = await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l.emergencyAlert),
        content: Text(l.emergencyMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.call),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _handleEmergency(l);
    }
  }

  // ═══════════════════════════════════════
  // 🎤 VOICE ASSISTANT LOGIC
  // ═══════════════════════════════════════

  Future<void> _startListenSession() async {
    if (!_isListening || _processingVoice) return;

    // ── Initialize once per popup session ───────────────────────────────────
    if (!_speechInitialized) {
      final bool available = await _speech.initialize(
        onError: (error) {
          debugPrint("STT error: ${error.errorMsg}");
          _micVolume.value = 0.0;
          final recoverable = error.errorMsg != 'error_permanent' &&
              error.errorMsg != 'error_not_recognized' &&
              _retryCount < _maxRetries;
          if (_isListening && !_processingVoice && recoverable) {
            _retryCount++;
            Future.delayed(const Duration(milliseconds: 600), _startListenSession);
          } else {
            // Give up — let user tap mic again
            _isListening = false;
            _micVolume.value = 0.0;
          }
        },
        onStatus: (status) {
          debugPrint("STT status: $status");
          if (status == 'done' && _isListening && !_processingVoice) {
            _micVolume.value = 0.0;
            Future.delayed(const Duration(milliseconds: 300), _startListenSession);
          }
        },
      );
      if (!available) {
        debugPrint("Speech recognition unavailable");
        _isListening = false;
        return;
      }
      _speechInitialized = true;
    }

    if (!_isListening || _processingVoice) return;
    _retryCount = 0;

    await _speech.listen(
      listenFor: const Duration(seconds: 45),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      cancelOnError: false,
      onSoundLevelChange: (level) {
        // level ranges roughly -2 to 10 on Android — normalize to 0.0–1.0
        final normalized = ((level + 2) / 12).clamp(0.0, 1.0);
        _micVolume.value = normalized;
      },
      onResult: (SpeechRecognitionResult result) {
        _silenceTimer?.cancel();

        if (result.finalResult) {
          _micVolume.value = 0.0;
          if (result.recognizedWords.isNotEmpty) {
            _accumulatedText +=
                (_accumulatedText.isEmpty ? '' : ' ') + result.recognizedWords;
          }
          _liveText.value = _accumulatedText;
          if (_accumulatedText.isNotEmpty) {
            _processVoiceAuto();
          }
        } else {
          // Show partial text live
          _liveText.value = _accumulatedText.isEmpty
              ? result.recognizedWords
              : '$_accumulatedText ${result.recognizedWords}';

          // Auto-submit after 2.5 s of no new words (dementia UX — short pauses)
          if (result.recognizedWords.isNotEmpty) {
            _silenceTimer = Timer(const Duration(milliseconds: 2500), () {
              if (_isListening && !_processingVoice && _liveText.value.isNotEmpty) {
                _accumulatedText = _liveText.value.trim();
                _processVoiceAuto();
              }
            });
          }
        }
      },
    );
  }

  Future<void> _processVoiceAuto() async {
    if (_processingVoice) return;
    _processingVoice = true;
    _isListening = false;
    _silenceTimer?.cancel();
    _micVolume.value = 0.0;

    await _speech.stop();

    final captured = _liveText.value.trim();
    if (captured.isEmpty) {
      _processingVoice = false;
      return;
    }

    final userMessage = captured;
    _accumulatedText = '';
    _liveText.value = '';
    _aiLoading.value = true;

    try {
      // ✅ FIX: pass the SAME full profileText that the chat screen sends so
      // the backend reminder parser has identical context in both code paths.
      // Without this, voice reminders silently failed (backend got no user_id
      // context and couldn't parse timezone / name correctly).
      final settings = SettingsProvider.of(context);
      final String? response = await _chatbotService.sendMessage(
        userMessage,
        profileText: '''
User Profile:
- Name: ${settings.username.isNotEmpty ? settings.username : 'Not specified'}
- Gender: ${settings.gender.isNotEmpty ? settings.gender : 'Not specified'}
- Age: ${settings.age > 0 ? '${settings.age} years' : 'Not specified'}
- Address: ${settings.address.isNotEmpty ? settings.address : 'Not specified'}
- Language: English
''',
      );
      final String answer = (response != null && response.trim().isNotEmpty)
          ? response.trim()
          : "I'm sorry, I didn't quite catch that. Could you say that again?";

      final turns = List<_ConversationTurn>.from(_history.value);
      turns.add(_ConversationTurn(userText: userMessage, botText: answer));
      _history.value = turns;

      _aiLoading.value = false;
      _isSpeaking.value = true;
      await _tts.stop();
      await _tts.speak(answer);
      // After TTS finishes → completionHandler re-enables mic automatically
    } catch (e) {
      debugPrint("Voice processing error: $e");
      _aiLoading.value = false;
      final turns = List<_ConversationTurn>.from(_history.value);
      turns.add(_ConversationTurn(
          userText: userMessage,
          botText: "Sorry, something went wrong. Please try again."));
      _history.value = turns;
      _processingVoice = false;
      // TTS won't fire on error — re-enable mic so user isn't stuck
      _isListening = true;
      await _startListenSession();
    }
  }

  void _openVoicePopup(AppLocalizations l) {
    // Reset all state fresh each time popup opens
    _accumulatedText = '';
    _liveText.value = '';
    _aiLoading.value = false;
    _isSpeaking.value = false;
    _history.value = [];
    _micVolume.value = 0.0;
    _isListening = false;
    _processingVoice = false;
    _speechInitialized = false;
    _retryCount = 0;
    _silenceTimer?.cancel();

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _VoiceSheet(
        l10n: l,
        liveText: _liveText,
        aiLoading: _aiLoading,
        isSpeaking: _isSpeaking,
        history: _history,
        micVolume: _micVolume,
        isListeningGetter: () => _isListening,
        onMicTap: (setS) async {
          if (!_isListening) {
            setS(() => _isListening = true);
            _processingVoice = false;
            _accumulatedText = '';
            _retryCount = 0;
            await _startListenSession();
          } else {
            _silenceTimer?.cancel();
            await _speech.stop();
            setS(() => _isListening = false);
            _processingVoice = false;
            _micVolume.value = 0.0;
          }
        },
        onClose: () async {
          _silenceTimer?.cancel();
          await _speech.stop();
          await _tts.stop();
          _isListening = false;
          _processingVoice = false;
          _speechInitialized = false;
          _micVolume.value = 0.0;
          Navigator.pop(ctx);
        },
      ),
    );
  }

  // ═══════════════════════════════════════
  // 🏠 BUILD
  // ═══════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final settings = SettingsProvider.of(context);
    final user = FirebaseAuth.instance.currentUser;
    final l = AppLocalizations.of(context) ?? AppLocalizationsEn();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F5),
      drawer: const AppDrawer(),
      body: Builder(
        builder: (scaffoldContext) {
          return SafeArea(
            child: Column(
              children: [
                // ── HEADER ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 35),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF2D6A4F), Color(0xFF26A69A)],
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Top bar: menu + Memoir branding ──────
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.menu,
                                      color: Colors.white, size: 28),
                                  onPressed: () {
                                    if (!mounted) return;
                                    Scaffold.of(scaffoldContext).openDrawer();
                                  },
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                                const SizedBox(width: 8),
                                Image.asset(
                                  'assets/images/logo.png',
                                  width: 34,
                                  height: 34,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.psychology_rounded,
                                    color: Colors.white,
                                    size: 34,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Memoir',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _getGreeting(l),
                              style: TextStyle(
                                fontSize: 26 * settings.fontSizeMultiplier,
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              user?.displayName ?? "User",
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 38 * settings.fontSizeMultiplier,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 12,
                              runSpacing: 6,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.access_time,
                                        color: Colors.white, size: 20),
                                    const SizedBox(width: 6),
                                    Text(
                                      DateFormat('hh:mm a').format(_now),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.calendar_today,
                                        color: Colors.white, size: 20),
                                    const SizedBox(width: 6),
                                    Text(
                                      DateFormat('EEE, MMM d').format(_now),
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 16),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // ── MIC BUTTON ──
                      GestureDetector(
                        onTap: () => _openVoicePopup(l),
                        child: Container(
                          height: 115,
                          width: 115,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.25),
                                blurRadius: 25,
                                offset: const Offset(0, 10),
                              )
                            ],
                          ),
                          child: const Icon(
                            Icons.mic,
                            size: 55,
                            color: Color(0xFF2D6A4F),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── GRID ──
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: GridView.count(
                      crossAxisCount: 2,
                      crossAxisSpacing: 20,
                      mainAxisSpacing: 20,
                      children: [
                        _buildCard(
                          icon: Icons.notifications_active_rounded,
                          label: l.reminders,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const ReminderPage()),
                          ),
                        ),
                        _buildCard(
                          icon: Icons.chat_rounded,
                          label: l.chatBuddy,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const ChatScreen()),
                          ),
                        ),
                        _buildCard(
                          icon: Icons.favorite_rounded,
                          label: l.family,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const FamilyPage()),
                          ),
                        ),
                        _buildCard(
                          icon: Icons.psychology,
                          label: l.cognitiveTest,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const QuestionnairePage()),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── EMERGENCY BUTTON ──
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      minimumSize: const Size(double.infinity, 70),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(35),
                      ),
                      elevation: 8,
                    ),
                    onPressed: () => _confirmAndCall(l),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.warning,
                            color: Colors.white, size: 28),
                        const SizedBox(width: 10),
                        Text(
                          l.emergencyHelp,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCard({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 15,
              offset: const Offset(0, 6),
            )
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 42, color: const Color(0xFF004D40)),
            const SizedBox(height: 16),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 18,
                color: Color(0xFF004D40),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// VOICE SHEET — improved UI with volume animation, stop button,
//               and dementia-friendly large text
// ═══════════════════════════════════════════════════════════════
class _VoiceSheet extends StatefulWidget {
  final AppLocalizations l10n;
  final ValueNotifier<String> liveText;
  final ValueNotifier<bool> aiLoading;
  final ValueNotifier<bool> isSpeaking;
  final ValueNotifier<List<_ConversationTurn>> history;
  final ValueNotifier<double> micVolume;
  final bool Function() isListeningGetter;
  final Future<void> Function(StateSetter) onMicTap;
  final VoidCallback onClose;

  const _VoiceSheet({
    required this.l10n,
    required this.liveText,
    required this.aiLoading,
    required this.isSpeaking,
    required this.history,
    required this.micVolume,
    required this.isListeningGetter,
    required this.onMicTap,
    required this.onClose,
  });

  @override
  State<_VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<_VoiceSheet>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    widget.history.addListener(_scrollToBottom);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    widget.history.removeListener(_scrollToBottom);
    _scrollController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 120), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.l10n;

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        children: [
          // ── Drag handle ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          // ── Header row: title + close ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.smart_toy_rounded,
                    color: Color(0xFF2D6A4F), size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    "Voice Assistant",
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1B4332),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded,
                      color: Colors.grey.shade500, size: 24),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),

          // ── Animated status bar ──────────────────────────────────────────
          ValueListenableBuilder<bool>(
            valueListenable: widget.isSpeaking,
            builder: (_, speaking, __) =>
                ValueListenableBuilder<bool>(
              valueListenable: widget.aiLoading,
              builder: (_, loading, __) {
                final bool isListening = widget.isListeningGetter();
                return _StatusBanner(
                  loading: loading,
                  speaking: speaking,
                  listening: isListening,
                  l: l,
                  pulseController: _pulseController,
                );
              },
            ),
          ),

          const Divider(height: 1),

          // ── Chat history ─────────────────────────────────────────────────
          Expanded(
            child: ValueListenableBuilder<List<_ConversationTurn>>(
              valueListenable: widget.history,
              builder: (_, turns, __) {
                if (turns.isEmpty) {
                  return _EmptyHistoryPlaceholder(l: l);
                }
                return ListView.builder(
                  controller: _scrollController,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: turns.length,
                  itemBuilder: (_, i) => _ChatBubblePair(turn: turns[i]),
                );
              },
            ),
          ),

          // ── Live transcription box ───────────────────────────────────────
          ValueListenableBuilder<String>(
            valueListenable: widget.liveText,
            builder: (_, text, __) {
              final bool isListening = widget.isListeningGetter();
              if (text.isEmpty && !isListening) return const SizedBox.shrink();
              return ValueListenableBuilder<double>(
                valueListenable: widget.micVolume,
                builder: (_, vol, __) => AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  constraints: const BoxConstraints(maxHeight: 72),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isListening
                          ? Color.lerp(
                                  const Color(0xFF2D6A4F),
                                  Colors.green.shade300,
                                  vol)!
                              .withOpacity(0.7)
                          : Colors.transparent,
                      width: 1.5 + vol * 1.5,
                    ),
                  ),
                  child: SingleChildScrollView(
                    reverse: true,
                    child: Text(
                      text.isEmpty ? l.voiceSaySomething : text,
                      style: TextStyle(
                        fontSize: 15,
                        color: text.isEmpty
                            ? Colors.grey.shade400
                            : Colors.black87,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // ── Loading indicator ────────────────────────────────────────────
          ValueListenableBuilder<bool>(
            valueListenable: widget.aiLoading,
            builder: (_, loading, __) {
              if (!loading) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.orange.shade600),
                    ),
                    const SizedBox(width: 8),
                    Text(l.voiceGettingReply,
                        style: TextStyle(
                            color: Colors.orange.shade600, fontSize: 13)),
                  ],
                ),
              );
            },
          ),

          // ── Mic button row ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            child: StatefulBuilder(
              builder: (_, setS) => ValueListenableBuilder<bool>(
                valueListenable: widget.aiLoading,
                builder: (_, loading, __) =>
                    ValueListenableBuilder<bool>(
                  valueListenable: widget.isSpeaking,
                  builder: (_, speaking, __) {
                    final bool isListening = widget.isListeningGetter();
                    final bool busy = loading;

                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Mic / Stop button
                        GestureDetector(
                          onTap: busy
                              ? null
                              : () => widget.onMicTap(setS),
                          child: ValueListenableBuilder<double>(
                            valueListenable: widget.micVolume,
                            builder: (_, vol, __) {
                              final double scale = isListening
                                  ? 1.0 + vol * 0.18
                                  : 1.0;
                              return AnimatedScale(
                                scale: scale,
                                duration: const Duration(milliseconds: 80),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  height: 72,
                                  width: 72,
                                  decoration: BoxDecoration(
                                    color: busy
                                        ? Colors.grey.shade300
                                        : speaking
                                            ? Colors.blue.shade400
                                            : isListening
                                                ? Colors.red.shade400
                                                : const Color(0xFF2D6A4F),
                                    shape: BoxShape.circle,
                                    boxShadow: busy
                                        ? []
                                        : [
                                            BoxShadow(
                                              color: (isListening
                                                      ? Colors.red
                                                      : speaking
                                                          ? Colors.blue
                                                          : const Color(
                                                              0xFF2D6A4F))
                                                  .withOpacity(
                                                      0.35 + vol * 0.25),
                                              blurRadius: 16 + vol * 10,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                  ),
                                  child: Icon(
                                    speaking
                                        ? Icons.stop_rounded
                                        : isListening
                                            ? Icons.mic_rounded
                                            : Icons.mic_none_rounded,
                                    size: 32,
                                    color: busy
                                        ? Colors.grey
                                        : Colors.white,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                        const SizedBox(width: 16),

                        // Status hint text
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                busy
                                    ? '⏳ ${l.voiceProcessing}'
                                    : speaking
                                        ? '🔊 ${l.voicePlayingReply}'
                                        : isListening
                                            ? '🎤 ${l.voiceSpeakNow}'
                                            : '👆 ${l.voiceTapMicToSpeak}',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: busy
                                      ? Colors.grey.shade400
                                      : speaking
                                          ? Colors.blue.shade600
                                          : isListening
                                              ? const Color(0xFF2D6A4F)
                                              : Colors.grey.shade500,
                                ),
                              ),
                              if (isListening && !busy)
                                Text(
                                  "Tap mic to stop",
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade400),
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Status banner shown below header ────────────────────────────────────────
class _StatusBanner extends StatelessWidget {
  final bool loading;
  final bool speaking;
  final bool listening;
  final AppLocalizations l;
  final AnimationController pulseController;

  const _StatusBanner({
    required this.loading,
    required this.speaking,
    required this.listening,
    required this.l,
    required this.pulseController,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    String text;
    IconData icon;

    if (loading) {
      bg = Colors.orange.shade50;
      fg = Colors.orange.shade700;
      text = l.voiceThinking;
      icon = Icons.hourglass_top_rounded;
    } else if (speaking) {
      bg = Colors.blue.shade50;
      fg = Colors.blue.shade700;
      text = '${l.voiceSpeaking}...';
      icon = Icons.volume_up_rounded;
    } else if (listening) {
      bg = const Color(0xFFE8F5E9);
      fg = const Color(0xFF2D6A4F);
      text = l.voiceListening;
      icon = Icons.hearing_rounded;
    } else {
      bg = Colors.grey.shade50;
      fg = Colors.grey.shade500;
      text = l.voiceTapToStart;
      icon = Icons.touch_app_rounded;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (listening)
            AnimatedBuilder(
              animation: pulseController,
              builder: (_, __) => Icon(icon,
                  color: fg.withOpacity(0.5 + pulseController.value * 0.5),
                  size: 18),
            )
          else
            Icon(icon, color: fg, size: 18),
          const SizedBox(width: 8),
          Text(text,
              style: TextStyle(
                  color: fg, fontWeight: FontWeight.w600, fontSize: 14)),
        ],
      ),
    );
  }
}

// ── Empty state placeholder ──────────────────────────────────────────────────
class _EmptyHistoryPlaceholder extends StatelessWidget {
  final AppLocalizations l;
  const _EmptyHistoryPlaceholder({required this.l});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.record_voice_over_rounded,
              size: 60, color: Colors.grey.shade200),
          const SizedBox(height: 14),
          Text(l.voiceTapMicAndSpeak,
              style:
                  TextStyle(color: Colors.grey.shade400, fontSize: 16)),
          const SizedBox(height: 6),
          Text(l.voiceReplyAutomatic,
              style:
                  TextStyle(color: Colors.grey.shade300, fontSize: 13)),
        ],
      ),
    );
  }
}

// ── One user + bot bubble pair ───────────────────────────────────────────────
class _ChatBubblePair extends StatelessWidget {
  final _ConversationTurn turn;
  const _ChatBubblePair({required this.turn});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // User bubble — right aligned
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.only(bottom: 6, left: 60),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFF2D6A4F),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(4),
              ),
            ),
            child: Text(turn.userText,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.4)),
          ),
        ),
        // Bot bubble — left aligned
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 18, right: 60),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF7F2),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
              border: Border.all(
                  color: const Color(0xFF2D6A4F).withOpacity(0.15)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.smart_toy_rounded,
                      color: Color(0xFF2D6A4F), size: 15),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(turn.botText,
                      style: const TextStyle(
                          color: Color(0xFF1B4332),
                          fontSize: 15,
                          height: 1.5)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}