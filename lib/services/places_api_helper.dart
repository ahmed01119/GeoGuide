class PlacesApiHelper {
  static const String apiKey = "AIzaSyClnVOvH1hqz1i-6ckTNYkPEEt0qFRHhik";

  static String getPhotoUrl(String photoRef) {
    return "https://maps.googleapis.com/maps/api/place/photo"
        "?maxwidth=800"
        "&photoreference=$photoRef"
        "&key=$apiKey";
  }
}