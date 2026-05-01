// ignore_for_file: file_names

class SignUpResponse {
  final String message;

  SignUpResponse({required this.message});

  factory SignUpResponse.fromJson(Map<String, dynamic> json) {
    return SignUpResponse(
      message: json['message'],
    );
  }
}
