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
// ✅ FIX: notification_service import removed — we no longer schedule notifications
// directly from chatbot.dart. The Firestore stream in ReminderPage is the single
// scheduling authority, preventing duplicate notifications.

// ═══════════════════════════════════════════════════════════════
// 🌐 MULTILINGUAL STRINGS  (English + Hindi)
// ═══════════════════════════════════════════════════════════════
class _L {
  final bool isHindi;
  const _L(this.isHindi);

  String get appTitle => 'Memoir AI';
  String hereFor(String name) =>
      isHindi ? 'आपके साथ हूँ, $name 💙' : 'Here for you, $name 💙';
  String get alwaysHere => isHindi ? 'हमेशा आपके साथ 💙' : 'Always here for you 💙';

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

  String get chipReminder    => isHindi ? '⏰ रिमाइंडर सेट करें' : '⏰ Set a reminder';
  String get chipFindItem    => isHindi ? '📍 चीज़ ढूंढें'       : '📍 Find my item';
  String get chipMyReminders => isHindi ? '📋 मेरे रिमाइंडर'     : '📋 My reminders';
  String get chipHelp        => isHindi ? '❓ सहायता'             : '❓ Help';

  String get inputHint =>
      isHindi ? 'कुछ भी पूछें या /help टाइप करें...' : 'Ask me anything or type /help...';
  String get helpTooltip =>
      isHindi ? 'देखें मैं क्या कर सकता हूँ' : 'See what I can do';

  String get reminderSheetTitle    => isHindi ? '⏰ रिमाइंडर सेट करें' : '⏰ Set a Reminder';
  String get reminderSheetSubtitle =>
      isHindi ? 'जानकारी भरें, मैं याद दिलाऊंगा! 😊' : 'Fill in the details and I\'ll remind you! 😊';
  String get reminderTaskLabel =>
      isHindi ? 'मुझे क्या याद दिलाना है?' : 'What should I remind you about?';
  String get reminderTaskHint =>
      isHindi ? 'जैसे: दवाई लेना, डॉक्टर अपॉइंटमेंट…' : 'e.g. Take medicine, Doctor appointment…';
  String get reminderDateLabel   => isHindi ? 'तारीख'        : 'Date';
  String get reminderTimeLabel   => isHindi ? 'समय'          : 'Time';
  String get reminderRepeatLabel => isHindi ? 'दोहराएं'      : 'Repeat';
  String get repeatOnce          => isHindi ? 'एक बार'       : 'One-time';
  String get repeatDaily         => isHindi ? 'रोज़'          : 'Daily';
  String get repeatWeekly        => isHindi ? 'साप्ताहिक'     : 'Weekly';
  String get reminderConfirm     => isHindi ? 'रिमाइंडर सेट करें 🎉' : 'Set Reminder 🎉';
  String get reminderEmptyWarn   =>
      isHindi ? 'कृपया बताएं क्या याद दिलाना है 😊' : 'Please enter what to remind you about 😊';

  // ── Find Item In-Chat ──────────────────────────────────────
  String get findCardTitle    => isHindi ? '📍 आपकी सेव की हुई चीज़ें' : '📍 Your Saved Items';
  String get findCardSubtitle =>
      isHindi ? 'जिस चीज़ को ढूंढना हो उस पर टैप करें' : 'Tap any item to find where you kept it';
  String get findSearchHint   => isHindi ? 'चीज़ें खोजें…'     : 'Search items…';
  String get findEmpty        =>
      isHindi
          ? 'अभी कोई चीज़ सेव नहीं है।\nमुझे बताएं आप चीज़ें कहाँ रखते हैं!'
          : 'No items saved yet.\nTell me where you keep things!';
  String get findNoMatch      => isHindi ? 'कोई मिलान नहीं मिला।' : 'No items match your search.';
  String get findLoading      => isHindi ? 'चीज़ें ढूंढ रहे हैं…' : 'Loading your items…';
  String get findError        =>
      isHindi ? 'चीज़ें लोड नहीं हो सकीं। फिर से कोशिश करें।' : 'Could not load items. Please try again.';

  String get errorMsg =>
      isHindi ? 'ओह नहीं, कनेक्शन में थोड़ी दिक्कत हुई। 😔 फिर से कोशिश करें!'
              : 'Oh no, I had a little trouble connecting. 😔 Please try again!';
  String get errorDirectMsg =>
      isHindi ? 'ओह नहीं, कुछ गड़बड़ हो गई। 😔 फिर से कोशिश करें!'
              : 'Oh no, I had a little trouble. 😔 Please try again!';

  String reminderMsg(String task, String time, String dateStr, String recurStr) =>
      isHindi
          ? 'मुझे $task की याद दिलाएं $time बजे $dateStr को$recurStr'
          : 'Remind me to $task at $time on $dateStr$recurStr';

  String findMsg(String name) =>
      isHindi ? 'मेरा $name कहाँ है?' : 'Where is my $name?';

  String get myRemindersMsg =>
      isHindi ? 'मेरे रिमाइंडर क्या हैं?' : 'What are my reminders?';

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

  String get langToggle => isHindi ? 'EN' : 'हिं';
}

// ═══════════════════════════════════════════════════════════════
// 💬  MESSAGE TYPE ENUM
// ═══════════════════════════════════════════════════════════════
enum _MessageType {
  text,        // Normal chat bubble
  findItems,   // In-chat "Find My Item" card
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
  bool _isHindi        = false;

  // ── Reminder sheet state ──────────────────────────────────
  String    _reminderTask      = '';
  DateTime  _reminderDate      = DateTime.now();
  TimeOfDay _reminderTime      = TimeOfDay.now();
  String    _reminderRecurring = 'none';

  // ── Find-item state ───────────────────────────────────────
  List<Map<String, dynamic>> _storedItems    = [];
  bool                       _itemsLoading   = false;
  String?                    _itemsError;

  final user = FirebaseAuth.instance.currentUser;

  // ── Messages list: each entry has 'type', plus type-specific fields ──
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
          'type':   _MessageType.text,
          'sender': 'bot',
          'text':   _l.welcome(name),
          'time':   DateTime.now(),
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

  void _toggleLanguage() => setState(() => _isHindi = !_isHindi);

  // ─────────────────────────────────────────────────────────
  // Messaging
  // ─────────────────────────────────────────────────────────
  Future<void> _sendMessage() async {
    final userInput = _controller.text.trim();
    if (userInput.isEmpty || _isLoading) return;

    _controller.clear();
    setState(() {
      messages.add({
        'type':   _MessageType.text,
        'sender': 'user',
        'text':   userInput,
        'time':   DateTime.now(),
      });
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
        messages.add({
          'type':   _MessageType.text,
          'sender': 'bot',
          'text':   botResponse,
          'time':   DateTime.now(),
        });
      });
      _refreshStoredItems();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        messages.add({
          'type':   _MessageType.text,
          'sender': 'bot',
          'text':   _l.errorMsg,
          'time':   DateTime.now(),
        });
      });
    }
    _scrollToBottom();
  }

  // Send a message programmatically (from chips / sheets)
  Future<void> _sendDirectMessage(String text) async {
    // ✅ FIX: Set _isLoading = true so the typing indicator appears while waiting.
    // Old code never set it, leaving the UI looking frozen during slow API responses.
    setState(() => _isLoading = true);
    _scrollToBottom();
    try {
      final settings    = SettingsProvider.of(context);
      final botResponse = await _chatbotService.sendMessage(
        text,
        profileText: _buildProfileText(settings),
      );
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        messages.add({
          'type':   _MessageType.text,
          'sender': 'bot',
          'text':   botResponse,
          'time':   DateTime.now(),
        });
      });
      _refreshStoredItems();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        messages.add({
          'type':   _MessageType.text,
          'sender': 'bot',
          'text':   _l.errorDirectMsg,
          'time':   DateTime.now(),
        });
      });
    }
    _scrollToBottom();
  }

  // ─────────────────────────────────────────────────────────
  // Find My Item — IN-CHAT CARD
  // ─────────────────────────────────────────────────────────

  /// Fetches items and injects a special 'findItems' message bubble into the chat.
  Future<void> _openFindItemInChat() async {
    if (_isLoading) return;

    // 1️⃣  Show the card immediately with a loading state
    final int cardIndex = messages.length;
    setState(() {
      _showQuickChips = false;
      // User-side message
      messages.add({
        'type':   _MessageType.text,
        'sender': 'user',
        'text':   _l.chipFindItem,
        'time':   DateTime.now(),
      });
      // Bot-side find-items card (loading)
      messages.add({
        'type':      _MessageType.findItems,
        'sender':    'bot',
        'time':      DateTime.now(),
        'loading':   true,
        'error':     null,
        'items':     <Map<String, dynamic>>[],
        'search':    '',
      });
    });
    _scrollToBottom();

    // 2️⃣  Fetch from Firestore
    final uid = user?.uid ?? '';
    if (uid.isEmpty) {
      _updateFindCard(cardIndex + 1, error: _l.findError, items: []);
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('long_term_memory')
          .where('type', isEqualTo: 'object_location')
          .get();

      final items = snapshot.docs.map((doc) {
        final data = doc.data();
        return <String, dynamic>{
          // memory_service stores key as 'object'; support legacy 'object_name' too
          'object_name': data['object'] ?? data['object_name'] ?? data['identifier'] ?? '',
          'identifier':  data['identifier']  ?? '',
          'location':    data['location']    ?? 'Unknown',
        };
      }).toList();

      if (!mounted) return;
      setState(() => _storedItems = items);
      _updateFindCard(cardIndex + 1, items: items);
    } catch (e) {
      if (!mounted) return;
      _updateFindCard(cardIndex + 1, error: _l.findError, items: []);
    }
  }

  void _updateFindCard(int index, {
    List<Map<String, dynamic>>? items,
    String? error,
  }) {
    if (index < 0 || index >= messages.length) return;
    setState(() {
      messages[index] = {
        ...messages[index],
        'loading': false,
        'items':   items ?? [],
        'error':   error,
      };
    });
    _scrollToBottom();
  }

  /// Called when user taps an item inside the in-chat card.
  void _onFindItemTap(String objectName) {
    final message = _l.findMsg(objectName);
    setState(() {
      messages.add({
        'type':   _MessageType.text,
        'sender': 'user',
        'text':   message,
        'time':   DateTime.now(),
      });
      _isLoading = true;
    });
    _scrollToBottom();
    _sendDirectMessage(message);
  }

  // ─────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────

  Future<void> _refreshStoredItems() async {
    try {
      final uid = user?.uid ?? '';
      if (uid.isEmpty) return;
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('long_term_memory')
          .where('type', isEqualTo: 'object_location')
          .get();
      if (!mounted) return;
      setState(() {
        _storedItems = snapshot.docs.map((doc) {
          final data = doc.data();
          return <String, dynamic>{
            // memory_service stores key as 'object'; support legacy 'object_name' too
            'object_name': data['object'] ?? data['object_name'] ?? data['identifier'] ?? '',
            'identifier':  data['identifier']  ?? '',
            'location':    data['location']    ?? 'Unknown',
          };
        }).toList();
      });
    } catch (_) {
      // Silent background refresh
    }
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
        l:                _l,
        initialDate:      _reminderDate,
        initialTime:      _reminderTime,
        initialRecurring: _reminderRecurring,
        onConfirm: (task, date, time, recurring) async {
          Navigator.pop(ctx);

          final scheduledDateTime = DateTime(
            date.year, date.month, date.day, time.hour, time.minute,
          );

          // ✅ FIX: Directly write to Firestore instead of sending a natural
          // language message to the AI. The old approach was fragile — it
          // relied on the AI correctly parsing the message AND calling the
          // right backend tool. Now we write directly and show the user
          // a confirmation message in chat ourselves.
          try {
            final uid = user?.uid;
            if (uid == null) throw Exception('Not logged in');

            final docRef = await FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .collection('reminders')
                .add({
              'title': task,
              'task': task,
              // ✅ FIX: Store both UTC timestamp fields so the stream listener
              // in reminders.dart (which reads 'scheduled_time' first) and
              // the Python backend (which also writes 'scheduled_time') agree.
              'time': Timestamp.fromDate(scheduledDateTime.toUtc()),
              'scheduled_time': Timestamp.fromDate(scheduledDateTime.toUtc()),
              'completed': false,
              'source': 'assistant_sheet',
              'recurring_type': recurring,
              // ✅ FIX: time_text must be the LOCAL display time, not UTC.
              // Previously this was correct but lacked a timezone field,
              // causing the Python backend to misinterpret the reminder time.
              'time_text': DateFormat('hh:mm a').format(scheduledDateTime),
              // ✅ FIX: Add timezone so the backend reminder parser uses IST,
              // matching assistant_service.py and reminder_service.py defaults.
              'timezone': 'Asia/Kolkata',
              'created_at': FieldValue.serverTimestamp(),
              'last_modified': FieldValue.serverTimestamp(),
            });

            // ✅ FIX: Do NOT call NotificationService.scheduleReminder() here.
            // The Firestore stream listener in ReminderPage.initState() is the
            // single scheduling authority for ALL reminder sources. Calling it
            // here too caused duplicate/triple-firing notifications because both
            // paths fire independently (this page has no _scheduledIds guard).
            // The stream picks up the new document automatically.

            final h      = time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
            final m      = time.minute.toString().padLeft(2, '0');
            final period = time.hour >= 12 ? 'pm' : 'am';
            final dateStr = '${date.day} ${_l.monthName(date.month)} ${date.year}';
            final recurStr = recurring == 'none' ? '' : ' (${recurring})';

            if (!mounted) return;
            setState(() {
              _showQuickChips = false;
              messages.add({
                'type':   _MessageType.text,
                'sender': 'user',
                'text':   _l.reminderMsg(task, '$h:$m $period', dateStr, recurStr),
                'time':   DateTime.now(),
              });
              messages.add({
                'type':   _MessageType.text,
                'sender': 'bot',
                'text':   _isHindi
                    ? '✅ रिमाइंडर सेट हो गया! मैं आपको "$task" के लिए $h:$m $period$recurStr याद दिलाऊंगा। 😊'
                    : '✅ Done! I\'ve set a reminder for "$task" at $h:$m $period on $dateStr$recurStr. 😊',
                'time':   DateTime.now(),
              });
            });
            _scrollToBottom();
          } catch (e) {
            if (!mounted) return;
            setState(() {
              _isLoading = false;
              messages.add({
                'type':   _MessageType.text,
                'sender': 'bot',
                'text':   _l.errorDirectMsg,
                'time':   DateTime.now(),
              });
            });
          }
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
                      // Typing indicator
                      if (_isLoading && index == messages.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 12),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _buildTypingIndicator(),
                          ),
                        );
                      }

                      final msg  = messages[index];
                      final type = msg['type'] as _MessageType;

                      // ── Find Items card ──
                      if (type == _MessageType.findItems) {
                        return _FindItemsChatCard(
                          l:         _l,
                          loading:   msg['loading'] as bool,
                          error:     msg['error'] as String?,
                          items:     List<Map<String, dynamic>>.from(msg['items'] as List),
                          time:      msg['time'] as DateTime,
                          onItemTap: _onFindItemTap,
                          fontSizeMultiplier: settings.fontSizeMultiplier,
                        );
                      }

                      // ── Normal text bubble ──
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
                    Text(_isHindi ? '🇮🇳' : '🇬🇧', style: const TextStyle(fontSize: 13)),
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
                  gradient: LinearGradient(colors: [Color(0xFF2D6A4F), Color(0xFF26A69A)]),
                ),
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.white,
                  child: SvgPicture.asset('assets/images/chatbot1.svg', width: 24),
                ),
              ),
              Positioned(
                bottom: 0, right: 0,
                child: Container(
                  width: 12, height: 12,
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
                  Text(_l.appTitle,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Color(0xFF1F2937), fontWeight: FontWeight.bold, fontSize: 18)),
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
          topLeft: Radius.circular(20), topRight: Radius.circular(20),
          bottomRight: Radius.circular(20), bottomLeft: Radius.circular(4),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [_dot(0), const SizedBox(width: 4), _dot(150), const SizedBox(width: 4), _dot(300)],
      ),
    ).animate().fadeIn().slideX(begin: -0.1);
  }

  Widget _dot(int delay) {
    return Container(
      width: 6, height: 6,
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
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        child: Column(
          crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser ? const Color(0xFF2D6A4F) : Colors.white,
                gradient: isUser
                    ? const LinearGradient(colors: [Color(0xFF2D6A4F), Color(0xFF26A69A)])
                    : null,
                borderRadius: BorderRadius.only(
                  topLeft:     const Radius.circular(20),
                  topRight:    const Radius.circular(20),
                  bottomLeft:  Radius.circular(isUser ? 20 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 20),
                ),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 5)),
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
                      fontSize: (11 * fontSizeMultiplier).clamp(9.0, 14.0),
                      color: Colors.grey[500],
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
      // ✅ Now triggers in-chat card instead of bottom sheet
      {'label': _l.chipFindItem,    'onTap': () => _openFindItemInChat()},
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
                    border: Border.all(color: const Color(0xFF2D6A4F).withOpacity(0.35)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Text(
                    chip['label']! as String,
                    style: const TextStyle(
                        color: Color(0xFF2D6A4F), fontSize: 13, fontWeight: FontWeight.w500),
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
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5)),
                ],
              ),
              child: TextField(
                focusNode:   _focusNode,
                controller:  _controller,
                onSubmitted: (_) => _sendMessage(),
                maxLines: 4,
                minLines: 1,
                style:       TextStyle(fontSize: (16 * fontSizeMultiplier).clamp(12.0, 20.0)),
                cursorColor: const Color(0xFF2D6A4F),
                decoration: InputDecoration(
                  hintText:  _l.inputHint,
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  border: InputBorder.none,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showEmoji ? Icons.keyboard : Icons.sentiment_satisfied_alt_rounded,
                      color: _showEmoji ? const Color(0xFF2D6A4F) : Colors.grey[400],
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
              height: 55, width: 55,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF2D6A4F), Color(0xFF26A69A)],
                    begin: Alignment.topLeft,
                    end:   Alignment.bottomRight),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: const Color(0xFF2D6A4F).withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 5)),
                ],
              ),
              child: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
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
// 📍  FIND ITEMS IN-CHAT CARD
// Rendered directly inside the chat ListView as a bot message.
// ═══════════════════════════════════════════════════════════════
class _FindItemsChatCard extends StatefulWidget {
  final _L                         l;
  final bool                       loading;
  final String?                    error;
  final List<Map<String, dynamic>> items;
  final DateTime                   time;
  final void Function(String)      onItemTap;
  final double                     fontSizeMultiplier;

  const _FindItemsChatCard({
    required this.l,
    required this.loading,
    required this.error,
    required this.items,
    required this.time,
    required this.onItemTap,
    required this.fontSizeMultiplier,
  });

  @override
  State<_FindItemsChatCard> createState() => _FindItemsChatCardState();
}

class _FindItemsChatCardState extends State<_FindItemsChatCard> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('h:mm a').format(widget.time);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.92,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Card body ──
            Container(
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
                    color:  Colors.black.withOpacity(0.07),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header ──
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF2D6A4F), Color(0xFF26A69A)],
                        begin: Alignment.topLeft,
                        end:   Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.only(
                        topLeft:  Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on_rounded, color: Colors.white, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.l.findCardTitle,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.l.findCardSubtitle,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Content ──
                  if (widget.loading)
                    _buildLoadingState()
                  else if (widget.error != null)
                    _buildErrorState()
                  else if (widget.items.isEmpty)
                    _buildEmptyState()
                  else
                    _buildItemsList(),
                ],
              ),
            ),

            // ── Timestamp ──
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                timeStr,
                style: TextStyle(
                  fontSize: (11 * widget.fontSizeMultiplier).clamp(9.0, 14.0),
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.15, curve: Curves.easeOut);
  }

  // ── Loading state ──────────────────────────────────────────
  Widget _buildLoadingState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      child: Column(
        children: [
          const SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              color: Color(0xFF2D6A4F),
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.l.findLoading,
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ── Error state ────────────────────────────────────────────
  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // ── Empty state ────────────────────────────────────────────
  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      child: Column(
        children: [
          Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(
            widget.l.findEmpty,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[400], fontSize: 13, height: 1.6),
          ),
        ],
      ),
    );
  }

  // ── Items list ─────────────────────────────────────────────
  Widget _buildItemsList() {
    final filtered = widget.items.where((item) {
      final name = (item['object_name'] ?? item['identifier'] ?? '').toString().toLowerCase();
      final loc  = (item['location'] ?? '').toString().toLowerCase();
      final q    = _search.toLowerCase();
      return name.contains(q) || loc.contains(q);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _search = v),
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText:  widget.l.findSearchHint,
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
              prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF2D6A4F), size: 18),
              suffixIcon: _search.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 16, color: Colors.grey),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _search = '');
                      },
                    )
                  : null,
              filled:    true,
              fillColor: const Color(0xFFF4F7F5),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF2D6A4F), width: 1.5)),
            ),
          ),
        ),

        // Item count label
        if (_search.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 4),
            child: Text(
              '${widget.items.length} item${widget.items.length == 1 ? '' : 's'} saved',
              style: TextStyle(fontSize: 11, color: Colors.grey[400], fontWeight: FontWeight.w500),
            ),
          ),

        // No results
        if (filtered.isEmpty && _search.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.search_off_rounded, size: 20, color: Colors.grey[300]),
                const SizedBox(width: 8),
                Text(widget.l.findNoMatch,
                    style: TextStyle(color: Colors.grey[400], fontSize: 13)),
              ],
            ),
          ),

        // Items
        ...filtered.asMap().entries.map((entry) {
          final i    = entry.key;
          final item = entry.value;

          final rawName    = item['object_name'] ?? item['identifier'] ?? '';
          final identifier = item['identifier']  ?? '';
          final location   = item['location']    ?? 'Unknown';

          // Display label: "black wallet" or just "wallet"
          final displayName = identifier.isNotEmpty && identifier.toLowerCase() != rawName.toLowerCase()
              ? '$identifier $rawName'
              : rawName;

          final isLast = i == filtered.length - 1;

          return _ItemTile(
            displayName: displayName,
            location:    location,
            isLast:      isLast,
            onTap:       () => widget.onItemTap(displayName),
          );
        }),

        const SizedBox(height: 8),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 📦 Single item tile inside the in-chat card
// ─────────────────────────────────────────────────────────────
class _ItemTile extends StatelessWidget {
  final String       displayName;
  final String       location;
  final bool         isLast;
  final VoidCallback onTap;

  const _ItemTile({
    required this.displayName,
    required this.location,
    required this.isLast,
    required this.onTap,
  });

  // Pick a subtle icon based on common object names
  IconData _iconFor(String name) {
    final n = name.toLowerCase();
    if (n.contains('glass') || n.contains('spectacle') || n.contains('चश्म')) {
      return Icons.visibility_rounded;
    }
    if (n.contains('key') || n.contains('चाबी')) return Icons.vpn_key_rounded;
    if (n.contains('phone') || n.contains('mobile') || n.contains('फ़ोन')) {
      return Icons.smartphone_rounded;
    }
    if (n.contains('wallet') || n.contains('purse') || n.contains('बटुआ')) {
      return Icons.account_balance_wallet_rounded;
    }
    if (n.contains('card') || n.contains('कार्ड')) return Icons.credit_card_rounded;
    if (n.contains('medicine') || n.contains('tablet') || n.contains('दवा')) {
      return Icons.medication_rounded;
    }
    if (n.contains('book') || n.contains('किताब')) return Icons.menu_book_rounded;
    if (n.contains('watch') || n.contains('घड़ी')) return Icons.watch_rounded;
    if (n.contains('bag') || n.contains('थैला')) return Icons.shopping_bag_rounded;
    if (n.contains('remote') || n.contains('रिमोट')) return Icons.settings_remote_rounded;
    return Icons.location_on_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (!isLast) // only draw divider if not last
          Divider(height: 1, indent: 16, endIndent: 16, color: Colors.grey[100]),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // Icon circle
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D6A4F).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _iconFor(displayName),
                      color: const Color(0xFF2D6A4F),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Name + location
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName.isNotEmpty
                              ? displayName[0].toUpperCase() + displayName.substring(1)
                              : displayName,
                          style: const TextStyle(
                            color:      Color(0xFF1F2937),
                            fontWeight: FontWeight.w600,
                            fontSize:   14,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(Icons.place_rounded, size: 12, color: Colors.grey[400]),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                location,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color:    Colors.grey[500],
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Tap indicator
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D6A4F).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Find',
                      style: TextStyle(
                        color:      Color(0xFF2D6A4F),
                        fontSize:   11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}


// ═══════════════════════════════════════════════════════════════
// 📅  REMINDER BOTTOM SHEET  (unchanged from original)
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
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
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
                filled:    true,
                fillColor: const Color(0xFFF9FAFB),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey[200]!)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF2D6A4F), width: 1.5)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey[200]!)),
              ),
            ),
            const SizedBox(height: 20),

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
                      color: selected ? const Color(0xFF2D6A4F) : const Color(0xFFF3F4F6),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
// Reusable picker tile (used in reminder sheet)
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