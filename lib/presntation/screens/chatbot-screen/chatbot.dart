import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geoguide/constants/app_colors.dart';
import 'package:geoguide/cubit/user_cubit.dart';
import 'package:geoguide/presntation/screens/chatbot-screen/chatbot-widgets/chat_background.dart';
import 'package:geoguide/presntation/screens/chatbot-screen/chatbot-widgets/chat_input_field.dart';
import 'package:geoguide/presntation/screens/chatbot-screen/chatbot-widgets/chat_message_bubble.dart';
import 'package:geoguide/services/chat_firestore_service.dart';

class ChatBotPage extends StatefulWidget {
  const ChatBotPage({super.key});

  @override
  State<ChatBotPage> createState() => _ChatBotPageState();
}

class _ChatBotPageState extends State<ChatBotPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ChatFirestoreService _chatStorage = ChatFirestoreService();

  String? _sessionId;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadLatestSession();
  }

  Future<void> _loadLatestSession() async {
    final id = await _chatStorage.getOrCreateLatestSession();

    if (!mounted) return;

    setState(() {
      _sessionId = id;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isLoading || _sessionId == null) return;

    final currentSession = _sessionId!;

    _controller.clear();

    setState(() {
      _isLoading = true;
    });

    await _chatStorage.addMessage(
      sessionId: currentSession,
      sender: 'user',
      text: text,
    );

    _scrollToBottom();

    try {
      final response = await context.read<UserCubit>().chatbotService.ask(text);

      await _chatStorage.addMessage(
        sessionId: currentSession,
        sender: 'bot',
        text: response.answer,
      );
    } catch (_) {
      await _chatStorage.addMessage(
        sessionId: currentSession,
        sender: 'bot',
        text: 'Sorry, I couldn’t process that right now. Please try again.',
      );
    }

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });

    _scrollToBottom();
  }

  Future<void> _newChat() async {
    if (_isLoading) return;

    final id = await _chatStorage.createNewSession();

    if (!mounted) return;

    setState(() {
      _sessionId = id;
      _isLoading = false;
    });

    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final sessionId = _sessionId;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F1EB),
      body: Stack(
        children: [
          const Positioned.fill(
            child: ChatBackground(),
          ),
          Column(
            children: [
              Expanded(
                child: sessionId == null
                    ? CustomScrollView(
                        controller: _scrollController,
                        physics: const BouncingScrollPhysics(),
                        slivers: [
                          _buildSliverHeader(),
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.only(top: 80),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: AppColors.chestnutBrown,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _chatStorage.messagesStream(sessionId),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return CustomScrollView(
                              controller: _scrollController,
                              physics: const BouncingScrollPhysics(),
                              slivers: [
                                _buildSliverHeader(),
                                const SliverToBoxAdapter(
                                  child: Padding(
                                    padding: EdgeInsets.only(top: 80),
                                    child: Center(
                                      child: Text(
                                        'Could not load chat messages.',
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }

                          final docs = snapshot.data?.docs ?? [];

                          return CustomScrollView(
                            controller: _scrollController,
                            physics: const BouncingScrollPhysics(),
                            slivers: [
                              _buildSliverHeader(),
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  16,
                                  16,
                                  8,
                                ),
                                sliver: SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (context, index) {
                                      if (_isLoading && index == docs.length) {
                                        return const _TypingBubble();
                                      }

                                      final data = docs[index].data();
                                      final text =
                                          data['text']?.toString() ?? '';
                                      final sender =
                                          data['sender']?.toString() ?? 'bot';

                                      return ChatMessageBubble(
                                        text: text,
                                        isUser: sender == 'user',
                                      );
                                    },
                                    childCount:
                                        docs.length + (_isLoading ? 1 : 0),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
              ChatInputField(
                controller: _controller,
                onSend: _sendMessage,
              ),
            ],
          ),
        ],
      ),
    );
  }

  SliverAppBar _buildSliverHeader() {
    return SliverAppBar(
      expandedHeight: 220,
      pinned: true,
      stretch: true,
      elevation: 0,
      backgroundColor: AppColors.chestnutBrown,
      leadingWidth: 64,
      leading: Padding(
        padding: const EdgeInsets.only(left: 12, top: 6, bottom: 6),
        child: _GlassIconButton(
          icon: Icons.arrow_back_ios_new_rounded,
          onTap: () => Navigator.pop(context),
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12, top: 6, bottom: 6),
          child: _GlassActionButton(
            icon: Icons.add_comment_rounded,
            label: 'New Chat',
            onTap: _newChat,
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.chestnutBrown,
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.05),
                      Colors.black.withOpacity(0.12),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 10,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.20),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Travel Assistant',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Row(
                          children: [
                            Icon(
                              Icons.assistant_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'GeoGuide Assistant',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Ask about destinations, restaurants, hotels, and travel tips across Egypt.',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.92),
                            fontSize: 13.5,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFCFA),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomRight: Radius.circular(20),
            bottomLeft: Radius.circular(6),
          ),
          border: Border.all(
            color: const Color(0xFFE7DED5),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF8D6E63),
              ),
            ),
            SizedBox(width: 8),
            Text(
              'Thinking...',
              style: TextStyle(
                color: Color(0xFF5E544D),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _GlassIconButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: Colors.white.withOpacity(0.14),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withOpacity(0.20),
                ),
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _GlassActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: Colors.white.withOpacity(0.14),
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onTap,
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 13),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: Colors.white.withOpacity(0.20),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
