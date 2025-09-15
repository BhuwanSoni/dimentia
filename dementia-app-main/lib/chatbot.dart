import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'settings_provider.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<Map<String, String>> messages = [
    {
      'sender': 'bot',
      'text':
      'Hi Sanskriti! 😊 Good to see you. Would you like to check your reminders or talk to me?',
    },
    {'sender': 'user', 'text': 'Where did I keep my Aadhar card?'},
    {
      'sender': 'bot',
      'text': 'You placed it in the top right corner of the top shelf.',
    },
  ];

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  Widget _buildMessage(String text, bool isUser, double fontSizeMultiplier) {
    final botAvatar = Container(
      width: 36,
      height: 30,
      margin: const EdgeInsets.only(right: 1),
      child: SvgPicture.asset('assets/images/chatbot1.svg',colorFilter: const ColorFilter.mode(
                             Color(0xFF2D6A4F), BlendMode.srcIn),),

    );

    final userAvatar = const Padding(
      padding: EdgeInsets.only(left: 2),
      child: CircleAvatar(
        radius: 20,
        backgroundColor: Color(0xFFE5FFF2),
        child: Icon(Icons.person, color: Color(0xFF2D6A4F), size: 24),
      ),
    );

    return Container(
     // padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      padding: const EdgeInsets.fromLTRB(6, 2, 8, 10),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) botAvatar,
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: isUser ? const Color(0xFF2D6A4F) : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isUser ? 20 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                text,
                style: TextStyle(
                  color: isUser ? Colors.white : Colors.black87,
                  fontSize: 16*fontSizeMultiplier,
                  height: 1.5,
                ),
              ),
            ),
          ),
          if (isUser) userAvatar,
        ],
      ),
    );
  }

  void _sendMessage() {
    final userInput = _controller.text.trim();
    if (userInput.isEmpty) return;

    const botResponse = "Let me check that for you...";
    setState(() {
      messages.add({'sender': 'user', 'text': userInput});
      messages.add({'sender': 'bot', 'text': botResponse});
    });

    _controller.clear();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsProvider.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F8F7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: true,
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              'assets/images/chatt.svg',
              height: 28,
              width: 28,
              colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
            ),
            const SizedBox(width: 8),
            const Text(
              'Your Assistant',
              style: TextStyle(
                color: Colors.white,
                fontFamily: 'Raleway',
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF2D6A4F), Color(0xFF26A69A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final msg = messages[index];
                return _buildMessage(msg['text']!, msg['sender'] == 'user',settings.fontSizeMultiplier);
              },
            ),
          ),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                )
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    cursorColor: const Color(0xFF2D6A4F),
                    decoration: const InputDecoration(
                      hintText: 'Ask anything...',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 20),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.mic, color: Color(0xFF2D6A4F)),
                  onPressed: () {},
                ),

                CircleAvatar(
                  backgroundColor: const Color(0xFF2D6A4F),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}