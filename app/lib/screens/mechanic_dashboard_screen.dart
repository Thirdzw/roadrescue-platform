import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/job.dart';
import '../services/client_location_sharing_service.dart';
import '../services/firestore_service.dart';
import '../services/location_service.dart';
import '../widgets/common_widgets.dart';
import 'maintenance_reminder_card.dart';

class MechanicScreen extends StatefulWidget {
  const MechanicScreen({super.key});
  @override
  State<MechanicScreen> createState() => _MechanicScreenState();
}

class _MechanicScreenState extends State<MechanicScreen> {
  static const filters = ['All', 'Towing', 'Tyre', 'Battery', 'Engine'];
  String filter = 'All';
  final _firestore = FirestoreService();
  final _locationSharing = ClientLocationSharingService.instance;
  late final Stream<List<Job>> _myJobs = _firestore.watchMyJobs();
  bool _creatingRequest = false;

  // Sample data: (name, service, rating, km, eta minutes)
  static const mechs = [
    ('Chinhoyi Auto Care', 'Engine', 4.8, 1.2, 8),
    ('QuickTow Services', 'Towing', 4.6, 2.5, 12),
    ('Tyre Masters', 'Tyre', 4.7, 3.1, 15),
    ('PowerCell Garage', 'Battery', 4.5, 4.0, 18),
  ];

  Widget meta(IconData i, String t) => Row(children: [
        Icon(i, size: 16, color: Colors.black45),
        const SizedBox(width: 4),
        Text(t, style: const TextStyle(fontSize: 13, color: Colors.black54)),
      ]);

  Widget mechCard(
    (String, String, double, double, int) m,
    bool canRequest,
  ) {
    final (name, service, rating, km, eta) = m;
    final icon = switch (service) {
      'Towing' => Icons.rv_hookup_rounded,
      'Tyre' => Icons.tire_repair_rounded,
      'Battery' => Icons.battery_charging_full_rounded,
      _ => Icons.build_rounded,
    };
    const orange = Color(0xFFFB8C00);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: card(Column(children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: orange.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: orange),
          ),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                    child: Text(name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: C.dark))),
                const SizedBox(width: 6),
                const Icon(Icons.verified_rounded, size: 16, color: C.navy),
              ]),
              Text(service,
                  style:
                      const TextStyle(fontSize: 12.5, color: Colors.black54)),
            ]),
          ),
          const Icon(Icons.star_rounded, color: Color(0xFFFFB300), size: 18),
          Text('$rating', style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          meta(Icons.near_me_rounded, '$km km'),
          const SizedBox(width: 14),
          meta(Icons.schedule_rounded, '$eta min'),
          const Spacer(),
          FilledButton(
            onPressed: !canRequest
                ? null
                : () {
                    HapticFeedback.mediumImpact();
                    unawaited(_requestProvider(service));
                  },
            style: FilledButton.styleFrom(backgroundColor: C.navy),
            child: const Text('Request'),
          ),
        ]),
      ])),
    );
  }

  Future<void> _requestProvider(String service) async {
    final shareLocation = await _confirmLocationSharing();
    if (shareLocation != true) return;

    setState(() => _creatingRequest = true);
    try {
      final position = await LocationService.instance
          .getCurrentLocation(requestPermission: true);
      if (DateTime.now().difference(position.timestamp) >
              const Duration(minutes: 1) ||
          !position.accuracy.isFinite ||
          position.accuracy > 100) {
        throw StateError(
          'A fresh, accurate GPS fix is required to request a provider.',
        );
      }
      final job = await _firestore.createRescueRequest(
        serviceType: service,
        position: position,
      );
      try {
        await _locationSharing.start(job.id);
      } catch (error) {
        _showMessage(
          'Request created, but live GPS sharing did not start: $error',
        );
        return;
      }
      _showMessage('Your request is visible to verified providers.');
    } catch (error) {
      _showMessage('Could not send the provider request: $error');
    } finally {
      if (mounted) setState(() => _creatingRequest = false);
    }
  }

  Future<bool?> _confirmLocationSharing() async {
    var enabled = false;
    return showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Share your location with a provider?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Verified providers can see your request location to accept '
                'the job. After one accepts, only that provider can see live '
                'GPS updates. You can pause sharing or cancel the request at '
                'any time.',
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: enabled,
                onChanged: (value) =>
                    setDialogState(() => enabled = value ?? false),
                title: const Text('I agree to share location for this request'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: enabled ? () => Navigator.pop(context, true) : null,
              child: const Text('Send request'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setLocationSharing(Job job, bool enabled) async {
    try {
      if (!enabled) {
        await _locationSharing.stopLocal(jobId: job.id);
      }
      await _firestore.updateJobLocationSharing(
        jobId: job.id,
        enabled: enabled,
      );
      if (enabled) {
        try {
          await _locationSharing.start(job.id);
        } catch (error) {
          await _firestore.updateJobLocationSharing(
            jobId: job.id,
            enabled: false,
          );
          rethrow;
        }
      } else {
        await _locationSharing.stopLocal(jobId: job.id);
      }
    } catch (error) {
      _showMessage('Could not update location sharing: $error');
    }
  }

  Future<void> _cancelJob(Job job) async {
    try {
      await _locationSharing.stopLocal(jobId: job.id);
      await _firestore.updateJobStatus(job.id, JobStatus.cancelled.name);
      _showMessage('Rescue request cancelled.');
    } catch (error) {
      _showMessage('Could not cancel the rescue request: $error');
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
    final list =
        filter == 'All' ? mechs : mechs.where((m) => m.$2 == filter).toList();
    return StreamBuilder<List<Job>>(
      stream: _myJobs,
      builder: (context, snapshot) {
        final jobs = snapshot.data ?? const <Job>[];
        for (final job in jobs) {
          if ((job.status == JobStatus.completed ||
                  job.status == JobStatus.cancelled ||
                  !job.locationSharingEnabled) &&
              _locationSharing.activeJobId == job.id) {
            unawaited(_locationSharing.stopLocal(jobId: job.id));
          }
        }
        final activeJobs = jobs
            .where((job) => [
                  JobStatus.requested,
                  JobStatus.matched,
                  JobStatus.enRoute,
                ].contains(job.status))
            .toList(growable: false);
        final canRequest = activeJobs.isEmpty && !_creatingRequest;
        return page(const Color(0xFFFFF1DE), [
          heading('Mechanics', 'Maintenance reminders and help nearby'),
          const MaintenanceReminderCard(),
          if (snapshot.hasError)
            card(
                Text('Could not load your rescue requests: ${snapshot.error}')),
          if (activeJobs.isNotEmpty) ...[
            sectionTitle('Your active rescue request'),
            for (final job in activeJobs) _activeJobCard(job),
          ],
          sectionTitle(
            'Nearby providers',
            trailing: Text('${list.length} found',
                style: const TextStyle(color: Colors.black54, fontSize: 13)),
          ),
          const Text(
            'Provider availability is still being onboarded. A request is '
            'shared with verified providers who can accept it.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final sel = filters[i] == filter;
                return ChoiceChip(
                  label: Text(filters[i]),
                  selected: sel,
                  showCheckmark: false,
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    setState(() => filter = filters[i]);
                  },
                  selectedColor: C.navy,
                  backgroundColor: Colors.white,
                  side: BorderSide.none,
                  labelStyle: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: sel ? Colors.white : C.dark),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          if (list.isEmpty)
            card(const Center(child: Text('No providers for this service.'))),
          for (final m in list) mechCard(m, canRequest),
          if (_creatingRequest) const LinearProgressIndicator(),
        ]);
      },
    );
  }

  Widget _activeJobCard(Job job) {
    final isActive =
        job.status != JobStatus.completed && job.status != JobStatus.cancelled;
    if (!isActive && _locationSharing.activeJobId == job.id) {
      unawaited(_locationSharing.stopLocal(jobId: job.id));
    }
    return card(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${job.serviceType} · ${job.status.name}',
          style: const TextStyle(fontWeight: FontWeight.w800, color: C.dark),
        ),
        const SizedBox(height: 8),
        Text(
          job.locationSharingEnabled
              ? 'Your assigned provider can see your live GPS location.'
              : 'Live location sharing is paused.',
        ),
        if (job.status == JobStatus.requested)
          const Text('Waiting for a verified provider to accept.'),
        if (job.locationSharingEnabled)
          ValueListenableBuilder<String?>(
            valueListenable: _locationSharing.error,
            builder: (context, error, _) => error == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child:
                        Text(error, style: const TextStyle(color: C.sosDark)),
                  ),
          ),
        if (isActive)
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Share live location'),
            value: job.locationSharingEnabled,
            onChanged: (enabled) => _setLocationSharing(job, enabled),
          ),
        if (isActive &&
            job.locationSharingEnabled &&
            _locationSharing.activeJobId != job.id)
          OutlinedButton.icon(
            onPressed: () async {
              try {
                await _locationSharing.start(job.id);
              } catch (error) {
                _showMessage('Could not resume live location sharing: $error');
              }
            },
            icon: const Icon(Icons.my_location_rounded),
            label: const Text('Resume live sharing'),
          ),
        if (isActive)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _cancelJob(job),
              child: const Text('Cancel request'),
            ),
          ),
      ],
    ));
  }
}
