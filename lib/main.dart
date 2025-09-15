import 'package:drivers/screens/car_info_screen.dart';
import 'package:drivers/themeProvider/theme_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';


import 'auth/login_screen.dart';
import 'firebase_options.dart';
import 'infoHandler/app_info.dart';
import 'main_screen.dart';

void main() async{
  WidgetsFlutterBinding.ensureInitialized(); // 👈 السطر المهم

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context)=>AppInfo(),
      child: MaterialApp(
        title: 'Flutter Demo',
        themeMode: ThemeMode.system,
        theme: MyThemes.lightTheme,
        darkTheme: MyThemes.darkTheme,

        debugShowCheckedModeBanner: false ,
        home: LoginScreen(),
      ),
    );
  }
}


