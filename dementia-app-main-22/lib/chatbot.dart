import 'package:flutter/material.dart';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'settings_provider.dart';
import 'chatbot_service.dart';

// ═══════════════════════════════════════════════════════════════
// 🌐 MULTILINGUAL STRINGS  (English + Hindi)
// ═══════════════════════════════════════════════════════════════
class _L {
  final bool isHindi;
  const _L(this.isHindi);

  // ── App bar ───────────────────────────────────────────────
  String get appTitle => 'Memoir AI';
  String hereFor(String name) =>
      isHindi ? 'आपके साथ हूँ, $name 💙' : 'Here for you, $name 💙';
  String get alwaysHere => isHindi ? 'हमेशा आपके साथ 💙' : 'Always here for you 💙';

  // ── Welcome ───────────────────────────────────────────────
  String welcome(String name) => isHindi
      ? 'नमस्ते $name! 😊 मैं Memoir हूँ, आपका व्यक्तिगत स्मृति सहायक।\n\n'
        'मैं आपकी मदद करता हूँ:\n'
        '• ⏰ रिमाइंडर सेट करने में\n'
        '• 📍 आपकी रखी चीज़ें याद रखने में\n'
        '• 🧠 ज़रूरी यादें सुरक्षित रखने में\n\n'
        'किसी भी समय /help टाइप करें! 💙'
      : 'Hi $name! 😊 I\'m Memoir, your personal memory companion.\n\n'
        'I\'m here to help you with:\n'
        '• ⏰ Setting reminders\n'
        '• 📍 Remembering where you kept things\n'
        '• 🧠 Keeping track of important memories\n\n'
        'Type /help anytime to see everything I can do! 💙';

  // ── Chips ─────────────────────────────────────────────────
  String get chipReminder    => isHindi ? '⏰ रिमाइंडर सेट करें' : '⏰ Set a reminder';
  String get chipFindItem    => isHindi ? '📍 चीज़ ढूंढें'       : '📍 Find my item';
  String get chipMyReminders => isHindi ? '📋 मेरे रिमाइंडर'     : '📋 My reminders';
  String get chipHelp        => isHindi ? '❓ सहायता'             : '❓ Help';

  // ── Input hint ────────────────────────────────────────────
  String get inputHint =>
      isHindi ? 'कुछ भी पूछें या /help टाइप करें...' : 'Ask me anything or type /help...';

  // ── Help tooltip ──────────────────────────────────────────
  String get helpTooltip =>
      isHindi ? 'देखें मैं क्या कर सकता हूँ' : 'See what I can do';

  // ── Reminder sheet ────────────────────────────────────────
  String get reminderSheetTitle =>
      isHindi ? '⏰ रिमाइंडर सेट करें' : '⏰ Set a Reminder';
  String get reminderSheetSubtitle =>
      isHindi ? 'जानकारी भरें, मैं याद दिलाऊंगा! 😊' : 'Fill in the details and I\'ll remind you! 😊';
  String get reminderTaskLabel =>
      isHindi ? 'मुझे क्या याद दिलाना है?' : 'What should I remind you about?';
  String get reminderTaskHint =>
      isHindi ? 'जैसे: दवाई लेना, डॉक्टर अपॉइंटमेंट…' : 'e.g. Take medicine, Doctor appointment…';
  String get reminderDateLabel  => isHindi ? 'तारीख'        : 'Date';
  String get reminderTimeLabel  => isHindi ? 'समय'          : 'Time';
  String get reminderRepeatLabel => isHindi ? 'दोहराएं'      : 'Repeat';
  String get repeatOnce         => isHindi ? 'एक बार'       : 'One-time';
  String get repeatDaily        => isHindi ? 'रोज़'          : 'Daily';
  String get repeatWeekly       => isHindi ? 'साप्ताहिक'     : 'Weekly';
  String get reminderConfirm    => isHindi ? 'रिमाइंडर सेट करें 🎉' : 'Set Reminder 🎉';
  String get reminderEmptyWarn  =>
      isHindi ? 'कृपया बताएं क्या याद दिलाना है 😊' : 'Please enter what to remind you about 😊';

  // ── Find item sheet ───────────────────────────────────────
  String get findSheetTitle =>
      isHindi ? '📍 मेरी चीज़ ढूंढें' : '📍 Find My Item';
  String get findSheetSubtitle =>
      isHindi ? 'चीज़ पर टैप करें 😊' : 'Tap an item to find where you kept it 😊';
  String get findSearchHint => isHindi ? 'चीज़ें खोजें…'     : 'Search items…';
  String get findEmpty =>
      isHindi ? 'अभी कोई चीज़ सेव नहीं है।\nमुझे बताएं आप चीज़ें कहाँ रखते हैं!' : 'No items stored yet.\nTell me where you keep things!';
  String get findNoMatch =>
      isHindi ? 'कोई मिलान नहीं मिला।' : 'No items match your search.';

  // ── Errors ────────────────────────────────────────────────
  String get errorMsg =>
      isHindi ? 'ओह नहीं, कनेक्शन में थोड़ी दिक्कत हुई। 😔 फिर से कोशिश करें!' : 'Oh no, I had a little trouble connecting. 😔 Please try again!';
  String get errorDirectMsg =>
      isHindi ? 'ओह नहीं, कुछ गड़बड़ हो गई। 😔 फिर से कोशिश करें!' : 'Oh no, I had a little trouble. 😔 Please try again!';

  // ── Backend messages ──────────────────────────────────────
  String reminderMsg(String task, String time, String dateStr, String recurStr) =>
      isHindi
          ? 'मुझे $task की याद दिलाएं $time बजे $dateStr को$recurStr'
          : 'Remind me to $task at $time on $dateStr$recurStr';

  String findMsg(String name) =>
      isHindi ? 'मेरा $name कहाँ है?' : 'Where is my $name?';

  String get myRemindersMsg =>
      isHindi ? 'मेरे रिमाइंडर क्या हैं?' : 'What are my reminders?';

  // ── Month names ───────────────────────────────────────────
  String monthName(int m) {
    if (isHindi) {
      const months = [
        '', 'जनवरी', 'फ़रवरी', 'मार्च', 'अप्रैल', 'मई', 'जून',
        'जुलाई', 'अगस्त', 'सितंबर', 'अक्टूबर', 'नवंबर', 'दिसंबर'
      ];
      return months[m];
    }
    const months = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[m];
  }

  // ── Language toggle label ─────────────────────────────────
  String get langToggle => isHindi ? 'EN' : 'हिं';
}

// ═══════════════════════════════════════════════════════════════
// 💬  CHAT SCREEN
// ═══════════════════════════════════════════════════════════════
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController      _scrollController = ScrollController();
  final TextEditingController _controller       = TextEditingController();
  final ChatbotService        _chatbotService   = ChatbotService();
  final FocusNode             _focusNode        = FocusNode();

  bool _isLoading      = false;
  bool _showEmoji      = false;
  bool _welcomeSent    = false;
  bool _showQuickChips = true;
  bool _isHindi        = false; // ← language toggle

  // ── Reminder sheet state ──────────────────────────────────
  String    _reminderTask      = '';
  DateTime  _reminderDate      = DateTime.now();
  TimeOfDay _reminderTime      = TimeOfDay.now();
  String    _reminderRecurring = 'none';

  // ── Find-item sheet state ─────────────────────────────────
  List<Map<String, dynamic>> _storedItems = [];
  bool _itemsLoading = false;

  final user = FirebaseAuth.instance.currentUser;
  final List<Map<String, dynamic>> messages = [];

  _L get _l => _L(_isHindi);

  // ─────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_welcomeSent) {
      final settings = SettingsProvider.of(context);
      final name     = settings.username.isNotEmpty ? settings.username : 'there';
      setState(() {
        messages.add({
          'sender': 'bot',
          'text': _l.welcome(name),
          'time': DateTime.now(),
        });
      });
      _welcomeSent = true;
    }
  }

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) setState(() => _showEmoji = false);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────
  // Language toggle
  // ─────────────────────────────────────────────────────────
  void _toggleLanguage() => setState(() => _isHindi = !_isHindi);

  // ─────────────────────────────────────────────────────────
  // Messaging
  // ─────────────────────────────────────────────────────────
  Future<void> _sendMessage() async {
    final userInput = _controller.text.trim();
    if (userInput.isEmpty || _isLoading) return;

    _controller.clear();
    setState(() {
      messages.add({'sender': 'user', 'text': userInput, 'time': DateTime.now()});
      _isLoading      = true;
      _showEmoji      = false;
      _showQuickChips = false;
    });
    _scrollToBottom();

    try {
      final settings    = SettingsProvider.of(context);
      final botResponse = await _chatbotService.sendMessage(
        userInput,
        profileText: _buildProfileText(settings),
      );
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        messages.add({'sender': 'bot', 'text': botResponse, 'time': DateTime.now()});
      });
      // ✅ FIX: Refresh stored items cache after every message so the
      // "Find My Item" sheet always shows the latest data without needing
      // to close and reopen the app.
      _refreshStoredItems();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        messages.add({'sender': 'bot', 'text': _l.errorMsg, 'time': DateTime.now()});
      });
    }
    _scrollToBottom();
  }

  // ✅ FIX: Silently refresh the object_memories cache in the background.
  // Called after every bot reply so _storedItems is always up-to-date.
  Future<void> _refreshStoredItems() async {
    try {
      final uid = user?.uid ?? '';
      if (uid.isEmpty) return;
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('object_memories')
          .get();
      if (!mounted) return;
      setState(() {
        _storedItems = snapshot.docs.map((doc) {
          final data = doc.data();
          return <String, dynamic>{
            'object_name': data['object_name'] ?? data['identifier'] ?? '',
            'identifier':  data['identifier']  ?? '',
            'location':    data['location']    ?? 'Unknown',
          };
        }).toList();
      });
    } catch (_) {
      // Silent — this is a background refresh, don't disrupt the user
    }
  }

  Future<void> _sendDirectMessage(String text) async {
    try {
      final settings    = SettingsProvider.of(context);
      final botResponse = await _chatbotService.sendMessage(
        text,
        profileText: _buildProfileText(settings),
      );
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        messages.add({'sender': 'bot', 'text': botResponse, 'time': DateTime.now()});
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        messages.add({'sender': 'bot', 'text': _l.errorDirectMsg, 'time': DateTime.now()});
      });
    }
    _scrollToBottom();
  }

  String _buildProfileText(dynamic settings) => '''
User Profile:
- Name: ${settings.username.isNotEmpty ? settings.username : 'Not specified'}
- Gender: ${settings.gender.isNotEmpty ? settings.gender : 'Not specified'}
- Age: ${settings.age > 0 ? '${settings.age} years' : 'Not specified'}
- Address: ${settings.address.isNotEmpty ? settings.address : 'Not specified'}
- Language: ${_isHindi ? 'Hindi' : 'English'}
''';

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _toggleEmojiPicker() {
    if (_showEmoji) {
      setState(() => _showEmoji = false);
      _focusNode.requestFocus();
    } else {
      _focusNode.unfocus();
      setState(() => _showEmoji = true);
    }
  }

  // ─────────────────────────────────────────────────────────
  // ⏰ Reminder sheet
  // ─────────────────────────────────────────────────────────
  void _openReminderSheet() {
    _reminderTask      = '';
    _reminderDate      = DateTime.now();
    _reminderTime      = TimeOfDay.now();
    _reminderRecurring = 'none';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ReminderSheet(
        l:               _l,
        initialDate:     _reminderDate,
        initialTime:     _reminderTime,
        initialRecurring: _reminderRecurring,
        onConfirm: (task, date, time, recurring) {
          Navigator.pop(ctx);
          final h       = time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
          final m       = time.minute.toString().padLeft(2, '0');
          final period  = time.hour >= 12 ? 'pm' : 'am';
          final dateStr = '${date.day} ${_l.monthName(date.month)} ${date.year}';
          final recurStr = recurring == 'none' ? '' : ' (recurring: $recurring)';
          final message  = _l.reminderMsg(task, '$h:$m $period', dateStr, recurStr);

          setState(() {
            _showQuickChips = false;
            messages.add({'sender': 'user', 'text': message, 'time': DateTime.now()});
            _isLoading = true;
          });
          _scrollToBottom();
          _sendDirectMessage(message);
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // 📍 Find-item sheet
  // ─────────────────────────────────────────────────────────
  Future<void> _openFindItemSheet() async {
    setState(() => _itemsLoading = true);

    try {
      final uid = user?.uid ?? '';
      if (uid.isEmpty) {
        setState(() => _itemsLoading = false);
        return;
      }

      // ✅ FIX: Always fetch fresh from Firestore when sheet opens, so newly
      // stored items (e.g. "My aadhar card is in the drawer") are visible
      // immediately without restarting the app.
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('object_memories')
          .get();

      final items = snapshot.docs.map((doc) {
        final data = doc.data();
        return <String, dynamic>{
          'object_name': data['object_name'] ?? data['identifier'] ?? '',
          'identifier':  data['identifier']  ?? '',
          'location':    data['location']    ?? 'Unknown',
        };
      }).toList();

      setState(() {
        _storedItems  = items;
        _itemsLoading = false;
      });
    } catch (e) {
      // ✅ FIX: Show error instead of silently swallowing it, so you can
      // actually debug when Firestore fails.
      setState(() => _itemsLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not load items. Please try again.'),
            backgroundColor: const Color(0xFF2D6A4F),
          ),
        );
      }
      return; // ✅ Don't open an empty sheet when fetch actually failed
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _FindItemSheet(
        l:     _l,
        items: _storedItems,
        onItemTap: (objectName) {
          Navigator.pop(ctx);
          final message = _l.findMsg(objectName);
          setState(() {
            _showQuickChips = false;
            messages.add({'sender': 'user', 'text': message, 'time': DateTime.now()});
            _isLoading = true;
          });
          _scrollToBottom();
          _sendDirectMessage(message);
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final settings = SettingsProvider.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFEFF3F5),
      appBar: _buildAppBar(context),
      body: PopScope(
        canPop: !_showEmoji,
        onPopInvoked: (didPop) {
          if (didPop) return;
          setState(() => _showEmoji = false);
        },
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0.05,
                      child: Container(color: Colors.transparent),
                    ),
                  ),
                  ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                    itemCount: messages.length + (_isLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_isLoading && index == messages.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 12),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _buildTypingIndicator(),
                          ),
                        );
                      }
                      final msg = messages[index];
                      return _buildMessageBubble(
                        msg, msg['sender'] == 'user', settings.fontSizeMultiplier);
                    },
                  ),
                ],
              ),
            ),

            _buildInputArea(settings.fontSizeMultiplier),

            if (_showQuickChips) _buildQuickChips(),

            if (_showEmoji)
              SizedBox(
                height: 250,
                child: EmojiPicker(
                  onEmojiSelected: (category, emoji) {
                    _controller.text = _controller.text + emoji.emoji;
                    _controller.selection = TextSelection.fromPosition(
                        TextPosition(offset: _controller.text.length));
                  },
                  config: Config(
                    height: 256,
                    checkPlatformCompatibility: true,
                    emojiViewConfig: EmojiViewConfig(
                      emojiSizeMax: 32 * (Platform.isIOS ? 1.30 : 1.0),
                      columns: 7,
                      backgroundColor: const Color(0xFFF2F2F2),
                      recentsLimit: 28,
                      replaceEmojiOnLimitExceed: false,
                      noRecents: const Text('No Recents',
                          style: TextStyle(fontSize: 20, color: Colors.black26),
                          textAlign: TextAlign.center),
                      buttonMode: ButtonMode.MATERIAL,
                    ),
                    categoryViewConfig: const CategoryViewConfig(
                      initCategory: Category.SMILEYS,
                      backgroundColor: Color(0xFFF2F2F2),
                      indicatorColor: Color(0xFF2D6A4F),
                      iconColor: Colors.grey,
                      iconColorSelected: Color(0xFF2D6A4F),
                      backspaceColor: Color(0xFF2D6A4F),
                      tabIndicatorAnimDuration: kTabScrollDuration,
                    ),
                    bottomActionBarConfig: const BottomActionBarConfig(
                      backgroundColor: Color(0xFFF2F2F2),
                      buttonColor: Color(0xFFF2F2F2),
                      buttonIconColor: Colors.grey,
                    ),
                    searchViewConfig: const SearchViewConfig(
                      backgroundColor: Color(0xFFF2F2F2),
                      buttonIconColor: Colors.grey,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // AppBar
  // ─────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      toolbarHeight: 70,
      titleSpacing: 0,
      leadingWidth: 60,
      leading: Padding(
        padding: const EdgeInsets.only(left: 16),
        child: CircleAvatar(
          backgroundColor: Colors.white,
          child: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF2D6A4F), size: 18),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      actions: [
        // 🌐 Language toggle
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Tooltip(
            message: _isHindi ? 'Switch to English' : 'हिंदी में बदलें',
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _toggleLanguage,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                constraints: const BoxConstraints(maxWidth: 80),
                decoration: BoxDecoration(
                  color: _isHindi
                      ? const Color(0xFF2D6A4F)
                      : const Color(0xFF2D6A4F).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF2D6A4F).withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_isHindi ? '🇮🇳' : '🇬🇧',
                        style: const TextStyle(fontSize: 13)),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        _l.langToggle,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _isHindi ? Colors.white : const Color(0xFF2D6A4F),
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // ❓ /help button
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Tooltip(
            message: _l.helpTooltip,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                _controller.text = '/help';
                _sendMessage();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D6A4F).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF2D6A4F).withOpacity(0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.help_outline_rounded, color: Color(0xFF2D6A4F), size: 16),
                    SizedBox(width: 4),
                    Text('/help',
                        style: TextStyle(
                            color: Color(0xFF2D6A4F),
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
      title: Row(
        children: [
          Stack(
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient:
                      LinearGradient(colors: [Color(0xFF2D6A4F), Color(0xFF26A69A)]),
                ),
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.white,
                  child: SvgPicture.asset('assets/images/chatbot1.svg', width: 24),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.greenAccent[400],
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Builder(builder: (ctx) {
              final settings = SettingsProvider.of(ctx);
              final name     = settings.username.isNotEmpty ? settings.username : null;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _l.appTitle,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFF1F2937),
                        fontWeight: FontWeight.bold,
                        fontSize: 18),
                  ),
                  Text(
                    name != null ? _l.hereFor(name) : _l.alwaysHere,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.green, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // Typing indicator
  // ─────────────────────────────────────────────────────────
  Widget _buildTypingIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft:     Radius.circular(20),
          topRight:    Radius.circular(20),
          bottomRight: Radius.circular(20),
          bottomLeft:  Radius.circular(4),
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _dot(0),
          const SizedBox(width: 4),
          _dot(150),
          const SizedBox(width: 4),
          _dot(300),
        ],
      ),
    ).animate().fadeIn().slideX(begin: -0.1);
  }

  Widget _dot(int delay) {
    return Container(
      width: 6,
      height: 6,
      decoration: const BoxDecoration(color: Color(0xFF26A69A), shape: BoxShape.circle),
    ).animate(onPlay: (c) => c.repeat(reverse: true))
        .scaleXY(begin: 0.6, end: 1.2, duration: 600.ms, delay: delay.ms);
  }

  // ─────────────────────────────────────────────────────────
  // Message bubble
  // ─────────────────────────────────────────────────────────
  Widget _buildMessageBubble(
      Map<String, dynamic> msg, bool isUser, double fontSizeMultiplier) {
    final text = msg['text'] as String;
    final time = DateFormat('h:mm a').format(msg['time'] as DateTime);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser ? const Color(0xFF2D6A4F) : Colors.white,
                gradient: isUser
                    ? const LinearGradient(
                        colors: [Color(0xFF2D6A4F), Color(0xFF26A69A)])
                    : null,
                borderRadius: BorderRadius.only(
                  topLeft:     const Radius.circular(20),
                  topRight:    const Radius.circular(20),
                  bottomLeft:  Radius.circular(isUser ? 20 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 20),
                ),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 5)),
                ],
              ),
              child: SelectableText(
                text,
                style: TextStyle(
                    color: isUser ? Colors.white : const Color(0xFF333333),
                    fontSize: (16 * fontSizeMultiplier).clamp(12.0, 22.0),
                    height: 1.5),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4, right: 4),
              child: Text(time,
                  style: TextStyle(
                      fontSize:   (11 * fontSizeMultiplier).clamp(9.0, 14.0),
                      color:      Colors.grey[500],
                      fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.2, curve: Curves.easeOut),
    );
  }

  // ─────────────────────────────────────────────────────────
  // Quick chips
  // ─────────────────────────────────────────────────────────
  Widget _buildQuickChips() {
    final chips = [
      {'label': _l.chipReminder,    'onTap': () => _openReminderSheet()},
      {'label': _l.chipFindItem,    'onTap': () => _openFindItemSheet()},
      {
        'label': _l.chipMyReminders,
        'onTap': () { _controller.text = _l.myRemindersMsg; _sendMessage(); },
      },
      {
        'label': _l.chipHelp,
        'onTap': () { _controller.text = '/help'; _sendMessage(); },
      },
    ];

    return Container(
      color: const Color(0xFFEFF3F5),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: chips.map((chip) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: chip['onTap'] as VoidCallback,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: const Color(0xFF2D6A4F).withOpacity(0.35)),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Text(
                    chip['label']! as String,
                    style: const TextStyle(
                        color: Color(0xFF2D6A4F),
                        fontSize: 13,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.3);
  }

  // ─────────────────────────────────────────────────────────
  // Input area
  // ─────────────────────────────────────────────────────────
  Widget _buildInputArea(double fontSizeMultiplier) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      color: const Color(0xFFEFF3F5),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 15,
                      offset: const Offset(0, 5)),
                ],
              ),
              child: TextField(
                focusNode:    _focusNode,
                controller:   _controller,
                onSubmitted:  (_) => _sendMessage(),
                maxLines:     4,
                minLines:     1,
                style:        TextStyle(fontSize: (16 * fontSizeMultiplier).clamp(12.0, 20.0)),
                cursorColor:  const Color(0xFF2D6A4F),
                decoration: InputDecoration(
                  hintText:  _l.inputHint,
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  border: InputBorder.none,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showEmoji
                          ? Icons.keyboard
                          : Icons.sentiment_satisfied_alt_rounded,
                      color: _showEmoji
                          ? const Color(0xFF2D6A4F)
                          : Colors.grey[400],
                    ),
                    onPressed: _toggleEmojiPicker,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: _isLoading ? null : _sendMessage,
            child: Container(
              height: 55,
              width:  55,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF2D6A4F), Color(0xFF26A69A)],
                    begin: Alignment.topLeft,
                    end:   Alignment.bottomRight),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: const Color(0xFF2D6A4F).withOpacity(0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 5)),
                ],
              ),
              child: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded, color: Colors.white, size: 24),
            ).animate(target: _isLoading ? 0 : 1).scale(duration: 200.ms),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 📅  REMINDER BOTTOM SHEET
// ═══════════════════════════════════════════════════════════════
class _ReminderSheet extends StatefulWidget {
  final _L      l;
  final DateTime   initialDate;
  final TimeOfDay  initialTime;
  final String     initialRecurring;
  final void Function(String task, DateTime date, TimeOfDay time, String recurring) onConfirm;

  const _ReminderSheet({
    required this.l,
    required this.initialDate,
    required this.initialTime,
    required this.initialRecurring,
    required this.onConfirm,
  });

  @override
  State<_ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends State<_ReminderSheet> {
  final TextEditingController _taskCtrl = TextEditingController();
  late DateTime  _date;
  late TimeOfDay _time;
  late String    _recurring;

  _L get _l => widget.l;

  @override
  void initState() {
    super.initState();
    _date      = widget.initialDate;
    _time      = widget.initialTime;
    _recurring = widget.initialRecurring;
  }

  @override
  void dispose() {
    _taskCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate:   DateTime.now(),
      lastDate:    DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF2D6A4F))),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
      builder: (ctx, child) => Theme(
        data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF2D6A4F))),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _time = picked);
  }

  String _formatDate(DateTime d) {
    const en = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final mon = _l.isHindi
        ? _l.monthName(d.month).substring(0, _l.monthName(d.month).length.clamp(0, 3))
        : en[d.month];
    return '${d.day} $mon ${d.year}';
  }

  String _formatTime(TimeOfDay t) {
    final h = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
    final m = t.minute.toString().padLeft(2, '0');
    final p = t.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $p';
  }

  @override
  Widget build(BuildContext context) {
    final recurringOptions = ['none', 'daily', 'weekly'];
    final recurringLabels  = {
      'none':   _l.repeatOnce,
      'daily':  _l.repeatDaily,
      'weekly': _l.repeatWeekly,
    };

    return Container(
      margin: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),

            Text(_l.reminderSheetTitle,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1F2937))),
            const SizedBox(height: 6),
            Text(_l.reminderSheetSubtitle,
                style: const TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 24),

            // Task input
            Text(_l.reminderTaskLabel,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF374151))),
            const SizedBox(height: 8),
            TextField(
              controller: _taskCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText:  _l.reminderTaskHint,
                hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                filled:     true,
                fillColor:  const Color(0xFFF9FAFB),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey[200]!)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        const BorderSide(color: Color(0xFF2D6A4F), width: 1.5)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey[200]!)),
              ),
            ),
            const SizedBox(height: 20),

            // Date & Time
            Row(
              children: [
                Expanded(
                  child: _PickerTile(
                    icon:  Icons.calendar_today_rounded,
                    label: _l.reminderDateLabel,
                    value: _formatDate(_date),
                    onTap: _pickDate,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PickerTile(
                    icon:  Icons.access_time_rounded,
                    label: _l.reminderTimeLabel,
                    value: _formatTime(_time),
                    onTap: _pickTime,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Repeat
            Text(_l.reminderRepeatLabel,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF374151))),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: recurringOptions.map((type) {
                final selected = _recurring == type;
                return GestureDetector(
                  onTap: () => setState(() => _recurring = type),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF2D6A4F)
                          : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      recurringLabels[type]!,
                      style: TextStyle(
                        color: selected ? Colors.white : const Color(0xFF6B7280),
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 28),

            // Confirm
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final task = _taskCtrl.text.trim();
                  if (task.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(_l.reminderEmptyWarn)));
                    return;
                  }
                  widget.onConfirm(task, _date, _time, _recurring);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2D6A4F),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: Text(
                  _l.reminderConfirm,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Reusable picker tile
// ─────────────────────────────────────────────────────────────
class _PickerTile extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final String       value;
  final VoidCallback onTap;

  const _PickerTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: const Color(0xFF2D6A4F)),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(value,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF1F2937),
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 📍  FIND MY ITEM BOTTOM SHEET
// ═══════════════════════════════════════════════════════════════
class _FindItemSheet extends StatefulWidget {
  final _L  l;
  final List<Map<String, dynamic>> items;
  final void Function(String objectName) onItemTap;

  const _FindItemSheet({
    required this.l,
    required this.items,
    required this.onItemTap,
  });

  @override
  State<_FindItemSheet> createState() => _FindItemSheetState();
}

class _FindItemSheetState extends State<_FindItemSheet> {
  String _search = '';
  _L get _l => widget.l;

  @override
  Widget build(BuildContext context) {
    final filtered = widget.items.where((item) {
      final name =
          (item['object_name'] ?? item['identifier'] ?? '').toString().toLowerCase();
      return name.contains(_search.toLowerCase());
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),

          Text(_l.findSheetTitle,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1F2937))),
          const SizedBox(height: 4),
          Text(_l.findSheetSubtitle,
              style: const TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 16),

          // Search bar
          TextField(
            onChanged: (v) => setState(() => _search = v),
            decoration: InputDecoration(
              hintText:  _l.findSearchHint,
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
              prefixIcon: const Icon(Icons.search, color: Color(0xFF2D6A4F), size: 20),
              filled:    true,
              fillColor: const Color(0xFFF9FAFB),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey[200]!)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey[200]!)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      const BorderSide(color: Color(0xFF2D6A4F), width: 1.5)),
            ),
          ),
          const SizedBox(height: 16),

          // Item list
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off_rounded,
                            size: 48, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        Text(
                          widget.items.isEmpty ? _l.findEmpty : _l.findNoMatch,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[400], fontSize: 14),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: Colors.grey[100]),
                    itemBuilder: (ctx, i) {
                      final item       = filtered[i];
                      final objectName =
                          item['object_name'] ?? item['identifier'] ?? 'Item';
                      final location   = item['location'] ?? 'Unknown location';
                      final identifier = item['identifier'] ?? '';

                      return ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                        leading: Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2D6A4F).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.location_on_rounded,
                              color: Color(0xFF2D6A4F), size: 22),
                        ),
                        title: Text(
                          identifier.isNotEmpty
                              ? '$identifier $objectName'
                              : objectName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: Color(0xFF1F2937)),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            '📍 $location',
                            style: const TextStyle(
                                fontSize: 13, color: Color(0xFF6B7280)),
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded,
                            color: Color(0xFF2D6A4F)),
                        onTap: () => widget.onItemTap(
                          identifier.isNotEmpty
                              ? '$identifier $objectName'
                              : objectName,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}