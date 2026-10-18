import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;

import 'emergency_config.dart';

enum EmergencyGroup { ambulance, police, fire, roadAssistance, hospitals }

class Contact {
  final String name;
  final List<String> phones;
  final String? address;
  final String? note;
  final bool primary;

  const Contact({
    required this.name,
    required this.phones,
    this.address,
    this.note,
    this.primary = false,
  });

  factory Contact.fromJson(Map<String, dynamic> json) => Contact(
        name: json['name'] as String,
        phones: (json['phones'] as List<dynamic>).cast<String>(),
        address: json['address'] as String?,
        note: json['note'] as String?,
        primary: json['primary'] as bool? ?? false,
      );
}

class City {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final List<Contact> ambulance;
  final List<Contact> police;
  final List<Contact> fire;
  final List<Contact> hospitals;

  const City({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.ambulance = const [],
    this.police = const [],
    this.fire = const [],
    this.hospitals = const [],
  });

  factory City.fromJson(Map<String, dynamic> json) => City(
        id: json['id'] as String,
        name: json['name'] as String,
        latitude: (json['lat'] as num).toDouble(),
        longitude: (json['lng'] as num).toDouble(),
        ambulance: _contacts(json['ambulance']),
        police: _contacts(json['police']),
        fire: _contacts(json['fire']),
        hospitals: _contacts(json['hospitals']),
      );

  static List<Contact> _contacts(dynamic value) => value is List
      ? value
          .map((contact) => Contact.fromJson(contact as Map<String, dynamic>))
          .toList()
      : const [];

  List<Contact> contactsFor(EmergencyGroup group) => switch (group) {
        EmergencyGroup.ambulance => ambulance,
        EmergencyGroup.police => police,
        EmergencyGroup.fire => fire,
        EmergencyGroup.roadAssistance => const [],
        EmergencyGroup.hospitals => hospitals,
      };
}

class EmergencyData {
  final String version;
  final bool verified;
  final List<Contact> national;
  final List<Contact> roadAssistance;
  final List<City> cities;

  const EmergencyData({
    required this.version,
    required this.verified,
    required this.national,
    required this.roadAssistance,
    required this.cities,
  });

  factory EmergencyData.fromJson(Map<String, dynamic> json) => EmergencyData(
        version: json['version'] as String,
        verified: json['verified'] as bool? ?? false,
        national: (json['national'] as List<dynamic>)
            .map((contact) => Contact.fromJson(contact as Map<String, dynamic>))
            .toList(),
        roadAssistance: (json['roadAssistance'] as List<dynamic>)
            .map((contact) => Contact.fromJson(contact as Map<String, dynamic>))
            .toList(),
        cities: (json['cities'] as List<dynamic>)
            .map((city) => City.fromJson(city as Map<String, dynamic>))
            .toList(),
      );
}

class NearestCityResult {
  final City? city;
  final double distanceKm;

  const NearestCityResult({required this.city, required this.distanceKm});

  bool get isWithinRange => distanceKm <= emergencyCityRadiusKm;
}

NearestCityResult nearestCity(
    List<City> cities, double latitude, double longitude) {
  City? nearest;
  var nearestDistance = double.infinity;
  for (final city in cities) {
    final distance = _distanceKm(
      latitude,
      longitude,
      city.latitude,
      city.longitude,
    );
    if (distance < nearestDistance) {
      nearest = city;
      nearestDistance = distance;
    }
  }
  return NearestCityResult(city: nearest, distanceKm: nearestDistance);
}

double _distanceKm(double firstLatitude, double firstLongitude,
    double secondLatitude, double secondLongitude) {
  const earthRadiusKm = 6371.0;
  final latitudeDelta = _radians(secondLatitude - firstLatitude);
  final longitudeDelta = _radians(secondLongitude - firstLongitude);
  final haversine = math.pow(math.sin(latitudeDelta / 2), 2) +
      math.cos(_radians(firstLatitude)) *
          math.cos(_radians(secondLatitude)) *
          math.pow(math.sin(longitudeDelta / 2), 2);
  return earthRadiusKm * 2 * math.asin(math.sqrt(haversine));
}

double _radians(double degrees) => degrees * math.pi / 180;

class ZimbabwePhoneNumberNormalizer {
  static final _shortCodes = {'999', '995', '993', '112', '114'};

  static String? normalize(String source) {
    final value = source.trim();
    if (value.isEmpty || !RegExp(r'^[+()0-9\s.-]+$').hasMatch(value)) {
      _logUnnormalizable(source);
      return null;
    }

    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (_shortCodes.contains(digits)) return digits;
    if (digits.startsWith('263')) {
      if (digits.length >= 7 && digits.length <= 15) return '+$digits';
      _logUnnormalizable(source);
      return null;
    }
    if (digits.startsWith('00') && digits.substring(2).startsWith('263')) {
      final international = digits.substring(2);
      if (international.length >= 7 && international.length <= 15) {
        return '+$international';
      }
      _logUnnormalizable(source);
      return null;
    }
    if (digits.startsWith('0') && digits.length >= 4 && digits.length <= 12) {
      return '+263${digits.substring(1)}';
    }

    _logUnnormalizable(source);
    return null;
  }

  static void _logUnnormalizable(String source) {
    debugPrint('Emergency number could not be normalized confidently: $source');
  }
}
