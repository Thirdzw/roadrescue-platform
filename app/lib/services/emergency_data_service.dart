import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/emergency_data.dart';

class EmergencyDataService {
  EmergencyDataService._();

  static final instance = EmergencyDataService._();
  static const assetPath = 'assets/emergency_data.json';

  EmergencyData? _cached;

  Future<EmergencyData> load() async {
    final cached = _cached;
    if (cached != null) return cached;
    final jsonText = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(jsonText) as Map<String, dynamic>;
    return _cached = EmergencyData.fromJson(decoded);
  }
}
