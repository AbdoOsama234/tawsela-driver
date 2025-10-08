import 'package:drivers/features/ride/domain/entities/nav_step.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:drivers/core/services/assistant_api/request_assistants.dart';

class DirectionsRemoteDataSource {
  const DirectionsRemoteDataSource();

  Future<List<NavStep>> fetchSteps(
      LatLng origin,
      LatLng dest, {
        required String apiKey,
      }) async {
    final url =
        "https://maps.googleapis.com/maps/api/directions/json"
        "?origin=${origin.latitude},${origin.longitude}"
        "&destination=${dest.latitude},${dest.longitude}"
        "&mode=driving&language=ar"
        "&key=AIzaSyBDJ5s8ORghEYD0ttmVrMgVH334Uk4tMH0";

    final res = await RequestAssistants.receiveRequest(url);
    if (res is! Map || res["status"] != "OK") return [];

    final routes = res["routes"] as List?;
    if (routes == null || routes.isEmpty) return [];
    final legs = routes[0]["legs"] as List?;
    if (legs == null || legs.isEmpty) return [];
    final steps = legs[0]["steps"] as List? ?? [];

    String stripHtml(String s) {
      final noTags = s.replaceAll(RegExp(r'<[^>]*>'), '');
      return noTags.replaceAll("&nbsp;", " ").replaceAll("&amp;", "&");
    }

    return steps.map((s) {
      final end = s["end_location"] as Map? ?? {};
      final dist = (s["distance"]?["value"] as num?)?.toInt() ?? 0;
      final dur = (s["duration"]?["value"] as num?)?.toInt() ?? 0;
      final instrHtml = (s["html_instructions"] ?? "").toString();
      return NavStep(
        instruction: stripHtml(instrHtml),
        endLocation: LatLng(
          (end["lat"] as num?)?.toDouble() ?? 0.0,
          (end["lng"] as num?)?.toDouble() ?? 0.0,
        ),
        distanceMeters: dist,
        durationSeconds: dur,
      );
    }).toList();
  }
}
