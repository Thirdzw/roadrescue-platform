import 'package:flutter/material.dart';

import '../models/job.dart';
import '../services/firestore_service.dart';
import '../ui/provider_job_map_screen.dart';

class ProviderRescueJobsPanel extends StatefulWidget {
  const ProviderRescueJobsPanel({super.key});

  @override
  State<ProviderRescueJobsPanel> createState() =>
      _ProviderRescueJobsPanelState();
}

class _ProviderRescueJobsPanelState extends State<ProviderRescueJobsPanel> {
  final _firestore = FirestoreService();
  late final _openJobs = _firestore.watchOpenJobs();
  late final _activeJobs = _firestore.watchProviderJobs();

  Future<void> _accept(Job job) async {
    try {
      final mechanicId = await _firestore.currentUserId();
      await _firestore.updateJobStatus(
        job.id,
        JobStatus.matched.name,
        mechanicId: mechanicId,
      );
    } catch (error) {
      _showMessage('Could not accept this request: $error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Live rescue jobs',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        StreamBuilder<List<Job>>(
          stream: _openJobs,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _messageCard(
                'The live job feed requires a verified provider account. '
                'If this account is verified, check its Firebase access.',
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final jobs = snapshot.data!;
            return Column(
              children: jobs.isEmpty
                  ? [_messageCard('No active requests are available.')]
                  : jobs
                      .map(
                        (job) => _openJobCard(job),
                      )
                      .toList(growable: false),
            );
          },
        ),
        const SizedBox(height: 14),
        const Text(
          'Clients you are helping',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        StreamBuilder<List<Job>>(
          stream: _activeJobs,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _messageCard(
                'Could not load your assigned jobs: ${snapshot.error}',
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final jobs = snapshot.data!;
            return Column(
              children: jobs.isEmpty
                  ? [_messageCard('Accepted jobs will appear here.')]
                  : jobs.map(_activeJobCard).toList(growable: false),
            );
          },
        ),
      ],
    );
  }

  Widget _openJobCard(Job job) => Card(
        child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.car_repair)),
          title: Text(job.serviceType),
          subtitle: Text(
            '${job.notes?.isNotEmpty == true ? job.notes : 'Client requested roadside help'}\n'
            'Client has opted in to share live location during this request.',
          ),
          isThreeLine: true,
          trailing: FilledButton(
            onPressed: () => _accept(job),
            child: const Text('Accept'),
          ),
        ),
      );

  Widget _activeJobCard(Job job) => Card(
        child: ListTile(
          leading: const CircleAvatar(
            child: Icon(Icons.location_searching_rounded),
          ),
          title: Text(job.serviceType),
          subtitle: Text(
            job.locationSharingEnabled
                ? 'Client live location is available.'
                : 'Client has paused live location sharing.',
          ),
          trailing: IconButton(
            tooltip: 'Open client map',
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => ProviderJobMapScreen(jobId: job.id),
              ),
            ),
            icon: const Icon(Icons.map_outlined),
          ),
        ),
      );

  Widget _messageCard(String message) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(message),
        ),
      );
}
