import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:drivers/features/ride/domain/entities/trip_stage.dart';

class TripHUDSheet extends StatelessWidget {
  final ValueListenable<TripStage> stageListenable;
  final ValueListenable<String?> etaListenable;
  final ValueListenable<String?> distListenable;
  final VoidCallback onPrimaryPressed;
  final VoidCallback onRecenter;
  final VoidCallback? onCancel;

  final ScrollController? scrollController;
  final VoidCallback? onClose;

  const TripHUDSheet({
    super.key,
    required this.stageListenable,
    required this.etaListenable,
    required this.distListenable,
    required this.onPrimaryPressed,
    required this.onRecenter,
    this.onCancel,
    this.scrollController,
    this.onClose,
  });

  String _title(TripStage s) {
    switch (s) {
      case TripStage.toPickup: return "في الطريق إلى الراكب";
      case TripStage.atPickup: return "وصلت لموقع الراكب";
      case TripStage.toDropoff: return "في الطريق إلى الوجهة";
      case TripStage.completed: return "تم إنهاء الرحلة";
      case TripStage.idle:
      default: return "لا توجد رحلة";
    }
  }

  String _primaryLabel(TripStage s) {
    switch (s) {
      case TripStage.toPickup: return "وصلت";
      case TripStage.atPickup: return "بدء الرحلة";
      case TripStage.toDropoff: return "إنهاء الرحلة";
      case TripStage.completed: return "تم";
      case TripStage.idle:
      default: return "جاهز";
    }
  }

  IconData _primaryIcon(TripStage s) {
    switch (s) {
      case TripStage.toPickup: return Icons.flag_rounded;
      case TripStage.atPickup: return Icons.play_arrow_rounded;
      case TripStage.toDropoff: return Icons.stop_rounded;
      case TripStage.completed: return Icons.check_rounded;
      case TripStage.idle:
      default: return Icons.local_taxi_rounded;
    }
  }

  Color _primaryColor(BuildContext context, TripStage s) {
    switch (s) {
      case TripStage.toPickup: return Colors.indigo;
      case TripStage.atPickup: return Colors.green;
      case TripStage.toDropoff: return Colors.redAccent;
      case TripStage.completed: return Colors.grey;
      case TripStage.idle:
      default: return Theme.of(context).colorScheme.primary;
    }
  }

  Widget _chip(BuildContext ctx, IconData icon, String text) {
    final dark = Theme.of(ctx).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: (dark ? Colors.white12 : Colors.black12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: (dark ? Colors.white24 : Colors.black12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _stageDots(TripStage s) {
    int active = 0;
    if (s == TripStage.toPickup) active = 0;
    if (s == TripStage.atPickup) active = 1;
    if (s == TripStage.toDropoff) active = 2;
    if (s == TripStage.completed) active = 3;

    final dots = List.generate(3, (i) {
      final on = i <= (active.clamp(0, 2));
      return AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        height: 6, width: on ? 22 : 10,
        margin: EdgeInsets.only(right: i == 2 ? 0 : 6),
        decoration: BoxDecoration(
          color: on ? Colors.greenAccent.withOpacity(.9) : Colors.grey.withOpacity(.4),
          borderRadius: BorderRadius.circular(999),
        ),
      );
    });
    return Row(children: dots);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: Stack(
          children: [
            BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(height: 1, color: Colors.transparent),
            ),
            Container(
              decoration: BoxDecoration(
                color: (dark ? const Color(0xFF121416) : Colors.white).withOpacity(dark ? .90 : .96),
                border: Border.all(width: 1, color: (dark ? Colors.white12 : Colors.black12)),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, -3))],
              ),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: ValueListenableBuilder<TripStage>(
                valueListenable: stageListenable,
                builder: (context, stage, _) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: onClose,
                        child: Container(
                          width: 56, height: 22,
                          margin: const EdgeInsets.only(bottom: 4),
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(.25),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                        ),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_title(stage),
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      color: dark ? Colors.white : Colors.black87,
                                    )),
                                const SizedBox(height: 6),
                                _stageDots(stage),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          ValueListenableBuilder<String?>(
                            valueListenable: etaListenable,
                            builder: (context, eta, __) {
                              return ValueListenableBuilder<String?>(
                                valueListenable: distListenable,
                                builder: (context, dist, ___) {
                                  return Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (eta != null) _chip(context, Icons.schedule_rounded, eta),
                                      if (eta != null && dist != null) const SizedBox(width: 8),
                                      if (dist != null) _chip(context, Icons.route_rounded, dist),
                                    ],
                                  );
                                },
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            onPrimaryPressed();
                          },
                          icon: Icon(_primaryIcon(stage), color: Colors.white),
                          label: Text(
                            _primaryLabel(stage),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryColor(context, stage),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: onRecenter,
                              icon: const Icon(Icons.my_location_rounded),
                              label: const Text("إعادة التمركز"),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: onCancel,
                              icon: const Icon(Icons.close_rounded),
                              label: const Text("إلغاء"),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                side: const BorderSide(color: Colors.redAccent),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    return SafeArea(
      top: false,
      child: (scrollController != null)
          ? SingleChildScrollView(
        controller: scrollController,
        physics: const ClampingScrollPhysics(),
        child: content,
      )
          : content,
    );
  }
}
