// ignore_for_file: file_names

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:geoguide/constants/app_assets.dart';
import 'package:geoguide/presntation/screens/chatbot-screen/chatbot.dart';

class BotButton extends StatelessWidget {
  final Offset initialOffset;
  final void Function(Offset) onDragEnd;

  const BotButton({
    super.key,
    required this.initialOffset,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Draggable(
      feedback: Material(
        color: Colors.transparent,
        child: _botAvatar(context, isDragging: true),
      ),
      childWhenDragging: const SizedBox(width: 56, height: 56),
      onDraggableCanceled: (velocity, offset) {
        onDragEnd(offset);
      },
      child: _botAvatar(context),
    );
  }

  Widget _botAvatar(BuildContext context, {bool isDragging = false}) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const ChatBotPage(),
          ),
        );
      },
      child: AnimatedScale(
        duration: const Duration(milliseconds: 180),
        scale: isDragging ? 1.06 : 1,
        child: Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8D6E63).withOpacity(0.28),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.10),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.35),
                    width: 2,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: ClipOval(
                    child: Image.asset(
                      AppAssets.botIcon,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}