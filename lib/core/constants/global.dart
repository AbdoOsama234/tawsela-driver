
import 'dart:async';

import 'package:drivers/features/ride/data/driver_data.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/ui/utils/stream_subscriber_mixin.dart';
import 'package:geolocator/geolocator.dart';

import '../../features/ride/data/direction_details_info.dart';
import '../../shared/models/user_model.dart';

final FirebaseAuth firebaseAuth= FirebaseAuth.instance;

User? currentUser;

StreamSubscription<Position>?streamSubscriptionPosition;
StreamSubscription<Position>?streamSubscriptionDriverLivePosition;


UserModel? userModelCurrentInfo;

Position? driverCurrentPosition;

DirectionDetailsInfo? tripDirectionDetailsInfo;

DriverData onlineDriverData=DriverData();

String? driverVehicleType="";
