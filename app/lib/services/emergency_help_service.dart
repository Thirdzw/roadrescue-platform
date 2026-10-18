import 'package:flutter/foundation.dart';

import '../models/emergency_data.dart';
import '../models/emergency_location_context.dart';
import 'emergency_data_service.dart';
import 'location_service.dart';

class EmergencyHelpService {
  EmergencyHelpService._();

  static final instance = EmergencyHelpService._();

  Future<EmergencyLocationContext> locate(EmergencyData data) async {
    try {
      final position = await LocationService.instance.getCurrentLocation(
        requestPermission: true,
      );
      return EmergencyLocationContext(
        position: position,
        nearestCity: nearestCity(
          data.cities,
          position.latitude,
          position.longitude,
        ),
      );
    } catch (error) {
      final reason = error is LocationAccessException
          ? error.message
          : 'Could not get a GPS fix.';
      debugPrint('Emergency location unavailable: $error');
      return EmergencyLocationContext(locationError: reason);
    }
  }

  Future<EmergencyData> loadData() => EmergencyDataService.instance.load();
}
