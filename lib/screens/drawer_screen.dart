import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

import '../global/global.dart';

class DrawerScreen extends StatelessWidget {
  const DrawerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = firebaseAuth.currentUser?.uid;

    if (uid == null) {
      return _DrawerShell(child: const _DrawerContent(displayName: 'Guest'));
    }

    final ref = FirebaseDatabase.instance.ref().child('users').child(uid);

    return _DrawerShell(
      child: StreamBuilder<DatabaseEvent>(
        stream: ref.onValue,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const _DrawerSkeleton();
          }

          if (!snap.hasData || snap.data!.snapshot.value == null) {
            return const _DrawerContent(displayName: 'Guest');
          }

          final data = snap.data!.snapshot.value;
          String name = 'Guest';
          if (data is Map && data['name'] != null) {
            name = data['name'].toString().trim();
          }

          return _DrawerContent(displayName: name);
        },
      ),
    );
  }
}

class _DrawerShell extends StatelessWidget {
  final Widget child;
  const _DrawerShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width * 0.78;
    final darkTheme = MediaQuery.of(context).platformBrightness == Brightness.dark;

    return SizedBox(
      width: width,

      child: Drawer(
        backgroundColor:darkTheme?Colors.black:Colors.white ,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 16),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _DrawerContent extends StatelessWidget {
  final String displayName;
  const _DrawerContent({required this.displayName});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark ? Colors.purple : Colors.blue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ===== Header Card =====
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [primary.withOpacity(.9), primary.withOpacity(.7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: primary.withOpacity(.3),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: Colors.white.withOpacity(.2),
                backgroundImage: const AssetImage("assets/users_image/person.png"),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Welcome back 👋',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
        ),

        const SizedBox(height: 10),

        // ===== Menu Items =====
        _SettingTile(icon: Icons.person_outline, title: 'Edit Profile', onTap: () {}),
        SizedBox(height: 30,),
        _SettingTile(icon: Icons.history, title: 'Your Trips', onTap: () {}),
        SizedBox(height: 30),

        _SettingTile(icon: Icons.card_giftcard_outlined, title: 'Free Trips', onTap: () {}),
        SizedBox(height: 30),

        _SettingTile(icon: Icons.account_balance_wallet_outlined, title: 'Payment', onTap: () {}),
        SizedBox(height: 30,),

        _SettingTile(icon: Icons.notifications_none_rounded, title: 'Notifications', onTap: () {}),
        SizedBox(height: 30,),

        _SettingTile(icon: Icons.help_outline_rounded, title: 'Help & Support', onTap: () {}),

        const SizedBox(height: 80),

        // ===== Logout Button =====
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ElevatedButton.icon(
            onPressed: () async {
              // await firebaseAuth.signOut();
              // Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
          ),
        ),
      ],
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback? onTap;

  const _SettingTile({required this.icon, required this.title, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: isDark ? Colors.white70 : Colors.black87),
      ),
      title: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onTap,
    );
  }
}

class _DrawerSkeleton extends StatelessWidget {
  const _DrawerSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(height: 100, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(16))),
          const SizedBox(height: 20),
          ...List.generate(
            5,
                (_) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(height: 50, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(12))),
            ),
          ),
        ],
      ),
    );
  }
}
