import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'settings_provider.dart';
import 'chatbot_service.dart';


class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _controller = TextEditingController();
  final ChatbotService _chatbotService = ChatbotService();
  final FocusNode _focusNode = FocusNode();

  bool _isLoading = false;
  bool _showEmoji = false;
  bool _welcomeSent = false; // 🔥 NEW: guard so welcome message fires only once

  final user = FirebaseAuth.instance.currentUser;

  // 🔥 CHANGED: Start with empty list — welcome message added in didChangeDependencies
  final List<Map<String, dynamic>> messages = [];

  // ─────────────────────────────────────────────
  // 🔥 NEW: Inject real name into welcome message
  // ─────────────────────────────────────────────
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_welcomeSent) {
      final settings = SettingsProvider.of(context);
      final name = settings.username.isNotEmpty ? settings.username : "there";

      setState(() {
        messages.add({
          'sender': 'bot',
          'text': 'Hi $name! 😊 I am Memoir, your personal memory assistant. How can I help you today?',
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
      if (_focusNode.hasFocus) {
        setState(() => _showEmoji = false);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // --- LOGIC ---

  Future<void> _sendMessage() async {
    final userInput = _controller.text.trim();

    if (userInput.isEmpty || _isLoading) return;

    _controller.clear();

    setState(() {
      messages.add({
        'sender': 'user',
        'text': userInput,
        'time': DateTime.now(),
      });

      _isLoading = true;
      _showEmoji = false;
    });

    _scrollToBottom();

    try {
      // ─────────────────────────────────────────────────────────────
      // 🔥 NEW: Build user profile context from SettingsProvider
      // This is injected into the AI prompt so it can personalize
      // responses using the user's name, age, gender, and address.
      // ─────────────────────────────────────────────────────────────
      final settings = SettingsProvider.of(context);

      final profileText = """
User Profile:
- Name: ${settings.username.isNotEmpty ? settings.username : 'Not specified'}
- Gender: ${settings.gender.isNotEmpty ? settings.gender : 'Not specified'}
- Age: ${settings.age > 0 ? '${settings.age} years' : 'Not specified'}
- Address: ${settings.address.isNotEmpty ? settings.address : 'Not specified'}
""";

      // 🔥 CHANGED: Pass profileText so the AI knows who it's talking to
      final botResponse = await _chatbotService.sendMessage(
        userInput,
        profileText: profileText,
      );

      if (!mounted) return;

      setState(() {
        _isLoading = false;

        messages.add({
          'sender': 'bot',
          'text': botResponse,
          'time': DateTime.now(),
        });
      });

    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;

        messages.add({
          'sender': 'bot',
          'text': "Something went wrong.",
          'time': DateTime.now(),
        });
      });
    }

    _scrollToBottom();
  }

  void _scrollToBottom() {
    // Small delay to ensure the list has rendered the new item before scrolling
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
      // Switch to Keyboard
      setState(() => _showEmoji = false);
      _focusNode.requestFocus();
    } else {
      // Switch to Emoji
      _focusNode.unfocus(); // Hide keyboard first
      setState(() => _showEmoji = true);
    }
  }


  @override
  Widget build(BuildContext context) {
    final settings = SettingsProvider.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFEFF3F5),
      appBar: _buildAppBar(context),
      // PopScope handles the Android Back Button
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
                  // Pattern Background
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0.05,
                      child: Container(color: Colors.transparent),
                    ),
                  ),

                  // THE CHAT LIST
                  ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                    // MAGIC HERE: If loading, we add 1 extra item for the indicator
                    itemCount: messages.length + (_isLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      // If we are at the last index and loading is true, show indicator
                      if (_isLoading && index == messages.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 12),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _buildTypingIndicator(),
                          ),
                        );
                      }

                      // Otherwise show standard message
                      final msg = messages[index];
                      return _buildMessageBubble(msg, msg['sender'] == 'user', settings.fontSizeMultiplier);
                    },
                  ),
                ],
              ),
            ),

            // INPUT AREA
            _buildInputArea(settings.fontSizeMultiplier),

            // EMOJI PICKER (Conditional Visibility)
            if (_showEmoji)
              SizedBox(
                height: 250,
                child: EmojiPicker(
                  onEmojiSelected: (category, emoji) {
                    _controller.text = _controller.text + emoji.emoji;
                    // Move cursor to end
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
                      noRecents: const Text(
                        'No Recents',
                        style: TextStyle(fontSize: 20, color: Colors.black26),
                        textAlign: TextAlign.center,
                      ),
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

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      toolbarHeight: 70,
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
                  child: SvgPicture.asset(
                    'assets/images/chatbot1.svg',
                    width: 24,
                  ),
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
              )
            ],
          ),
          const SizedBox(width: 12),
          // 🔥 NEW: Show real user name in AppBar subtitle
          Builder(builder: (ctx) {
            final settings = SettingsProvider.of(ctx);
            final name = settings.username.isNotEmpty ? settings.username : null;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Memoir',
                  style: TextStyle(color: Color(0xFF1F2937), fontWeight: FontWeight.bold, fontSize: 18),
                ),
                Text(
                  name != null ? 'Hi, $name 👋' : 'Online',
                  style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
          bottomRight: Radius.circular(20),
          bottomLeft: Radius.circular(4), // Tail on the left
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
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

  Widget _buildMessageBubble(Map<String, dynamic> msg, bool isUser, double fontSizeMultiplier) {
    final text = msg['text'] as String;
    final time = DateFormat('h:mm a').format(msg['time'] as DateTime);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        child: Column(
          crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: isUser ? const Color(0xFF2D6A4F) : Colors.white,
                gradient: isUser
                    ? const LinearGradient(colors: [Color(0xFF2D6A4F), Color(0xFF26A69A)])
                    : null,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isUser ? 20 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: SelectableText(
                text,
                style: TextStyle(
                  color: isUser ? Colors.white : const Color(0xFF333333),
                  fontSize: 16 * fontSizeMultiplier,
                  height: 1.4,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4, right: 4),
              child: Text(
                time,
                style: TextStyle(
                  fontSize: 11 * fontSizeMultiplier,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.2, curve: Curves.easeOut),
    );
  }

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
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: TextField(
                focusNode: _focusNode,
                controller: _controller,
                onSubmitted: (_) => _sendMessage(),
                style: TextStyle(fontSize: 16 * fontSizeMultiplier),
                cursorColor: const Color(0xFF2D6A4F),
                decoration: InputDecoration(
                  hintText: 'Type your message...',
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  border: InputBorder.none,
                  // --- EMOJI TOGGLE ICON ---
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
            onTap: _isLoading ? null : () => _sendMessage(),
            child: Container(
              height: 55,
              width: 55,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2D6A4F), Color(0xFF26A69A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2D6A4F).withOpacity(0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: _isLoading
                  ? const Padding(
                padding: EdgeInsets.all(16.0),
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