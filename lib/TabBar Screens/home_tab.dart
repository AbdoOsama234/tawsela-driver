import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui; // للـ ImageFilter.blur
import 'package:drivers/global/global.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../Assistants/assistants_methods.dart';
import '../Assistants/request_assistants.dart';
import '../ride_request_sheet.dart';

class HomeTabPage extends StatefulWidget {
  const HomeTabPage({super.key});

  @override
  State<HomeTabPage> createState() => _HomeTabPageState();
}

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

/// مراحل الرحلة
enum TripStage { idle, toPickup, atPickup, toDropoff, completed }

class _HomeTabPageState extends State<HomeTabPage> {
  GoogleMapController? newGoogleMapController;
  final Completer<GoogleMapController> _controllerGoogleMap = Completer<GoogleMapController>();

  static const CameraPosition _kGooglePlex = CameraPosition(
    target: LatLng(30.0444, 31.2357),
    zoom: 14.4746,
  );

  // ========= إذونات / أونلاين =========
  LocationPermission? _locationPermission;
  bool isDriverActive = false;

  // ========= Streams =========
  StreamSubscription<Position>? streamSubscriptionPosition;
  StreamSubscription<DatabaseEvent>? rideRequestSub;
  StreamSubscription<DatabaseEvent>? _acceptedRideWatcher;

  // ========= منع تكرار نفس الطلب =========
  String? _lastRequestId;

  // ========= الخريطة =========
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  PolylineId? _routePolylineIdPickup;
  PolylineId? _routePolylineIdDropoff;

  // ========= حالة الرحلة =========
  TripStage _stage = TripStage.idle;
  String? _activeRequestId;
  LatLng? _pickupLatLng;
  LatLng? _dropoffLatLng;

  // الملاحة
  List<NavStep> _routeSteps = [];
  int _currentStepIndex = 0;

  // بانر التعليمات أعلى الخريطة
  String _bannerText = "";
  String _bannerSub = "";

  // thresholds
  static const double _advanceThresholdMeters = 30.0;
  static const double _rerouteThresholdMeters = 80.0;
  static const double _autoArriveThresholdMeters = 25.0;

  // ========= HUD (Dialog) =========
  bool _hudShown = false;
  final ValueNotifier<TripStage> _hudStage = ValueNotifier<TripStage>(TripStage.idle);
  final ValueNotifier<String?> _hudEta = ValueNotifier<String?>(null);
  final ValueNotifier<String?> _hudDist = ValueNotifier<String?>(null);
  BuildContext? _hudContext;

  // ========= Map padding حسب ظهور الـ HUD =========
  double _mapBottomPadding = 170;
  static const double _mapBottomPaddingHUD = 260;
  static const double _mapBottomPaddingIdle = 170;

  // ========= Helpers =========
  String _fmtDist(int m) => m >= 1000 ? "${(m / 1000).toStringAsFixed(1)} كم" : "$m م";
  String _fmtDur(int s) {
    if (s < 60) return "$s ث";
    final m = (s / 60).floor();
    final rem = s % 60;
    if (m < 60) return rem == 0 ? "$m د" : "$m د ${rem}ث";
    final h = (m / 60).floor();
    final mm = m % 60;
    return mm == 0 ? "$h س" : "$h س ${mm}د";
  }

  (int meters, int seconds) _remainingStats() {
    if (_routeSteps.isEmpty) return (0, 0);
    int meters = 0, seconds = 0;
    for (int i = _currentStepIndex; i < _routeSteps.length; i++) {
      meters += _routeSteps[i].distanceMeters;
      seconds += _routeSteps[i].durationSeconds;
    }
    return (meters, seconds);
  }

  // ========= Permissions =========
  Future<bool> _ensureLocationReady() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      Fluttertoast.showToast(msg: "من فضلك فعّل خدمة الموقع (GPS)");
      await Geolocator.openLocationSettings();
      return false;
    }
    _locationPermission = await Geolocator.checkPermission();
    if (_locationPermission == LocationPermission.denied) {
      _locationPermission = await Geolocator.requestPermission();
    }
    if (_locationPermission == LocationPermission.deniedForever) {
      Fluttertoast.showToast(msg: "من فضلك فعّل صلاحية الموقع من إعدادات التطبيق");
      await Geolocator.openAppSettings();
      return false;
    }
    if (_locationPermission == LocationPermission.denied) {
      Fluttertoast.showToast(msg: "تم رفض صلاحية الموقع.");
      return false;
    }
    return true;
  }

  // ========= موقع السائق =========
  Future<void> locateDriverPosition() async {
    try {
      if (!await _ensureLocationReady()) return;

      final cPosition = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      driverCurrentPosition = cPosition;

      final latLng = LatLng(cPosition.latitude, cPosition.longitude);
      final cam = CameraPosition(target: latLng, zoom: 15);
      await newGoogleMapController?.animateCamera(CameraUpdate.newCameraPosition(cam));

      // لا ماركر للعربية — فقط نحدّث عنوان المستخدم
      await AssistantsMehods.searchAddressForGeographCoOrdinates(cPosition, context);
    } catch (_) {
      Fluttertoast.showToast(msg: "تعذر تحديد الموقع الحالي.");
    }
  }

  // ========= قراءة بيانات السائق =========
  Future<void> readCurrentDriverInformation() async {
    try {
      currentUser = firebaseAuth.currentUser;
      if (currentUser == null) return;

      final ref = FirebaseDatabase.instance.ref().child("drivers").child(currentUser!.uid);
      final snap = await ref.get();
      final val = snap.value;
      if (val is Map) {
        onlineDriverData.id = val["id"];
        onlineDriverData.name = val["name"];
        onlineDriverData.phone = val["phone"];
        onlineDriverData.email = val["email"];
        onlineDriverData.address = val["address"];
        final car = (val["car_details"] as Map?) ?? {};
        onlineDriverData.car_color = car["car_color"];
        onlineDriverData.car_model = car["car_model"];
        onlineDriverData.car_number = car["car_number"];
        driverVehicleType = (car["type"] ?? "").toString();
      }
    } catch (_) {}
  }

  // ========= أونلاين / أوفلاين =========
  Future<void> driverIsOnlineNow() async {
    if (currentUser == null) currentUser = firebaseAuth.currentUser;
    if (currentUser == null) return;

    final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    final driversRef = FirebaseDatabase.instance.ref().child("drivers").child(currentUser!.uid);

    await driversRef.child("newRideRequestId").remove();

    await driversRef.update({
      "newRideStatus": "idle",
      "location": {"lat": pos.latitude, "lng": pos.longitude},
    });

    _listenForRideRequests();
  }

  Future<void> driverOfflineNow() async {
    try {
      await streamSubscriptionPosition?.cancel();
      await rideRequestSub?.cancel();
      await _acceptedRideWatcher?.cancel();
      streamSubscriptionPosition = null;
      rideRequestSub = null;
      _acceptedRideWatcher = null;
      _lastRequestId = null;

      _resetAllNavigation();

      if (currentUser != null) {
        final driversRef = FirebaseDatabase.instance.ref().child("drivers").child(currentUser!.uid);
        await driversRef.update({"newRideStatus": "offline"});
        await driversRef.child("newRideRequestId").remove();
        await driversRef.child("location").remove();
      }
    } catch (_) {}
  }

  // ========= حساب الاتجاه بين نقطتين (للكاميرا فقط) =========
  double _bearingBetween(LatLng from, LatLng to) {
    final fLat = from.latitude * (math.pi / 180.0);
    final fLng = from.longitude * (math.pi / 180.0);
    final tLat = to.latitude * (math.pi / 180.0);
    final tLng = to.longitude * (math.pi / 180.0);
    final dLng = tLng - fLng;
    final y = math.sin(dLng) * math.cos(tLat);
    final x = math.cos(fLat) * math.sin(tLat) - math.sin(fLat) * math.cos(tLat) * math.cos(dLng);
    final brng = math.atan2(y, x);
    return (brng * 180.0 / math.pi + 360.0) % 360.0;
  }

  Future<void> _updateDrivingCamera(LatLng car, LatLng lookAt) async {
    final bearing = _bearingBetween(car, lookAt);
    await newGoogleMapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: car,
          zoom: (_stage == TripStage.toPickup || _stage == TripStage.toDropoff) ? 17 : 15,
          tilt: (_stage == TripStage.toPickup || _stage == TripStage.toDropoff) ? 55 : 0,
          bearing: bearing,
        ),
      ),
    );
  }

  // ========= تحديث الموقع =========
  Future<void> updateDriversLocationAtRealTime() async {
    streamSubscriptionPosition = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 8,
      ),
    ).listen((Position position) async {
      if (currentUser == null) return;

      driverCurrentPosition = position;

      if (isDriverActive) {
        final driversRef = FirebaseDatabase.instance.ref().child("drivers").child(currentUser!.uid);
        await driversRef.child("location").set({
          "lat": position.latitude,
          "lng": position.longitude,
        });
      }

      final newPos = LatLng(position.latitude, position.longitude);

      // تحديد نقطة النظر (بدون ماركر سيارة)
      LatLng lookAt = newPos;
      if (_stage == TripStage.toPickup && _routeSteps.isNotEmpty) {
        lookAt = _routeSteps[_currentStepIndex].endLocation;
      } else if (_stage == TripStage.toDropoff && _routeSteps.isNotEmpty) {
        lookAt = _routeSteps[_currentStepIndex].endLocation;
      } else if (_pickupLatLng != null) {
        lookAt = _pickupLatLng!;
      }

      await _updateDrivingCamera(newPos, lookAt);

      // تقدّم في الخطوات
      if ((_stage == TripStage.toPickup || _stage == TripStage.toDropoff) && _routeSteps.isNotEmpty) {
        final cur = _routeSteps[_currentStepIndex];
        final d = Geolocator.distanceBetween(
          newPos.latitude, newPos.longitude,
          cur.endLocation.latitude, cur.endLocation.longitude,
        );

        if (d < _advanceThresholdMeters && _currentStepIndex < _routeSteps.length - 1) {
          _currentStepIndex++;
          _updateBanner();
        } else {
          _updateBanner(currentDistanceOverride: d);
        }

        // وصول تلقائي لموقع الراكب
        if (_stage == TripStage.toPickup && _pickupLatLng != null) {
          final dp = Geolocator.distanceBetween(
            newPos.latitude, newPos.longitude,
            _pickupLatLng!.latitude, _pickupLatLng!.longitude,
          );
          if (dp <= _autoArriveThresholdMeters) {
            _markArrivedAtPickup();
          }
        }

        // نهاية المسار عند الوجهة
        if (_stage == TripStage.toDropoff && _currentStepIndex == _routeSteps.length - 1 && d < 15) {
          await _finishTripCompleted();
        }

        // ريروت
        if (_stage == TripStage.toPickup && _pickupLatLng != null) {
          await _recalculateIfOffRoute(newPos, _pickupLatLng!, toPickup: true);
        } else if (_stage == TripStage.toDropoff && _dropoffLatLng != null) {
          await _recalculateIfOffRoute(newPos, _dropoffLatLng!, toPickup: false);
        }
      }

      // حدّث HUD كل تحديث
      _refreshTripHUD();
    });
  }

  Future<void> _recalculateIfOffRoute(
      LatLng driver,
      LatLng target, {
        required bool toPickup,
      }) async {
    if (_routeSteps.isEmpty) return;
    final cur = _routeSteps[_currentStepIndex];
    final d = Geolocator.distanceBetween(
      driver.latitude, driver.longitude,
      cur.endLocation.latitude, cur.endLocation.longitude,
    );

    if (d > _rerouteThresholdMeters) {
      final details = await AssistantsMehods.obtainOriginToDestinationDirectionDetails(driver, target);
      if (details == null || details.e_points == null) return;

      final points = _decodePolyline(details.e_points!);
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final polyId = toPickup
          ? (_routePolylineIdPickup ?? const PolylineId("to_pickup"))
          : (_routePolylineIdDropoff ?? const PolylineId("to_dropoff"));

      setState(() {
        _polylines.removeWhere((p) => p.polylineId == polyId);
        _polylines.add(Polyline(
          polylineId: polyId,
          points: points,
          width: 6,
          color: toPickup
              ? (isDark ? Colors.purpleAccent : Colors.blue)
              : (isDark ? Colors.tealAccent : Colors.green),
        ));
      });

      _routeSteps = await _fetchSteps(driver, target);
      _currentStepIndex = 0;
      _updateBanner();
      _refreshTripHUD();
    }
  }

  // ========= طلبات الرحلة =========
  void _listenForRideRequests() {
    if (currentUser == null) return;

    final driverRef = FirebaseDatabase.instance
        .ref()
        .child("drivers")
        .child(currentUser!.uid)
        .child("newRideRequestId");

    rideRequestSub = driverRef.onValue.listen((event) async {
      final val = event.snapshot.value?.toString();

      if (val == null || val.isEmpty) {
        _lastRequestId = null;
        return;
      }
      if (_lastRequestId == val) return;
      _lastRequestId = val;

      await _fetchRideRequestInfo(val);
    });
  }

  Future<void> _fetchRideRequestInfo(String requestId) async {
    final rideRef = FirebaseDatabase.instance.ref().child("rideRequests").child(requestId);
    try {
      final snap = await rideRef.get();
      if (snap.value == null) return;
      final data = Map<String, dynamic>.from(snap.value as Map);

      final status = (data["status"] ?? "").toString();
      if (status != "searching") return;

      // فلترة النوع (اختياري)
      final reqVehicle = (data["vehicleType"] ?? "").toString();
      if (driverVehicleType != null &&
          driverVehicleType!.isNotEmpty &&
          reqVehicle.isNotEmpty &&
          driverVehicleType!.toLowerCase() != reqVehicle.toLowerCase()) {
        return;
      }

      final pickupAddr = data["originAddress"] ?? "غير محدد";
      final dropoffAddr = data["destinationAddress"] ?? "غير محدد";

      final originMap = (data["origin"] as Map?) ?? {};
      final destMap = (data["destination"] as Map?) ?? {};
      final pickupLat = (originMap["latitude"] is num)
          ? (originMap["latitude"] as num).toDouble()
          : double.tryParse("${originMap["latitude"]}");
      final pickupLng = (originMap["longitude"] is num)
          ? (originMap["longitude"] as num).toDouble()
          : double.tryParse("${originMap["longitude"]}");
      final dropLat = (destMap["latitude"] is num)
          ? (destMap["latitude"] as num).toDouble()
          : double.tryParse("${destMap["latitude"]}");
      final dropLng = (destMap["longitude"] is num)
          ? (destMap["longitude"] as num).toDouble()
          : double.tryParse("${destMap["longitude"]}");

      double fare = 0.0;
      final f = data["fare"];
      if (f is num) fare = f.toDouble();
      if (f is String) fare = double.tryParse(f) ?? 0.0;
      final currency = (data["currency"] ?? "SAR").toString();

      if (!mounted) return;

      // شاشة قبول/رفض
      final action = await showModalBottomSheet<String>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        enableDrag: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black54,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        builder: (_) => RideRequestSheet(
          requestId: requestId,
          pickup: pickupAddr,
          dropoff: dropoffAddr,
          fare: fare,
          currency: currency,
          timeoutSeconds: 20,
        ),
      );

      final uid = currentUser?.uid;
      if (uid == null || action == null) return;

      if (action == "accept") {
        await rideRef.update({"status": "accepted", "driverId": uid});
        await FirebaseDatabase.instance.ref("drivers/$uid/newRideRequestId").remove();

        HapticFeedback.mediumImpact();
        Fluttertoast.showToast(msg: "تم قبول الطلب ✅");
        _resetAllNavigation(keepCar: false);

        _activeRequestId = requestId;
        _acceptedRideWatcher?.cancel();
        _acceptedRideWatcher = FirebaseDatabase.instance
            .ref("rideRequests/$requestId/status")
            .onValue
            .listen((ev) {
          final st = ev.snapshot.value?.toString() ?? "";
          if (st == "cancelled") {
            _resetAllNavigation(keepCar: false);
            Fluttertoast.showToast(msg: "الطلب اتلغى من الراكب ❌");
          }
        });

        if (pickupLat != null && pickupLng != null) {
          _pickupLatLng = LatLng(pickupLat, pickupLng);
        }
        if (dropLat != null && dropLng != null) {
          _dropoffLatLng = LatLng(dropLat, dropLng);
        }

        if (_pickupLatLng != null && driverCurrentPosition != null) {
          final driverLatLng = LatLng(driverCurrentPosition!.latitude, driverCurrentPosition!.longitude);

          await _drawRouteToPickup(driverLatLng, _pickupLatLng!);
          _routeSteps = await _fetchSteps(driverLatLng, _pickupLatLng!);
          _currentStepIndex = 0;

          _stage = TripStage.toPickup;
          _bannerText = "اتجه إلى الراكب";
          _updateBanner();
          setState(() {});
          _refreshTripHUD(); // يظهر HUD
        }
      } else {
        await rideRef.update({"status": action == "timeout" ? "timeout" : "rejected"});
        await FirebaseDatabase.instance.ref("drivers/$uid/newRideRequestId").remove();
        Fluttertoast.showToast(msg: action == "timeout" ? "انتهى الوقت ⏱️" : "تم رفض الطلب ❌");
      }
    } catch (_) {}
  }

  // ========= رسم طرق =========
  Future<void> _drawRouteToPickup(LatLng origin, LatLng dest) async {
    final details = await AssistantsMehods.obtainOriginToDestinationDirectionDetails(origin, dest);
    if (details == null || details.e_points == null) return;

    final points = _decodePolyline(details.e_points!);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final polyId = _routePolylineIdPickup ?? const PolylineId("to_pickup");
    _routePolylineIdPickup = polyId;

    setState(() {
      _polylines.removeWhere((p) => p.polylineId == polyId);
      _polylines.add(Polyline(
        polylineId: polyId,
        points: points,
        width: 6,
        color: isDark ? Colors.purpleAccent : Colors.blue,
      ));
      _markers.removeWhere((m) => m.markerId.value == "pickup" || m.markerId.value == "dropoff");
      _markers.add(Marker(
        markerId: const MarkerId("pickup"),
        position: dest,
        infoWindow: const InfoWindow(title: "نقطة الالتقاط"),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ));
    });

    await _fitBounds(origin, dest);
  }

  Future<void> _drawRouteToDropoff(LatLng origin, LatLng dest) async {
    final details = await AssistantsMehods.obtainOriginToDestinationDirectionDetails(origin, dest);
    if (details == null || details.e_points == null) return;

    final points = _decodePolyline(details.e_points!);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final polyId = _routePolylineIdDropoff ?? const PolylineId("to_dropoff");
    _routePolylineIdDropoff = polyId;

    setState(() {
      _polylines.removeWhere((p) => p.polylineId == polyId);
      _polylines.add(Polyline(
        polylineId: polyId,
        points: points,
        width: 6,
        color: isDark ? Colors.tealAccent : Colors.green,
      ));
      _markers.removeWhere((m) => m.markerId.value == "dropoff");
      _markers.add(Marker(
        markerId: const MarkerId("dropoff"),
        position: dest,
        infoWindow: const InfoWindow(title: "الوجهة"),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ));
    });

    await _fitBounds(origin, dest);
  }

  Future<void> _fitBounds(LatLng a, LatLng b) async {
    final southWest = LatLng(
      math.min(a.latitude, b.latitude),
      math.min(a.longitude, b.longitude),
    );
    final northEast = LatLng(
      math.max(a.latitude, b.latitude),
      math.max(a.longitude, b.longitude),
    );
    final bounds = LatLngBounds(southwest: southWest, northeast: northEast);
    await newGoogleMapController?.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 70),
    );
  }

  // ========= Steps =========
  Future<List<NavStep>> _fetchSteps(LatLng origin, LatLng dest) async {
    final url =
        "https://maps.googleapis.com/maps/api/directions/json"
        "?origin=${origin.latitude},${origin.longitude}"
        "&destination=${dest.latitude},${dest.longitude}"
        "&mode=driving&language=ar"
        "&key=AIzaSyBDJ5s8ORghEYD0ttmVrMgVH334Uk4tMH0"; // ← ضع مفتاحك

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

  void _updateBanner({double? currentDistanceOverride}) {
    if (!(_stage == TripStage.toPickup || _stage == TripStage.toDropoff) || _routeSteps.isEmpty) {
      if (_stage != TripStage.atPickup) {
        _bannerText = "";
        _bannerSub = "";
      }
      if (mounted) setState(() {});
      return;
    }
    final step = _routeSteps[_currentStepIndex];
    final title = _stage == TripStage.toPickup ? "إلى الراكب: " : "إلى الوجهة: ";
    _bannerText = "$title${step.instruction}";

    final d = (currentDistanceOverride ?? step.distanceMeters).clamp(0, 1e9).toDouble();
    _bannerSub = "تبقّى ${_fmtDist(d.round())} لهذه المناورة";
    if (mounted) setState(() {});
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, lat = 0, lng = 0;
    while (index < encoded.length) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  // ========= تغييرات حالة الرحلة =========
  void _markArrivedAtPickup() async {
    if (_stage != TripStage.toPickup) return;
    _stage = TripStage.atPickup;
    _bannerText = "وصلت لموقع الراكب";
    _bannerSub = "ابدأ الرحلة للانطلاق إلى الوجهة";
    if (_activeRequestId != null) {
      await FirebaseDatabase.instance.ref("rideRequests/$_activeRequestId/status").set("arrived");
    }
    HapticFeedback.lightImpact();
    setState(() {});
    Fluttertoast.showToast(msg: "تم إعلام الراكب أنك وصلت ✅");
    _refreshTripHUD();
  }

  Future<void> _startTrip() async {
    if (_dropoffLatLng == null || driverCurrentPosition == null) return;
    final origin = LatLng(driverCurrentPosition!.latitude, driverCurrentPosition!.longitude);
    await _drawRouteToDropoff(origin, _dropoffLatLng!);
    _routeSteps = await _fetchSteps(origin, _dropoffLatLng!);
    _currentStepIndex = 0;
    _stage = TripStage.toDropoff;
    _bannerText = "ابدأ التوجّه إلى الوجهة";
    _updateBanner();
    if (_activeRequestId != null) {
      await FirebaseDatabase.instance.ref("rideRequests/$_activeRequestId/status").set("ongoing");
    }
    HapticFeedback.mediumImpact();
    setState(() {});
    _refreshTripHUD();
  }

  Future<void> _finishTripCompleted() async {
    _stage = TripStage.completed;
    _bannerText = "تم الوصول إلى الوجهة";
    _bannerSub = "";
    if (_activeRequestId != null) {
      await FirebaseDatabase.instance.ref("rideRequests/$_activeRequestId/status").set("completed");
    }
    HapticFeedback.heavyImpact();
    setState(() {});
    Fluttertoast.showToast(msg: "تم إنهاء الرحلة ✅");
    _refreshTripHUD();
  }

  void _resetAllNavigation({bool keepCar = false}) {
    _activeRequestId = null;
    _pickupLatLng = null;
    _dropoffLatLng = null;
    _routeSteps.clear();
    _polylines.clear();
    _markers.clear(); // لا تترك أي ماركر (لا يوجد car أساسًا)
    _currentStepIndex = 0;
    _bannerText = "";
    _bannerSub = "";
    _stage = TripStage.idle;
    setState(() {});
    _refreshTripHUD();
  }

  // ========= HUD Control =========
  Future<void> _showTripHUD() async {
    if (_hudShown || !mounted) return;
    _hudShown = true;
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: false,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black45,
      builder: (ctx) {
        _hudContext = ctx;
        return _TripHUDSheet(
          stageListenable: _hudStage,
          etaListenable: _hudEta,
          distListenable: _hudDist,
          onPrimaryPressed: () async {
            if (_hudStage.value == TripStage.toPickup) {
              _markArrivedAtPickup();
            } else if (_hudStage.value == TripStage.atPickup) {
              await _startTrip();
            } else if (_hudStage.value == TripStage.toDropoff) {
              await _finishTripCompleted();
            }
          },
          onRecenter: () async {
            if (driverCurrentPosition == null) return;
            final car = LatLng(
              driverCurrentPosition!.latitude,
              driverCurrentPosition!.longitude,
            );
            LatLng lookAt = _pickupLatLng ?? car;
            if (_routeSteps.isNotEmpty) {
              lookAt = _routeSteps[_currentStepIndex].endLocation;
            }
            await _updateDrivingCamera(car, lookAt);
            HapticFeedback.selectionClick();
          },
          onCancel: (_hudStage.value == TripStage.toPickup || _hudStage.value == TripStage.atPickup)
              ? () async {
            if (_activeRequestId != null) {
              await FirebaseDatabase.instance
                  .ref("rideRequests/$_activeRequestId/status")
                  .set("cancelled_by_driver");
            }
            _resetAllNavigation(keepCar: false);
            Fluttertoast.showToast(msg: "تم إلغاء الطلب");
          }
              : null,
        );
      },
    ).whenComplete(() {
      _hudShown = false;
      _hudContext = null;
    });

    _refreshTripHUD();
  }

  void _hideTripHUD() {
    if (_hudShown && _hudContext != null) {
      Navigator.of(_hudContext!).pop();
    }
    if (mounted) setState(() => _mapBottomPadding = _mapBottomPaddingIdle);
  }

  void _refreshTripHUD() {
    _hudStage.value = _stage;
    final (remM, remS) = _remainingStats();
    _hudEta.value = (remS > 0) ? _fmtDur(remS) : null;
    _hudDist.value = (remM > 0) ? _fmtDist(remM) : null;

    _maybeShowOrHideHUD();
  }

  void _maybeShowOrHideHUD() {
    if (_stage == TripStage.idle || _stage == TripStage.completed) {
      _hideTripHUD();
      if (mounted) setState(() => _mapBottomPadding = _mapBottomPaddingIdle);
    } else {
      _showTripHUD();
      if (mounted) setState(() => _mapBottomPadding = _mapBottomPaddingHUD);
    }
  }

  // ========= Lifecycle =========
  @override
  void initState() {
    super.initState();
    readCurrentDriverInformation();
  }

  @override
  void dispose() {
    streamSubscriptionPosition?.cancel();
    rideRequestSub?.cancel();
    _acceptedRideWatcher?.cancel();
    newGoogleMapController?.dispose();
    super.dispose();
  }

  // ========= UI =========
  @override
  Widget build(BuildContext context) {
    final darkTheme = MediaQuery.of(context).platformBrightness == Brightness.dark;

    final (remM, remS) = _remainingStats();
    final showInfoChip = (_stage == TripStage.toPickup || _stage == TripStage.toDropoff) && remM > 0;

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            padding: EdgeInsets.only(top: 30, bottom: _mapBottomPadding),
            mapType: MapType.normal,
            initialCameraPosition: _kGooglePlex,
            myLocationEnabled: true,
            zoomControlsEnabled: false,
            zoomGesturesEnabled: true,
            markers: _markers,
            polylines: _polylines,
            onMapCreated: (GoogleMapController controller) async {
              if (!_controllerGoogleMap.isCompleted) {
                _controllerGoogleMap.complete(controller);
              }
              newGoogleMapController = controller;
              await locateDriverPosition();
            },
          ),

          // بانر صغير أعلى الخريطة للتعليمات (AnimatedSwitcher)
          Positioned(
            top: 56,
            left: 12,
            right: 12,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, anim) => SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, -0.2), end: Offset.zero)
                    .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: (_stage == TripStage.toPickup || _stage == TripStage.toDropoff || _stage == TripStage.atPickup) && _bannerText.isNotEmpty
                  ? _BannerCard(key: const ValueKey("banner"), title: _bannerText, subtitle: _bannerSub)
                  : const SizedBox.shrink(key: ValueKey("no_banner")),
            ),
          ),

          // شارة الوقت والمسافة (اختياري)
          if (showInfoChip)
            Positioned(
              top: 12,
              right: 12,
              child: _InfoChip(
                timeText: _fmtDur(remS),
                distanceText: _fmtDist(remM),
              ),
            ),

          // Overlay للأوفلاين
          if (!isDriverActive) const _OfflineOverlay(),

          // شارة الحالة
          Positioned(
            top: 12,
            left: 12,
            child: _StatusBadge(isOnline: isDriverActive),
          ),
        ],
      ),

      // زر Online/Offline ثابت
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: FloatingActionButton.extended(
          onPressed: () async {
            if (!isDriverActive) {
              await driverIsOnlineNow();
              await updateDriversLocationAtRealTime();
              setState(() => isDriverActive = true);
              Fluttertoast.showToast(msg: "You are Online now");
            } else {
              await driverOfflineNow();
              setState(() => isDriverActive = false);
              Fluttertoast.showToast(msg: "You are Offline now");
            }
          },
          backgroundColor: isDriverActive ? Colors.green : (darkTheme ? Colors.purple : Colors.blue),
          icon: Icon(isDriverActive ? Icons.stop_circle_rounded : Icons.play_circle_rounded, color: Colors.white),
          label: Text(isDriverActive ? "إيقاف" : "ابدأ",
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 6,
        ),
      ),
    );
  }
}

/* =================== Widgets مساعدة للـ UI =================== */

class _BannerCard extends StatelessWidget {
  final String title;
  final String subtitle;
  const _BannerCard({super.key, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: (dark ? const Color(0xFF15181B) : Colors.black87).withOpacity(dark ? .72 : .78),
        border: Border.all(
          width: 0.7,
          color: dark ? Colors.white.withOpacity(.06) : Colors.white.withOpacity(.08),
        ),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(subtitle,
                style: TextStyle(color: Colors.white.withOpacity(.85), fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String timeText;
  final String distanceText;
  const _InfoChip({required this.timeText, required this.distanceText});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: (dark ? Colors.white12 : Colors.black12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: (dark ? Colors.white24 : Colors.black12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(timeText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          const SizedBox(width: 10),
          const Icon(Icons.route_rounded, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(distanceText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isOnline;
  const _StatusBadge({required this.isOnline});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: (isOnline ? Colors.green : Colors.grey.shade700).withOpacity(.92),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Icon(isOnline ? Icons.circle : Icons.circle_outlined, size: 12, color: Colors.white),
          const SizedBox(width: 8),
          Text(isOnline ? "Now Online" : "Now Offline",
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// HUD سفلي (BottomSheet) متفاعل مودرن
class _TripHUDSheet extends StatelessWidget {
  final ValueListenable<TripStage> stageListenable;
  final ValueListenable<String?> etaListenable;
  final ValueListenable<String?> distListenable;
  final VoidCallback onPrimaryPressed;
  final VoidCallback onRecenter;
  final VoidCallback? onCancel;

  const _TripHUDSheet({
    required this.stageListenable,
    required this.etaListenable,
    required this.distListenable,
    required this.onPrimaryPressed,
    required this.onRecenter,
    this.onCancel,
  });

  String _title(TripStage s) {
    switch (s) {
      case TripStage.toPickup: return "في الطريق إلى الراكب";
      case TripStage.atPickup: return "وصلت لموقع الراكب";
      case TripStage.toDropoff: return "في الطريق إلى الوجهة";
      case TripStage.completed: return "تم إنهاء الرحلة";
      case TripStage.idle:
      default: return "لا توجد رحلة";
    }
  }

  String _primaryLabel(TripStage s) {
    switch (s) {
      case TripStage.toPickup: return "وصلت";
      case TripStage.atPickup: return "بدء الرحلة";
      case TripStage.toDropoff: return "إنهاء الرحلة";
      case TripStage.completed: return "تم";
      case TripStage.idle:
      default: return "جاهز";
    }
  }

  IconData _primaryIcon(TripStage s) {
    switch (s) {
      case TripStage.toPickup: return Icons.flag_rounded;
      case TripStage.atPickup: return Icons.play_arrow_rounded;
      case TripStage.toDropoff: return Icons.stop_rounded;
      case TripStage.completed: return Icons.check_rounded;
      case TripStage.idle:
      default: return Icons.local_taxi_rounded;
    }
  }

  Color _primaryColor(BuildContext context, TripStage s) {
    switch (s) {
      case TripStage.toPickup: return Colors.indigo;
      case TripStage.atPickup: return Colors.green;
      case TripStage.toDropoff: return Colors.redAccent;
      case TripStage.completed: return Colors.grey;
      case TripStage.idle:
      default: return Theme.of(context).colorScheme.primary;
    }
  }

  Widget _chip(BuildContext ctx, IconData icon, String text) {
    final dark = Theme.of(ctx).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: (dark ? Colors.white12 : Colors.black12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: (dark ? Colors.white24 : Colors.black12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _stageDots(TripStage s) {
    int active = 0;
    if (s == TripStage.toPickup) active = 0;
    if (s == TripStage.atPickup) active = 1;
    if (s == TripStage.toDropoff) active = 2;
    if (s == TripStage.completed) active = 3;

    List<Widget> dots = List.generate(3, (i) {
      final on = i <= (active.clamp(0, 2));
      return AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        height: 6, width: on ? 22 : 10,
        margin: EdgeInsets.only(right: i == 2 ? 0 : 6),
        decoration: BoxDecoration(
          color: on ? Colors.greenAccent.withOpacity(.9) : Colors.grey.withOpacity(.4),
          borderRadius: BorderRadius.circular(999),
        ),
      );
    });
    return Row(children: dots);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: Stack(
            children: [
              // Blur خلفي
              BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(height: 1, color: Colors.transparent),
              ),
              // بطاقة زجاجية بحدّ خفيف
              Container(
                decoration: BoxDecoration(
                  color: (dark ? const Color(0xFF121416) : Colors.white).withOpacity(dark ? .90 : .96),
                  border: Border.all(width: 1, color: (dark ? Colors.white12 : Colors.black12)),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, -3))],
                ),
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                child: ValueListenableBuilder<TripStage>(
                  valueListenable: stageListenable,
                  builder: (context, stage, _) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // مقبض
                        Container(
                          width: 36, height: 4,
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(.35),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),

                        // العنوان + مؤشر مراحل + Chips
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_title(stage),
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                        color: dark ? Colors.white : Colors.black87,
                                      )),
                                  const SizedBox(height: 6),
                                  _stageDots(stage),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            ValueListenableBuilder<String?>(
                              valueListenable: etaListenable,
                              builder: (context, eta, __) {
                                return ValueListenableBuilder<String?>(
                                  valueListenable: distListenable,
                                  builder: (context, dist, ___) {
                                    return Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (eta != null) _chip(context, Icons.schedule_rounded, eta),
                                        if (eta != null && dist != null) const SizedBox(width: 8),
                                        if (dist != null) _chip(context, Icons.route_rounded, dist),
                                      ],
                                    );
                                  },
                                );
                              },
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // زر أساسي
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              onPrimaryPressed();
                            },
                            icon: Icon(_primaryIcon(stage), color: Colors.white),
                            label: Text(
                              _primaryLabel(stage),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryColor(context, stage),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 0,
                            ),
                          ),
                        ),

                        const SizedBox(height: 10),

                        // أزرار ثانوية
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: onRecenter,
                                icon: const Icon(Icons.my_location_rounded),
                                label: const Text("إعادة التمركز"),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: onCancel,
                                icon: const Icon(Icons.close_rounded),
                                label: const Text("إلغاء"),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.redAccent,
                                  side: const BorderSide(color: Colors.redAccent),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OfflineOverlay extends StatelessWidget {
  const _OfflineOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black87,
        child: Center(
          child: Container(
            width: 280,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, 6))],
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.power_settings_new_rounded, size: 40, color: Colors.redAccent),
                SizedBox(height: 10),
                Text("أنت حالياً أوفلاين", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                SizedBox(height: 6),
                Text("اضغط “ابدأ” للظهور للركّاب واستقبال الطلبات.", textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
