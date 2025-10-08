import 'package:flutter/material.dart';

class InfoChip extends StatelessWidget {
  final String timeText;
  final String distanceText;
  const InfoChip({super.key, required this.timeText, required this.distanceText});

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
