import 'package:flutter/material.dart';

class BannerCard extends StatelessWidget {
  final String title;
  final String subtitle;
  const BannerCard({super.key, required this.title, required this.subtitle});

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
