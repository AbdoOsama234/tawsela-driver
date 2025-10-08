import 'package:drivers/core/services/assistant_api/request_assistants.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../constants/global.dart';
import '../../../shared/state/app_info.dart';
import '../../../features/ride/data/direction_details_info.dart';
import '../../../features/ride/data/directions.dart';
import '../../../shared/models/user_model.dart';

class AssistantsMehods {
  /// قراءة بيانات المستخدم الحالي من Firebase
  static void readCurrentOnlineUserInfo() async {
    currentUser = firebaseAuth.currentUser;

    DatabaseReference userRef = FirebaseDatabase.instance
        .ref()
        .child("users")
        .child(currentUser!.uid);

    userRef.once().then((snap) {
      if (snap.snapshot.value != null) {
        userModelCurrentInfo = UserModel.formSnapshot(snap.snapshot);
      }
    });
  }

  /// جلب العنوان البشري من الإحداثيات (Geocoding)
  static Future<String> searchAddressForGeographCoOrdinates(
      Position position, context) async {
    final apiUrl =
        "https://maps.googleapis.com/maps/api/geocode/json"
        "?latlng=${position.latitude},${position.longitude}"
        "&key=AIzaSyBDJ5s8ORghEYD0ttmVrMgVH334Uk4tMH0";

    String humanReadableAddress = "";

    final response = await RequestAssistants.receiveRequest(apiUrl);

    // تأكد إن الرد صحيح
    if (response is! Map) return humanReadableAddress;

    if (response["status"] == "OK" &&
        response["results"] is List &&
        (response["results"] as List).isNotEmpty) {
      humanReadableAddress =
          response["results"][0]["formatted_address"] ?? "";

      final userPickUpAddress = Directions()
        ..locationLatitude = position.latitude
        ..locationLongitude = position.longitude
        ..locationName = humanReadableAddress;

      Provider.of<AppInfo>(context, listen: false)
          .updatePickUpLocationAddress(userPickUpAddress);
    }

    return humanReadableAddress;
  }

  /// جلب تفاصيل الاتجاهات من Google Directions API
  static Future<DirectionDetailsInfo?> obtainOriginToDestinationDirectionDetails(
      LatLng originPosition,
      LatLng destinationPosition,
      ) async {
    final url =
        "https://maps.googleapis.com/maps/api/directions/json"
        "?origin=${originPosition.latitude},${originPosition.longitude}"
        "&destination=${destinationPosition.latitude},${destinationPosition.longitude}"
        "&mode=driving"
        "&key=AIzaSyBDJ5s8ORghEYD0ttmVrMgVH334Uk4tMH0";

    final response = await RequestAssistants.receiveRequest(url);

    // لو الرد فاضي أو فيه خطأ
    if (response is! Map || response["status"] != "OK") {
      return null;
    }

    final routes = response["routes"] as List?;
    if (routes == null || routes.isEmpty) return null;

    final legs = routes[0]["legs"] as List?;
    if (legs == null || legs.isEmpty) return null;

    final info = DirectionDetailsInfo()
      ..e_points = routes[0]["overview_polyline"]?["points"] as String?
      ..distance_text = legs[0]["distance"]?["text"] as String?
      ..distance_value = (legs[0]["distance"]?["value"] as num?)?.toInt()
      ..duration_text = legs[0]["duration"]?["text"] as String?
      ..duration_value = (legs[0]["duration"]?["value"] as num?)?.toInt();

    return info;
  }
}
