import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/emergency_config.dart';
import '../models/emergency_location_context.dart';
import '../services/emergency_call_service.dart';
import '../services/emergency_countdown_controller.dart';
import '../services/emergency_event_logger.dart';
import '../services/emergency_settings_service.dart';
import '../widgets/common_widgets.dart';

class EmergencyCountdownScreen extends StatefulWidget {
  final String number;
  final String triggerType;
  final EmergencyLocationContext location;
  final String? contactName;

  const EmergencyCountdownScreen({
    super.key,
    required this.number,
    required this.triggerType,
    required this.location,
    this.contactName,
  });

  @override
  State<EmergencyCountdownScreen> createState() =>
      _EmergencyCountdownScreenState();
}

class _EmergencyCountdownScreenState extends State<EmergencyCountdownScreen>
    with WidgetsBindingObserver {
  late final EmergencyCountdownController _controller;
  bool _finished = false;
  bool _cancelled = false;
  String? _callError;

  bool get _dryRun => EmergencySettingsService.instance.dryRunEnabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final settings = EmergencySettingsService.instance;
    _controller = EmergencyCountdownController(
      countdownSeconds: emergencyCountdownSeconds,
      dryRun: settings.dryRunEnabled,
      onTick: () {
        HapticFeedback.selectionClick();
        SystemSound.play(SystemSoundType.click);
      },
      onCancel: () {
        EmergencyEventLogger.record(
          event: 'cancelled',
          triggerType: widget.triggerType,
          nearestCity: widget.location.nearbyCity?.name,
          numberDialed: widget.number,
        );
        if (mounted) {
          setState(() {
            _cancelled = true;
            _finished = true;
          });
        }
      },
      onDryRun: () async {
        await EmergencyCallService.callNumber(
          number: widget.number,
          triggerType: widget.triggerType,
          dryRun: true,
          directCall: false,
          nearestCity: widget.location.nearbyCity?.name,
        );
        if (mounted) setState(() => _finished = true);
      },
      onCall: () async {
        try {
          final opened = await EmergencyCallService.callNumber(
            number: widget.number,
            triggerType: widget.triggerType,
            dryRun: false,
            directCall: settings.directCallEnabled,
            nearestCity: widget.location.nearbyCity?.name,
          );
          if (!opened && mounted) {
            setState(() => _callError = 'Could not open the phone app.');
          }
        } catch (error) {
          if (mounted) {
            setState(() => _callError = 'Call could not start: $error');
          }
        }
        if (mounted) setState(() => _finished = true);
      },
    )..start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.resume();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _controller.pause();
    }
  }

  Future<void> _shareLocation() async {
    if (widget.location.position == null || _finished) return;
    _controller.pause();
    try {
      final opened = await EmergencyCallService.openSmsComposer(
        context: widget.location,
        dryRun: _dryRun,
      );
      if (!mounted) return;
      if (_dryRun) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Dry-run message'),
            content: SelectableText(
                EmergencyCallService.locationMessage(widget.location)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      } else if (!opened) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the messaging app.')),
        );
      }
    } finally {
      if (mounted && !_finished) _controller.resume();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFFFF1F1),
        appBar: AppBar(
          title: const Text('Emergency call'),
          backgroundColor: const Color(0xFFFFF1F1),
        ),
        body: SafeArea(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
              child: Column(
                children: [
                  const Spacer(),
                  Icon(
                    _finished ? Icons.phone_in_talk_rounded : Icons.sos_rounded,
                    color: C.sosDark,
                    size: 58,
                  ),
                  const SizedBox(height: 22),
                  Text(
                    _finished
                      ? _cancelled
                        ? 'Call cancelled'
                        : _dryRun
                            ? 'Dry run complete'
                            : _callError == null
                                ? 'Opening phone app'
                                : 'Call not connected'
                        : 'Calling ${widget.number} in ${_controller.secondsRemaining} s',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: C.dark,
                        fontSize: 27,
                        fontWeight: FontWeight.w800),
                  ),
                  if (widget.contactName != null && !_finished) ...[
                    const SizedBox(height: 8),
                    Text(widget.contactName!,
                        style: const TextStyle(color: Colors.black54)),
                  ],
                  const SizedBox(height: 16),
                  Text(widget.location.locationSummary,
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(color: Colors.black87, fontSize: 16)),
                  if (_dryRun && _finished) ...[
                    const SizedBox(height: 16),
                    SelectableText('Dry run: would dial ${widget.number}'),
                  ],
                  if (_callError != null) ...[
                    const SizedBox(height: 16),
                    Text(_callError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: C.sosDark)),
                  ],
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: widget.location.position == null || _finished
                          ? null
                          : _shareLocation,
                      icon: const Icon(Icons.sms_outlined),
                      label: const Text('Share location by message'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 68,
                    child: FilledButton.icon(
                      onPressed: _finished
                          ? () => Navigator.of(context).pop()
                          : _controller.cancel,
                      icon: Icon(_finished
                          ? Icons.check_rounded
                          : Icons.close_rounded),
                      label: Text(_finished ? 'Done' : 'Cancel call'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _finished ? C.navy : C.sosDark,
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(
                            fontSize: 21, fontWeight: FontWeight.w800),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'RoadRescue helps connect you to services. It does not replace calling emergency services. Numbers may change.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
