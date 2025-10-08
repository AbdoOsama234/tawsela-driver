import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class GeoUtils {
  static double bearingBetween(LatLng from, LatLng to) {
    final fLat = from.latitude * (math.pi / 180.0);
    final fLng = from.longitude * (math.pi / 180.0);
    final tLat = to.latitude * (math.pi / 180.0);
    final tLng = to.longitude * (math.pi / 180.0);
    final dLng = tLng - fLng;
    final y = math.sin(dLng) * math.cos(tLat);
    final x = math.cos(fLat) * math.sin(tLat) -
        math.sin(fLat) * math.cos(tLat) * math.cos(dLng);
    final brng = math.atan2(y, x);
    return (brng * 180.0 / math.pi + 360.0) % 360.0;
  }

  static List<LatLng> decodePolyline(String encoded) {
    final points = <LatLng>[];
    int index = 0, lat = 0, lng = 0;

    while (index < encoded.length) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0; result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  static LatLngBounds boundsBetween(LatLng a, LatLng b) {
    final southWest = LatLng(
      math.min(a.latitude, b.latitude),
      math.min(a.longitude, b.longitude),
    );
    final northEast = LatLng(
      math.max(a.latitude, b.latitude),
      math.max(a.longitude, b.longitude),
    );
    return LatLngBounds(southwest: southWest, northeast: northEast);
  }
}
