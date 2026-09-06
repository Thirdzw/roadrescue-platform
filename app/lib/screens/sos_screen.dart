import 'package:flutter/material.dart';
import '../services/location_service.dart';
import '../services/firestore_service.dart';
import '../models/job.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  final _locationService = LocationService();
  final _firestoreService = FirestoreService();

  bool _sending = false;
  String? _statusMessage;

  Future<void> _sendSos() async {
    setState(() {
      _sending = true;
      _statusMessage = 'Getting your location…';
    });

    try {
      final position = await _locationService.getCurrentLocation();

      setState(() => _statusMessage = 'Matching you with a nearby mechanic…');

      // TODO: replace with the real signed-in motorist id
      const motoristId = 'demo-motorist-id';

      final job = Job(
        id: '',
        motoristId: motoristId,
        latitude: position.latitude,
        longitude: position.longitude,
        status: JobStatus.requested,
        createdAt: DateTime.now(),
      );

      await _firestoreService.createJob(job);

      setState(() {
        _statusMessage = 'Request sent. Waiting for a mechanic to accept.';
      });
    } catch (e) {
      setState(() => _statusMessage = 'Could not send SOS: $e');
    } finally {
      setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SOS Rescue')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: _sending ? null : _sendSos,
                child: CircleAvatar(
                  radius: 80,
                  backgroundColor:
                      _sending ? Colors.grey : Colors.redAccent,
                  child: _sending
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'SOS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 24),
              if (_statusMessage != null)
                Text(_statusMessage!, textAlign: TextAlign.center),
              // TODO: once a mechanic accepts, show a live map + ETA here.
            ],
          ),
        ),
      ),
    );
  }
}
