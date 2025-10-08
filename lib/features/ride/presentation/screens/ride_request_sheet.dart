import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RideRequestSheet extends StatefulWidget {
  final String requestId;
  final String pickup;
  final String dropoff;
  final double fare;
  final int timeoutSeconds;
  final String currency;

  /// ستريم حالة الرحلة من الداتا بيز/اللوجيك:
  /// ابعت قيم زي: searching / accepted / cancelled / timeout / ended ...
  final Stream<String>? statusStream;

  const RideRequestSheet({
    super.key,
    required this.requestId,
    required this.pickup,
    required this.dropoff,
    required this.fare,
    this.timeoutSeconds = 20,
    this.currency = "SAR",
    this.statusStream,
  });

  @override
  State<RideRequestSheet> createState() => _RideRequestSheetState();
}

class _RideRequestSheetState extends State<RideRequestSheet> {
  late int _secondsLeft;
  Timer? _timer;
  StreamSubscription<String>? _statusSub;

  bool _closed = false; // يمنع الـ pop المكرر

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.timeoutSeconds;

    // تايمر العدّ التنازلي
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        _finish("timeout");
      }
    });

    // اهتزاز بسيط عند الظهور
    HapticFeedback.mediumImpact();

    // لو في ستريم حالة، اسمع له
    if (widget.statusStream != null) {
      _statusSub = widget.statusStream!.listen((status) {
        final s = status.trim().toLowerCase();
        // أي حالة إنهاء من الراكب أو النظام
        if (s == "cancelled" ||
            s == "cancelled_by_user" ||
            s == "cancelled_by_driver" ||
            s == "timeout" ||
            s == "ended" ||
            s == "completed") {
          _finish(s == "timeout" ? "timeout" : "cancelled");
        }
      }, onError: (_) {
        // لو حصل خطأ في الستريم، تجاهل
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }

  // إقفال الشيت بأمان مرة واحدة
  void _finish(String result) {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    _statusSub?.cancel();
    if (mounted) {
      // لو إلغاء/تايم أوت هزة خفيفة
      if (result == "cancelled" || result == "timeout") {
        HapticFeedback.selectionClick();
      }
      Navigator.of(context).pop(result);
    }
  }

  double get _progress =>
      (_secondsLeft <= 0) ? 0 : _secondsLeft / widget.timeoutSeconds;

  Widget _chip({
    required IconData icon,
    required String text,
    required Color accent,
  }) {
    final darkTheme =
        MediaQuery.of(context).platformBrightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: darkTheme ? Colors.white.withOpacity(.06) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: darkTheme ? Colors.white10 : const Color(0xFFEAECEF),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accent, accent.withOpacity(.7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child:
            const Icon(Icons.circle, size: 0, color: Colors.transparent),
          ),
          const SizedBox(width: 8),
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: darkTheme ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final darkTheme =
        MediaQuery.of(context).platformBrightness == Brightness.dark;
    final Color primary = darkTheme ? Colors.purple : Colors.blue;
    final Color surface = darkTheme ? const Color(0xFF0E0F12) : Colors.white;
    final Color outline =
    darkTheme ? Colors.white12 : const Color(0xFFE7EAF0);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
        child: Material(
          color: surface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // handle
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: darkTheme ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 12),

                // العنوان + عدّاد
                Row(
                  children: [
                    CircleAvatar(
                      radius: 15,
                      backgroundColor: primary,
                      child: const Icon(Icons.local_taxi_rounded,
                          color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      "طلب جديد",
                      style: TextStyle(
                        color: darkTheme ? Colors.white : Colors.black87,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: (_secondsLeft <= 5)
                            ? Colors.red.withOpacity(.12)
                            : primary.withOpacity(.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: (_secondsLeft <= 5)
                              ? Colors.red.withOpacity(.45)
                              : primary.withOpacity(.40),
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              value: _progress,
                              color: (_secondsLeft <= 5)
                                  ? Colors.red
                                  : primary,
                              backgroundColor: outline,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "${_secondsLeft}s",
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: (_secondsLeft <= 5)
                                  ? Colors.red
                                  : primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // تايمر خطي
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: _progress,
                    minHeight: 6,
                    backgroundColor: outline,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      (_secondsLeft <= 5)
                          ? Colors.redAccent
                          : primary,
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // من / إلى
                _chip(
                  icon: Icons.radio_button_checked_rounded,
                  text: widget.pickup,
                  accent: primary,
                ),
                const SizedBox(height: 10),
                _chip(
                  icon: Icons.location_on_rounded,
                  text: widget.dropoff,
                  accent: Colors.grey,
                ),

                const SizedBox(height: 14),

                // السعر
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: darkTheme
                        ? Colors.white.withOpacity(.05)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: outline),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.green,
                        child: const Icon(Icons.payments_rounded,
                            color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        "السعر التقديري",
                        style: TextStyle(
                          color:
                          darkTheme ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(.10),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.green.withOpacity(.35)),
                        ),
                        child: Text(
                          "${widget.fare.toStringAsFixed(0)} ${widget.currency}",
                          style: const TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // الأزرار
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          _finish("reject");
                        },
                        icon: const Icon(Icons.close_rounded),
                        label: const Text("رفض"),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: BorderSide(color: outline),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                              BorderRadius.circular(12)),
                          foregroundColor: darkTheme
                              ? Colors.white70
                              : Colors.black87,
                          textStyle: const TextStyle(
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          HapticFeedback.heavyImpact();
                          _finish("accept");
                        },
                        icon: const Icon(Icons.check_circle_rounded),
                        label: const Text("قبول الرحلة",
                            style: TextStyle(
                                fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primary,
                          foregroundColor: Colors.white,
                          padding:
                          const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                              BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
