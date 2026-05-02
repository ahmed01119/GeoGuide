import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class CloudinaryService {
  static const String cloudName = 'dcdv2jm6v';
  static const String uploadPreset = 'geoguide';

  static Future<String> uploadProfileImage(XFile imageFile) async {
    final bytes = await imageFile.readAsBytes();

    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/$cloudName/image/upload',
    );

    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = uploadPreset
      ..fields['folder'] = 'geoguide/profile_images'
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: imageFile.name.isNotEmpty
              ? imageFile.name
              : 'profile_image.jpg',
        ),
      );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return data['secure_url'].toString();
    }

    throw Exception(data['error']?['message'] ?? 'Cloudinary upload failed');
  }
}