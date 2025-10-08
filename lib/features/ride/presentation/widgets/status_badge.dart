import 'package:flutter/material.dart';

class StatusBadge extends StatelessWidget {
  final bool isOnline;
  const StatusBadge({super.key, required this.isOnline});

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
