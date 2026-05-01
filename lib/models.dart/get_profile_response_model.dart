// ignore_for_file: non_constant_identifier_names

class GetProfileResponse {
  final ProfileData data;

  GetProfileResponse({required this.data});

  factory GetProfileResponse.fromJson(Map<String, dynamic> json) {
    return GetProfileResponse(
      data: ProfileData.fromJson(json['data']),
    );
  }
}

class ProfileData {
  final String name;
  final String email;
  final String phone_number;
  final String country;
  final String role;

  ProfileData({
    required this.name,
    required this.email,
    required this.phone_number,
    required this.country,
    required this.role,
  });

  factory ProfileData.fromJson(Map<String, dynamic> json) {
    return ProfileData(
      name: json['name'],
      email: json['email'],
      phone_number: json['phone_number'],
      country: json['country'],
      role: json['role'],
    );
  }
}
