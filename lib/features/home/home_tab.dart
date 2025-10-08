import 'dart:async';
import 'package:drivers/core/constants/global.dart';

import 'package:drivers/features/ride/data/datasources/directions_remote_data_source.dart';
import 'package:drivers/features/ride/domain/entities/nav_step.dart';
import 'package:drivers/features/ride/domain/entities/trip_stage.dart';
import 'package:drivers/features/ride/presentation/map/map_overlays.dart';
import 'package:drivers/features/ride/presentation/widgets/banner_card.dart';
import 'package:drivers/features/ride/presentation/widgets/info_chip.dart';
import 'package:drivers/features/ride/presentation/widgets/offline_overlay.dart';
import 'package:drivers/features/ride/presentation/widgets/status_badge.dart';
import 'package:drivers/features/ride/presentation/widgets/trip_hud_sheet.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/services/assistant_api/assistants_methods.dart';
import '../../utils/formatters.dart';
import '../../utils/geo_utils.dart';
import '../ride/presentation/screens/ride_request_sheet.dart';

class HomeTabPage extends StatefulWidget {
  const HomeTabPage({super.key});

  @override
  State<HomeTabPage> createState() => _HomeTabPageState();
}

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

  // ========= Data sources =========
  final _dirDs = const DirectionsRemoteDataSource();

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

  Future<void> _updateDrivingCamera(LatLng car, LatLng lookAt) async {
    final bearing = GeoUtils.bearingBetween(car, lookAt);
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

  /// ===== Helper: إعادة تمركز الكاميرا على السائق + تصفير الزوايا =====
  Future<void> _recenterToDriverAndResetCamera({double zoom = 15}) async {
    if (driverCurrentPosition == null || newGoogleMapController == null) return;
    final pos = LatLng(driverCurrentPosition!.latitude, driverCurrentPosition!.longitude);
    await newGoogleMapController!.animateCamera(
      CameraUpdate.newCameraPosition(CameraPosition(target: pos, zoom: zoom, tilt: 0, bearing: 0)),
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

      // تحديد نقطة النظر
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

      // حدّث HUD
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
      final points = await MapOverlays.routePoints(driver, target);
      if (points.isEmpty) return;

      final isDark = Theme.of(context).brightness == Brightness.dark;
      final polyId = toPickup
          ? (_routePolylineIdPickup ?? const PolylineId("to_pickup"))
          : (_routePolylineIdDropoff ?? const PolylineId("to_dropoff"));

      setState(() {
        _polylines.removeWhere((p) => p.polylineId == polyId);
        _polylines.add(MapOverlays.buildPolyline(
          id: polyId.value,
          points: points,
          toPickup: toPickup,
          isDark: isDark,
        ));
      });

      _routeSteps = await _dirDs.fetchSteps(driver, target, apiKey: "AIzaSyBDJ5s8ORghEYD0ttmVrMgVH334Uk4tMH0");
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
    // ندي الشيت ستريم الحالة علشان يقفل نفسه لو الراكب لغى
    final statusStream = FirebaseDatabase.instance
        .ref('rideRequests/$requestId/status')
        .onValue
        .map((e) => (e.snapshot.value ?? '').toString());

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
          statusStream: statusStream, // 👈 مهم
        ),
      );

      final uid = currentUser?.uid;
      if (uid == null || action == null) return;

      try {
        if (action == "accept") {
          // قبول الطلب
          await rideRef.update({"status": "accepted", "driverId": uid});
          await FirebaseDatabase.instance.ref("drivers/$uid/newRideRequestId").remove();

          await FirebaseDatabase.instance.ref("drivers/$uid").update({
            "newRideStatus": "incoming",
            "currentRideId": requestId,
          });

          HapticFeedback.mediumImpact();
          Fluttertoast.showToast(msg: "تم قبول الطلب ✅");
          _resetAllNavigation(keepCar: false);

          _activeRequestId = requestId;

          // راقب حالة الطلب بعد القبول
          _acceptedRideWatcher?.cancel();
          _acceptedRideWatcher = FirebaseDatabase.instance
              .ref("rideRequests/$requestId/status")
              .onValue
              .listen((ev) {
            final st = (ev.snapshot.value ?? "").toString().toLowerCase();
            if (st == "cancelled" ||
                st == "timeout" ||
                st == "cancelled_by_user" ||
                st == "cancelled_by_driver") {
              _resetAllNavigation(keepCar: false);
              Fluttertoast.showToast(
                msg: st == "timeout" ? "الطلب انتهى وقته ⏱️" : "الطلب اتلغى ❌",
              );
              FirebaseDatabase.instance.ref("drivers/$uid").update({
                "newRideStatus": "idle",
                "currentRideId": null,
              });
            }
          });

          // إحداثيات الالتقاط/الوجهة
          if (pickupLat != null && pickupLng != null) {
            _pickupLatLng = LatLng(pickupLat, pickupLng);
          }
          if (dropLat != null && dropLng != null) {
            _dropoffLatLng = LatLng(dropLat, dropLng);
          }

          // ابدأ الملاحة إلى الراكب
          if (_pickupLatLng != null && driverCurrentPosition != null) {
            final driverLatLng = LatLng(
              driverCurrentPosition!.latitude,
              driverCurrentPosition!.longitude,
            );

            await _drawRouteToPickup(driverLatLng, _pickupLatLng!);
            _routeSteps = await _dirDs.fetchSteps(
              driverLatLng,
              _pickupLatLng!,
              apiKey: "AIzaSyBDJ5s8ORghEYD0ttmVrMgVH334Uk4tMH0",
            );
            _currentStepIndex = 0;

            _stage = TripStage.toPickup;
            _bannerText = "اتجه إلى الراكب";
            _updateBanner();
            if (mounted) setState(() {});
            _refreshTripHUD();
          }
        } else if (action == "cancelled") {
          // الراكب لغى أثناء عرض الشيت
          await FirebaseDatabase.instance.ref("drivers/$uid/newRideRequestId").remove();
          HapticFeedback.selectionClick();
          Fluttertoast.showToast(msg: "الطلب اتلغى من الراكب ❌");
          _resetAllNavigation(keepCar: false);
          return;
        } else {
          // "reject" أو "timeout" من عداد السائق
          await rideRef.update({"status": action == "timeout" ? "timeout" : "rejected"});
          await FirebaseDatabase.instance.ref("drivers/$uid/newRideRequestId").remove();
          Fluttertoast.showToast(
            msg: action == "timeout" ? "انتهى الوقت ⏱️" : "تم رفض الطلب ❌",
          );
        }
      } catch (_) {
        // ممكن تضيف لوج هنا لو حابب
      }
    } catch (_) {}
  }

  // ========= رسم طرق =========
  Future<void> _drawRouteToPickup(LatLng origin, LatLng dest) async {
    final points = await MapOverlays.routePoints(origin, dest);
    if (points.isEmpty) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final polyId = _routePolylineIdPickup ?? const PolylineId("to_pickup");
    _routePolylineIdPickup = polyId;

    setState(() {
      _polylines.removeWhere((p) => p.polylineId == polyId);
      _polylines.add(MapOverlays.buildPolyline(
        id: polyId.value,
        points: points,
        toPickup: true,
        isDark: isDark,
      ));
      _markers.removeWhere((m) => m.markerId.value == "pickup" || m.markerId.value == "dropoff");
      _markers.add(MapOverlays.pickupMarker(dest));
    });

    await _fitBounds(origin, dest);
  }

  Future<void> _drawRouteToDropoff(LatLng origin, LatLng dest) async {
    final points = await MapOverlays.routePoints(origin, dest);
    if (points.isEmpty) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final polyId = _routePolylineIdDropoff ?? const PolylineId("to_dropoff");
    _routePolylineIdDropoff = polyId;

    setState(() {
      _polylines.removeWhere((p) => p.polylineId == polyId);
      _polylines.add(MapOverlays.buildPolyline(
        id: polyId.value,
        points: points,
        toPickup: false,
        isDark: isDark,
      ));
      _markers.removeWhere((m) => m.markerId.value == "dropoff");
      _markers.add(MapOverlays.dropoffMarker(dest));
    });

    await _fitBounds(origin, dest);
  }

  Future<void> _fitBounds(LatLng a, LatLng b) async {
    final bounds = GeoUtils.boundsBetween(a, b);
    await newGoogleMapController?.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 70),
    );
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
    _bannerSub = "تبقّى ${Formatters.distance(d.round())} لهذه المناورة";
    if (mounted) setState(() {});
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
    _routeSteps = await _dirDs.fetchSteps(origin, _dropoffLatLng!, apiKey: "AIzaSyBDJ5s8ORghEYD0ttmVrMgVH334Uk4tMH0");
    _currentStepIndex = 0;
    _stage = TripStage.toDropoff;
    _bannerText = "ابدأ التوجّه إلى الوجهة";
    _updateBanner();
    if (_activeRequestId != null) {
      await FirebaseDatabase.instance.ref("rideRequests/$_activeRequestId/status").set("ongoing");

      final uid = currentUser?.uid;
      if (uid != null) {
        await FirebaseDatabase.instance.ref("drivers/$uid").update({
          "newRideStatus": "busy",
        });
      }
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
      final uid = currentUser?.uid;
      if (uid != null) {
        await FirebaseDatabase.instance.ref("drivers/$uid").update({
          "newRideStatus": "idle",
          "currentRideId": null,
        });
      }
    }

    // تنظيف + رجوع الكاميرا
    _resetAllNavigation();
    await _recenterToDriverAndResetCamera(zoom: 15);

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
    _currentStepIndex = 0;

    _polylines.clear();
    _markers.clear();

    _routePolylineIdPickup = null;
    _routePolylineIdDropoff = null;

    _bannerText = "";
    _bannerSub = "";
    _stage = TripStage.idle;

    _mapBottomPadding = _mapBottomPaddingIdle;

    setState(() {});
    _refreshTripHUD();
  }

  // ========= HUD Control =========

  bool get _shouldShowReopenHandle =>
      (_stage != TripStage.idle && _stage != TripStage.completed) && !_hudShown;

  Future<void> _showTripHUD() async {
    if (_hudShown || !mounted) return;
    _hudShown = true;

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black45,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        _hudContext = ctx;
        return DraggableScrollableSheet(
          initialChildSize: 0.28,
          minChildSize: 0.12,
          maxChildSize: 0.85,
          expand: false,
          builder: (context, scrollController) {
            return TripHUDSheet(
              stageListenable: _hudStage,
              etaListenable: _hudEta,
              distListenable: _hudDist,
              scrollController: scrollController,
              onClose: () {
                Navigator.of(ctx).pop();
              },
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
                await _recenterToDriverAndResetCamera();
                Fluttertoast.showToast(msg: "تم إلغاء الطلب");
              }
                  : null,
            );
          },
        );
      },
    ).whenComplete(() {
      _hudShown = false;
      _hudContext = null;
      if (mounted) setState(() {}); // لتحديث زر السهم العائم
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
    _hudEta.value = (remS > 0) ? Formatters.duration(remS) : null;
    _hudDist.value = (remM > 0) ? Formatters.distance(remM) : null;

    _maybeShowOrHideHUD();
  }

  void _maybeShowOrHideHUD() {
    if (_stage == TripStage.idle || _stage == TripStage.completed) {
      _hideTripHUD();
      if (mounted) setState(() => _mapBottomPadding = _mapBottomPaddingIdle);
    } else {
      if (!_hudShown) _showTripHUD();
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
        alignment: Alignment.center,
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

          // بانر صغير أعلى الخريطة للتعليمات
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
                  ? BannerCard(key: const ValueKey("banner"), title: _bannerText, subtitle: _bannerSub)
                  : const SizedBox.shrink(key: ValueKey("no_banner")),
            ),
          ),

          // شارة الوقت والمسافة (اختياري)
          if (showInfoChip)
            Positioned(
              top: 12,
              right: 12,
              child: InfoChip(
                timeText: Formatters.duration(remS),
                distanceText: Formatters.distance(remM),
              ),
            ),

          // Overlay للأوفلاين
          if (!isDriverActive) const OfflineOverlay(),

          // شارة الحالة
          Positioned(
            top: 12,
            left: 12,
            child: StatusBadge(isOnline: isDriverActive),
          ),

          // ====== زر السهم العائم لإظهار الـHUD عند إغلاقه ======
          if (_shouldShowReopenHandle)
            Positioned(
              bottom: 100, // فوق زر الـFAB بشوية
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  _showTripHUD();
                },
                child: AnimatedOpacity(
                  opacity: 1,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white.withOpacity(0.12)),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white),
                        SizedBox(width: 4),
                        Text("إظهار اللوحة", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
              ),
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
