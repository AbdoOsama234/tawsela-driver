import 'package:google_maps_flutter/google_maps_flutter.dart';

/// خطوة ملاحة
class NavStep {
  final String instruction;
  final LatLng endLocation;
  final int distanceMeters;
  final int durationSeconds;

  NavStep({
    required this.instruction,
    required this.endLocation,
    required this.distanceMeters,
    required this.durationSeconds,
  });
}