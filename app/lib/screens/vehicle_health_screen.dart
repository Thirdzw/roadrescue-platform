import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../models/vehicle.dart';

/// Displays live OBD-II readings and flags abnormal patterns.
/// TODO(iot-track): wire this up to flutter_blue_plus once the ELM327
/// dongle is streaming — for now it reads whatever the backend last
/// wrote to Firestore (real or simulated data, per task tracker #16).
class VehicleHealthScreen extends StatelessWidget {
  const VehicleHealthScreen({super.key});

  // TODO: replace with the real signed-in motorist's vehicle id
  static const _demoVehicleId = 'demo-vehicle-id';

  @override
  Widget build(BuildContext context) {
    final firestoreService = FirestoreService();

    return Scaffold(
      appBar: AppBar(title: const Text('Vehicle Health')),
      body: StreamBuilder<Vehicle?>(
        stream: firestoreService.watchVehicle(_demoVehicleId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final vehicle = snapshot.data;
          if (vehicle == null) {
            return const Center(child: Text('No vehicle data yet.'));
          }

          final reading = vehicle.lastHealthReading;
          final hasWarning = _hasAbnormalReading(reading);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (hasWarning)
                Card(
                  color: Colors.orange.shade100,
                  child: const ListTile(
                    leading: Icon(Icons.warning, color: Colors.orange),
                    title: Text('Early warning: possible fault detected'),
                    subtitle:
                        Text('Consider booking a mechanic before it strands you.'),
                  ),
                ),
              const SizedBox(height: 12),
              _ReadingTile(label: 'Engine temp', value: reading['engineTemp']),
              _ReadingTile(label: 'Battery voltage', value: reading['batteryVoltage']),
              _ReadingTile(label: 'Tyre pressure', value: reading['tyrePressure']),
            ],
          );
        },
      ),
    );
  }

  bool _hasAbnormalReading(Map<String, dynamic> reading) {
    // TODO: replace with real threshold logic (task tracker #13).
    final temp = reading['engineTemp'];
    return temp is num && temp > 110;
  }
}

class _ReadingTile extends StatelessWidget {
  final String label;
  final dynamic value;

  const _ReadingTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(label),
        trailing: Text(value?.toString() ?? '—'),
      ),
    );
  }
}
