import 'package:drivers/core/constants/global.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../home/earnings_tab.dart';
import '../../../home/home_tab.dart';
import '../../../home/profile_tab.dart';
import '../../../home/ratings_tab.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>with SingleTickerProviderStateMixin {


 TabController? tabController;
 int selectedIndex=0;

 onItemClicked(int index){
   setState(() {
     selectedIndex=index;
     tabController!.index=selectedIndex;
   });
 }


 @override
  void initState() {
    // TODO: implement initState
    super.initState();

    tabController=TabController(length: 4, vsync: this);
  }

  @override
  Widget build(BuildContext context) {

    bool darkTheme=MediaQuery.of(context).platformBrightness==Brightness.dark;
    return Scaffold(
      body:TabBarView(
        physics: NeverScrollableScrollPhysics(),
          controller: tabController,
          children: [
            HomeTabPage(),
            EarningsTabPage(),
            RatingsTabPage(),
            ProfileTabPage(),

          ]),
      
      bottomNavigationBar: BottomNavigationBar(
          items: [
            BottomNavigationBarItem(icon: Icon(Icons.home) ,label: "Home"),
            BottomNavigationBarItem(icon: Icon(Icons.credit_card) ,label: "Earnings"),
            BottomNavigationBarItem(icon: Icon(Icons.star) ,label: "Ratings"),
            BottomNavigationBarItem(icon: Icon(Icons.person) ,label: "Profile"),

          ],

        unselectedItemColor: darkTheme ? Colors.black54:Colors.white54,
        selectedItemColor: darkTheme ? Colors.black:Colors.white,
        backgroundColor: darkTheme ? Colors.purple:Colors.blue,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(fontSize: 14),
        showUnselectedLabels: true,
        currentIndex: selectedIndex,
        onTap: onItemClicked,


      ),
    );
  }
}
