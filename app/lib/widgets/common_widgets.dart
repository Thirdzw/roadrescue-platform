import 'package:flutter/material.dart';

class C {
  static const bg = Color(0xFFF8F7FE),
      navy = Color(0xFF4B5B94),
      dark = Color(0xFF2E3A66),
      sos = Color(0xFFFF5252),
      sosDark = Color(0xFFD32F2F),
      green = Color(0xFF2ECC71);
}

Widget card(Widget child,
        {Color color = Colors.white,
        EdgeInsets p = const EdgeInsets.all(16)}) =>
    Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 6))
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: p, child: child),
      ),
    );

Widget sectionTitle(String t, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Row(children: [
        Text(t,
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w800, color: C.dark)),
        const Spacer(),
        if (trailing != null) trailing,
      ]),
    );

Widget heading(String t, String s) => Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t,
            style: const TextStyle(
                fontSize: 28, fontWeight: FontWeight.w800, color: C.dark)),
        Text(s, style: const TextStyle(fontSize: 14, color: Colors.black54)),
      ]),
    );

Widget page(Color tint, List<Widget> children) => Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [tint, C.bg],
            stops: const [0, 0.32]),
      ),
      child: SafeArea(
        child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
            children: children),
      ),
    );