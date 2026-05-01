// ignore_for_file: file_names

class VisitRequest {
  final int landmarkId;
  final String visitDate;

  VisitRequest({
    required this.landmarkId,
    required this.visitDate,
  });

  Map<String, dynamic> toJson() {
    return {
      "landmark_id": landmarkId,
      "visit_date": visitDate,
    };
  }
}
