import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'common_widgets.dart';

class FloatingNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const FloatingNav({super.key, required this.currentIndex, required this.onTap});

  static const tabs = [
    (Icons.sos_rounded, 'SOS'),
    (Icons.health_and_safety_outlined, 'Safety'),
    (Icons.build_outlined, 'Mechanic'),
  ];

  @override
  Widget build(BuildContext context) {
    final i = currentIndex;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: C.navy,
          borderRadius: BorderRadius.circular(40),
          boxShadow: [
            BoxShadow(
                color: C.navy.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 10))
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (var n = 0; n < tabs.length; n++)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTap(n);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.symmetric(
                      horizontal: n == i ? 20 : 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: n == i ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(children: [
                    Icon(tabs[n].$1,
                        color:
                            n == i ? C.navy : Colors.white.withValues(alpha: 0.7)),
                    if (n == i)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(tabs[n].$2,
                            style: const TextStyle(
                                color: C.navy, fontWeight: FontWeight.w700)),
                      ),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}