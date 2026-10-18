import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/maintenance_reminder_service.dart';
import '../widgets/common_widgets.dart';

class MaintenanceReminderCard extends StatelessWidget {
  const MaintenanceReminderCard({super.key});

  Future<void> _recordService(BuildContext context) async {
    final service = MaintenanceReminderService.instance;
    final record = await showDialog<_MaintenanceRecord>(
      context: context,
      builder: (_) => _RecordMaintenanceDialog(service: service),
    );
    if (record == null) return;
    try {
      await service.recordService(
        odometerKm: record.odometerKm,
        serviceDate: record.date,
        intervalKm: record.intervalKm,
      );
    } catch (error) {
      debugPrint('Saving maintenance reminder record failed: $error');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save the service record.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = MaintenanceReminderService.instance;
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final lastDate = service.lastServiceDate;
        final currentOdometer = service.estimatedOdometerKm;
        final nextOdometer = service.nextServiceOdometerKm;
        final dueDate = lastDate?.add(
          const Duration(days: defaultMaintenanceIntervalDays),
        );
        final distanceRemaining = nextOdometer == null || currentOdometer == null
            ? null
            : (nextOdometer - currentOdometer).ceil();
        final daysRemaining = dueDate?.difference(DateTime.now()).inDays;
        final isDue = service.isDue;

        return card(
          color: C.navy,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.event_note_rounded, color: Colors.white, size: 25),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Maintenance reminders',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                lastDate == null
                    ? 'Add your last service details to start mileage and date reminders.'
                    : isDue
                        ? 'Service reminder is due. Arrange maintenance using your vehicle manual or service provider.'
                        : 'Next reminder in ${distanceRemaining ?? 0} km or ${daysRemaining ?? 0} days, whichever comes first.',
                style: const TextStyle(color: Colors.white70, height: 1.35),
              ),
              if (lastDate != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _detail(
                        'Estimated mileage',
                        currentOdometer == null
                            ? '--'
                            : '${currentOdometer.toStringAsFixed(1)} km',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _detail(
                        'GPS since service',
                        '${service.gpsDistanceSinceServiceKm.toStringAsFixed(1)} km',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Last service: ${DateFormat.yMMMd().format(lastDate)} at '
                  '${service.lastServiceOdometerKm!.toStringAsFixed(0)} km',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _recordService(context),
                  icon: const Icon(Icons.edit_calendar_rounded),
                  label: Text(
                    lastDate == null ? 'Set maintenance baseline' : 'Update service record',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Mileage is an estimate accumulated from GPS during trips you start. These are reminders, not diagnostics or breakdown predictions.',
                style: TextStyle(color: Colors.white60, fontSize: 11, height: 1.35),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _detail(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
}

class _MaintenanceRecord {
  final double odometerKm;
  final DateTime date;
  final double intervalKm;

  const _MaintenanceRecord(this.odometerKm, this.date, this.intervalKm);
}

class _RecordMaintenanceDialog extends StatefulWidget {
  final MaintenanceReminderService service;

  const _RecordMaintenanceDialog({required this.service});

  @override
  State<_RecordMaintenanceDialog> createState() =>
      _RecordMaintenanceDialogState();
}

class _RecordMaintenanceDialogState extends State<_RecordMaintenanceDialog> {
  late final TextEditingController _odometerController;
  late final TextEditingController _intervalController;
  late DateTime _serviceDate;
  String? _error;

  @override
  void initState() {
    super.initState();
    _odometerController = TextEditingController(
      text: widget.service.estimatedOdometerKm?.toStringAsFixed(0) ?? '',
    );
    _intervalController = TextEditingController(
      text: widget.service.serviceIntervalKm.toStringAsFixed(0),
    );
    _serviceDate = widget.service.lastServiceDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _odometerController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  void _save() {
    final odometer = double.tryParse(_odometerController.text.trim());
    final interval = double.tryParse(_intervalController.text.trim());
    if (odometer == null ||
        !odometer.isFinite ||
        odometer < 0 ||
        interval == null ||
        !interval.isFinite ||
        interval <= 0) {
      setState(() => _error = 'Enter valid odometer and service interval values.');
      return;
    }
    Navigator.of(context).pop(_MaintenanceRecord(odometer, _serviceDate, interval));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Maintenance baseline'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _odometerController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Odometer at last service (km)',
              ),
            ),
            TextField(
              controller: _intervalController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Service interval (km)',
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final selected = await showDatePicker(
                    context: context,
                    initialDate: _serviceDate,
                    firstDate: DateTime(1990),
                    lastDate: DateTime.now(),
                  );
                  if (selected != null) setState(() => _serviceDate = selected);
                },
                icon: const Icon(Icons.calendar_today_rounded),
                label: Text('Last service: ${DateFormat.yMMMd().format(_serviceDate)}'),
              ),
            ),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'The date reminder interval is six months.',
                style: TextStyle(color: Colors.black54, fontSize: 12),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      );
}
