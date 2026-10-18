import 'package:geolocator/geolocator.dart';

import 'emergency_data.dart';

class EmergencyLocationContext {
  final Position? position;
  final NearestCityResult? nearestCity;
  final String? locationError;

  const EmergencyLocationContext({
    this.position,
    this.nearestCity,
    this.locationError,
  });

  City? get nearbyCity {
    final match = nearestCity;
    return match != null && match.isWithinRange ? match.city : null;
  }

  bool get isOutOfCityRange =>
      nearestCity != null && !nearestCity!.isWithinRange;

  String get locationSummary {
    final position = this.position;
    if (position == null) return locationError ?? 'Location unavailable';
    final city = nearbyCity;
    final location = city == null ? 'Current location' : 'Near ${city.name}';
    return '$location, accuracy ${position.accuracy.round()} m';
  }

  String get helpNotice {
    if (position == null) {
      return '${locationError ?? 'Location unavailable.'} Showing national numbers only.';
    }
    if (isOutOfCityRange) {
      return 'More than 150 km from every listed city. Showing national numbers only.';
    }
    return 'City and phone details are unverified and may change.';
  }
}
