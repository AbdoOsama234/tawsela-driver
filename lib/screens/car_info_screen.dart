import 'package:drivers/main_screen.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../global/global.dart';

class CarInfoScreen extends StatefulWidget {
  const CarInfoScreen({super.key});

  @override
  State<CarInfoScreen> createState() => _CarInfoScreenState();
}

class _CarInfoScreenState extends State<CarInfoScreen> {

  final carModelTextEditingController=TextEditingController();
  final carNumberTextEditingController=TextEditingController();
  final carColorTextEditingController=TextEditingController();

  List<String>carType=["Car","Bike","Bus"];

  String? selectedCarType;


  final _formKey =GlobalKey<FormState>();


  _submit(){
    if(_formKey.currentState!.validate()){
      Map driverCarInfoMap={
       "carModel":carModelTextEditingController.text.trim(),
        "carNumber":carNumberTextEditingController.text.trim(),
        "carColor":carColorTextEditingController.text.trim(),

      };
      DatabaseReference userRef=FirebaseDatabase.instance.ref().child("drivers");
      userRef.child(currentUser!.uid).child("car_details").set(driverCarInfoMap);

       Fluttertoast.showToast(msg: "vehicle details has been saved. Congratulation");
      Navigator.push(context, MaterialPageRoute(builder: (c)=>MainScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final darkTheme = MediaQuery.of(context).platformBrightness == Brightness.dark;

    return GestureDetector(
      onTap: (){
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        body: ListView(
          padding: EdgeInsets.all(0),
          children: [
            Column(
              children: [
                Image.asset(darkTheme?"assets/city/city_dark.jpg":"assets/city/city_light.png"),

                SizedBox(height: 20,),
                
                Text("Add Car Details",
                  style: TextStyle(
                    color: darkTheme?Colors.purple:Colors.blue,
                    fontSize: 25,
                    fontWeight: FontWeight.bold
                  ),

                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(15,20,15,50),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Form(
                          key: _formKey,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              //Name
                              //Email
                              TextFormField(
                                inputFormatters: [
                                  LengthLimitingTextInputFormatter(50)
                                ],
                                decoration: InputDecoration(
                                  hintText: "Car Model",
                                  hintStyle: TextStyle(
                                    color: Colors.grey,
                                  ),
                                  filled: true,
                                  fillColor: darkTheme ?Colors.black45:Colors.grey.shade200,
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(40),
                                      borderSide: BorderSide(
                                          width: 0,
                                          style: BorderStyle.none
                                      )
                                  ),
                                  prefixIcon:Icon(Icons.directions_car_filled,color: darkTheme?Colors.purple:Colors.grey,),

                                ),
                                autovalidateMode: AutovalidateMode.onUserInteraction,
                                validator: (text){
                                  if(text==null || text.isEmpty){
                                    return 'Email can\'t be empty';
                                  }

                                  if(text.length<2){
                                    return 'Please enter a valide Email';
                                  }
                                  if(text.length > 99){
                                    return 'Email can\'t be more than 100';
                                  }
                                },
                                onChanged: (text)=>setState(() {
                                  carModelTextEditingController.text=text;
                                }),

                              ),
                              SizedBox(height: 20,),
                              TextFormField(
                                inputFormatters: [
                                  LengthLimitingTextInputFormatter(100)
                                ],
                                decoration: InputDecoration(
                                  hintText: "Car Number",
                                  hintStyle: TextStyle(
                                    color: Colors.grey,
                                  ),
                                  filled: true,
                                  fillColor: darkTheme ?Colors.black45:Colors.grey.shade200,
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(40),
                                      borderSide: BorderSide(
                                          width: 0,
                                          style: BorderStyle.none
                                      )
                                  ),
                                  prefixIcon:Icon(Icons.confirmation_num,color: darkTheme?Colors.purple:Colors.grey,),

                                ),
                                autovalidateMode: AutovalidateMode.onUserInteraction,
                                validator: (text){
                                  if(text==null || text.isEmpty){
                                    return 'Address can\'t be empty';
                                  }

                                  if(text.length<2){
                                    return 'Please enter a valide Address';
                                  }

                                },
                                onChanged: (text)=>setState(() {
                                  carNumberTextEditingController.text=text;
                                }),

                              ),
                              SizedBox(height: 20,),
                              TextFormField(
                                inputFormatters: [
                                  LengthLimitingTextInputFormatter(100)
                                ],
                                decoration: InputDecoration(
                                  hintText: "Car Color",
                                  hintStyle: TextStyle(
                                    color: Colors.grey,
                                  ),
                                  filled: true,
                                  fillColor: darkTheme ?Colors.black45:Colors.grey.shade200,
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(40),
                                      borderSide: BorderSide(
                                          width: 0,
                                          style: BorderStyle.none
                                      )
                                  ),
                                  prefixIcon:Icon(Icons.color_lens,color: darkTheme?Colors.purple:Colors.grey,),

                                ),
                                autovalidateMode: AutovalidateMode.onUserInteraction,
                                validator: (text){
                                  if(text==null || text.isEmpty){
                                    return 'Address can\'t be empty';
                                  }

                                  if(text.length<2){
                                    return 'Please enter a valide Address';
                                  }

                                },
                                onChanged: (text)=>setState(() {
                                  carColorTextEditingController.text=text;
                                }),

                              ),

                              SizedBox(height: 20,),
                              DropdownButtonFormField(
                                decoration: InputDecoration(
                                  hintText: "Please select the vehicle type",

                                  prefixIcon: Icon(Icons.car_crash,color: darkTheme?Colors.purple:Colors.grey,),
                                  filled: true,
                                  fillColor: darkTheme?Colors.black45:Colors.grey.shade200,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(40),
                                    borderSide: BorderSide(
                                      width: 0,
                                      style: BorderStyle.none
                                    )
                                  )
                                ),
                                  items: carType.map((car){
                                    return DropdownMenuItem(
                                        child: Text(
                                            car,
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      value: car,
                                    );
                                  }).toList(),
                                  onChanged: (newValue){
                                  setState(() {
                                    selectedCarType=newValue.toString();
                                  });
                                  }),

                              SizedBox(height: 20,),

                              ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor:darkTheme ? Colors.purple :Colors.blue,
                                      foregroundColor:darkTheme ? Colors.white :Colors.white ,
                                      elevation: 0, // كل ما الرقم زاد، الظل زاد
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(32)
                                      ),
                                      minimumSize: Size(double.infinity, 50)
                                  ),
                                  onPressed: (){
                                   _submit();
                                  },

                                  child: Text(
                                    "Confirm",
                                    style: TextStyle(
                                      fontSize: 20,
                                    ),

                                  )),
                              SizedBox(height: 10,),









                            ],
                          ))
                    ],

                  ),
                )

                
              ],
            )
          ],
        ),
      ),

    );
  }
}
