import 'package:flutter/material.dart';

class OfflineOverlay extends StatelessWidget {
  const OfflineOverlay({super.key});

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

