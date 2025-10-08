import 'package:drivers/core/services/assistant_api/assistants_methods.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/material.dart';

import '../../../../utils/geo_utils.dart';

class MapOverlays {
  static Future<List<LatLng>> routePoints(LatLng origin, LatLng dest) async {
    final details = await AssistantsMehods.obtainOriginToDestinationDirectionDetails(origin, dest);
    if (details == null || details.e_points == null) return [];
    return GeoUtils.decodePolyline(details.e_points!);
  }

  static Polyline buildPolyline({
    required String id,
    required List<LatLng> points,
    required bool toPickup,
    required bool isDark,
  }) {
    return Polyline(
      polylineId: PolylineId(id),
      points: points,
      width: 6,
      color: toPickup
          ? (isDark ? Colors.purpleAccent : Colors.blue)
          : (isDark ? Colors.tealAccent : Colors.green),
    );
  }

  static Marker pickupMarker(LatLng p) => Marker(
    markerId: const MarkerId("pickup"),
    position: p,
    infoWindow: const InfoWindow(title: "نقطة الالتقاط"),
    icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
  );

  static Marker dropoffMarker(LatLng p) => Marker(
    markerId: const MarkerId("dropoff"),
    position: p,
    infoWindow: const InfoWindow(title: "الوجهة"),
    icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
  );
}
