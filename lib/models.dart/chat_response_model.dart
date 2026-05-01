class ChatResponse {
  final String answer;
  final double responseTimeSec;

  ChatResponse({
    required this.answer,
    required this.responseTimeSec,
  });

  factory ChatResponse.fromJson(Map<String, dynamic> json) {
    return ChatResponse(
      answer: json['answer'],
      responseTimeSec: json['response_time_sec'],
    );
  }
}
