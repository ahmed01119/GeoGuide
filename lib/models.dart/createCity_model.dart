// ============================================================
//  models/createCity_model.dart
//
//  FIXES:
//  - Added image field correctly
//  - Added copyWith()
//  - Kept == and hashCode for DropdownButton<City>
// ============================================================

class City {
  final String id;
  final String name;
  final String image;
  final double lat;
  final double lng;

  const City({
    required this.id,
    required this.name,
    this.image = '',
    this.lat = 0,
    this.lng = 0,
  });

  factory City.fromJson(Map<String, dynamic> json, String id) {
    return City(
      id: id,
      name: json['name'] as String? ?? '',
      image: json['image'] as String? ?? '',
      lat: (json['lat'] ?? 0).toDouble(),
      lng: (json['lng'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'image': image,
        'lat': lat,
        'lng': lng,
      };

  City copyWith({
    String? id,
    String? name,
    String? image,
    double? lat,
    double? lng,
  }) {
    return City(
      id: id ?? this.id,
      name: name ?? this.name,
      image: image ?? this.image,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is City && other.id == id);

  @override
  int get hashCode => id.hashCode;
}