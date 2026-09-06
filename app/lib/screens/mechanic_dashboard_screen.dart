import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../models/job.dart';

class MechanicDashboardScreen extends StatelessWidget {
  const MechanicDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final firestoreService = FirestoreService();

    return Scaffold(
      appBar: AppBar(title: const Text('Mechanic Dashboard')),
      body: StreamBuilder<List<Job>>(
        stream: firestoreService.watchOpenJobs(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final jobs = snapshot.data!;
          if (jobs.isEmpty) {
            return const Center(child: Text('No open jobs right now.'));
          }

          return ListView.builder(
            itemCount: jobs.length,
            itemBuilder: (context, index) {
              final job = jobs[index];
              return Card(
                margin: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                child: ListTile(
                  leading: const Icon(Icons.directions_car),
                  title: Text('Job #${job.id.substring(0, 6)}'),
                  subtitle: Text(
                      'Lat: ${job.latitude.toStringAsFixed(4)}, '
                      'Lng: ${job.longitude.toStringAsFixed(4)}'),
                  trailing: ElevatedButton(
                    onPressed: () {
                      // TODO: pass the real signed-in mechanic id
                      firestoreService.updateJobStatus(
                        job.id,
                        JobStatus.matched.name,
                        mechanicId: 'demo-mechanic-id',
                      );
                    },
                    child: const Text('Accept'),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
