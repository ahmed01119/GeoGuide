import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String name;
  final String email;
  final String image;
  final List<String> favorites;
  final DateTime createdAt;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.image,
    required this.favorites,
    required this.createdAt,
  });

  // لتحويل الموديل إلى Map عشان نرفعها على Firestore
  Map<String, dynamic> toMap() {
    return {
      "uid": uid,
      "name": name,
      "email": email,
      "image": image,
      "favorites": favorites,
      "createdAt": Timestamp.fromDate(createdAt),
    };
  }

  // إنشاء موديل من DocumentSnapshot
  factory UserModel.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel(
      uid: data["uid"],
      name: data["name"],
      email: data["email"],
      image: data["image"] ?? "",
      favorites: List<String>.from(data["favorites"] ?? []),
      createdAt: (data["createdAt"] as Timestamp).toDate(),
    );
  }
}