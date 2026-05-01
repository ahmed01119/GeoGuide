import 'package:flutter/material.dart';

class ChatBackground extends StatelessWidget {
  const ChatBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF7F1EB),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFF7F1EB),
            Color(0xFFF4EDE6),
            Color(0xFFF7F1EB),
          ],
        ),
      ),
    );
  }
}