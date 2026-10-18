import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../models/emergency_data.dart';
import '../logic/crash_controller.dart';
import '../services/emergency_data_service.dart';
import '../services/emergency_event_logger.dart';
import '../services/emergency_help_service.dart';
import '../services/emergency_settings_service.dart';
import '../services/location_service.dart';
import '../services/demo_session.dart';
import '../widgets/common_widgets.dart';
import 'emergency_countdown_screen.dart';
import 'emergency_help_screen.dart';
import 'emergency_settings_screen.dart';

class SosScreen extends StatefulWidget {
  final VoidCallback? onMenuTap;
  final VoidCallback? onVoiceModeTap;

  const SosScreen({super.key, this.onMenuTap, this.onVoiceModeTap});
  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> with TickerProviderStateMixin {
  StreamSubscription<Position>? _positionSubscription;
  final _settings = EmergencySettingsService.instance;
  bool _triggering = false;
  bool _settingsLoaded = false;
  String _gpsStatus = 'Location only on emergency';

  late final pulse =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))
        ..repeat();
  late final hold =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) {
            unawaited(_beginEmergencyCall('sos_hold'));
          }
        });

  @override
  void initState() {
    super.initState();
    _settings.addListener(_syncSettings);
    _positionSubscription = LocationService.instance.positions.listen(
      (_) {
        if (mounted &&
            _settings.isTripActive &&
            _gpsStatus != 'Trip location active') {
          setState(() => _gpsStatus = 'Trip location active');
        }
      },
      onError: (Object _) {
        if (mounted && _settings.isTripActive) {
          setState(() => _gpsStatus = 'Trip location unavailable');
        }
      },
    );
    unawaited(_initializeSettings());
  }

  Future<void> _initializeSettings() async {
    try {
      await _settings.load();
      _settingsLoaded = true;
      _syncSettings();
      if (mounted) setState(() {});
    } catch (error) {
      debugPrint('Loading emergency settings failed: $error');
    }
  }

  void _syncSettings() {
    if (!_settingsLoaded) return;
    final crashController = CrashController.instance;
    if (!DemoSession.instance.isActive &&
        _settings.autoCrashDetectionEnabled &&
        !crashController.isRunning) {
      unawaited(crashController.start().catchError((Object error) {
        debugPrint('Crash monitoring failed to start: $error');
      }));
    } else if (!DemoSession.instance.isActive &&
        !_settings.autoCrashDetectionEnabled &&
        crashController.isRunning) {
      unawaited(crashController.stop());
    }
    final locationService = LocationService.instance;
    if (_settings.isTripActive && !locationService.isTracking) {
      unawaited(_startTripLocation());
    } else if (!_settings.isTripActive && locationService.isTracking) {
      unawaited(locationService.stopTracking());
    }
  }

  Future<void> _startTripLocation() async {
    try {
      await LocationService.instance.startTracking();
      if (mounted && _settings.isTripActive) {
        setState(() => _gpsStatus = 'Trip location active');
      }
    } on LocationAccessException catch (error) {
      if (mounted) setState(() => _gpsStatus = error.message);
    } catch (error) {
      debugPrint('Trip location failed: $error');
      if (mounted) setState(() => _gpsStatus = 'Trip location unavailable');
    }
  }

  Future<void> _toggleTrip() async {
    if (!_settings.tripTrackingEnabled) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => const EmergencySettingsScreen()),
      );
      return;
    }
    if (_settings.isTripActive) {
      await _settings.endTrip();
      await LocationService.instance.stopTracking();
      if (mounted) setState(() => _gpsStatus = 'Location only on emergency');
      return;
    }
    try {
      await LocationService.instance.startTracking();
      await _settings.startTrip();
      if (mounted) setState(() => _gpsStatus = 'Trip location active');
    } on LocationAccessException catch (error) {
      if (mounted) {
        setState(() => _gpsStatus = error.message);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (error) {
      debugPrint('Starting trip failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start trip location.')),
        );
      }
    }
  }

  Future<void> _beginEmergencyCall(String triggerType) async {
    if (_triggering || !mounted) return;
    _triggering = true;
    final triggeredAt = DateTime.now().toUtc();
    var triggerLogged = false;
    String? nearestCityName;
    String? numberDialed;
    hold.stop();
    HapticFeedback.heavyImpact();
    try {
      await _settings.load();
      final data = await EmergencyDataService.instance.load();
      final location = await EmergencyHelpService.instance.locate(data);
      nearestCityName = location.nearbyCity?.name;
      final primary = data.national.firstWhere(
        (contact) => contact.primary,
        orElse: () => data.national.first,
      );
      final number = primary.phones
          .map(ZimbabwePhoneNumberNormalizer.normalize)
          .whereType<String>()
          .firstOrNull;
      if (number == null) {
        throw StateError('No dialable national emergency number is bundled.');
      }
      numberDialed = number;
      await EmergencyEventLogger.record(
        event: 'triggered',
        triggerType: triggerType,
        occurredAt: triggeredAt,
        nearestCity: location.nearbyCity?.name,
        numberDialed: number,
      );
      triggerLogged = true;
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => EmergencyCountdownScreen(
            number: number,
            triggerType: triggerType,
            location: location,
          ),
        ),
      );
    } catch (error) {
      if (!triggerLogged) {
        await EmergencyEventLogger.record(
          event: 'triggered',
          triggerType: triggerType,
          occurredAt: triggeredAt,
          nearestCity: nearestCityName,
          numberDialed: numberDialed,
        );
      }
      debugPrint('Emergency call setup failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Emergency call could not be prepared. Open Emergency Help to use a national number.',
          ),
          duration: Duration(seconds: 8),
        ),
      );
    } finally {
      _triggering = false;
      if (mounted) hold.reset();
    }
  }

  Future<void> _openHelp() => Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => const EmergencyHelpScreen()),
      );

  Future<void> _openSettings() => Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => const EmergencySettingsScreen()),
      );

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _settings.removeListener(_syncSettings);
    if (!_settings.isTripActive) {
      unawaited(LocationService.instance.stopTracking());
    }
    pulse.dispose();
    hold.dispose();
    super.dispose();
  }

  Widget chip(IconData icon, String text) => Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: C.green),
          const SizedBox(width: 6),
          Text(text,
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600, color: C.dark)),
        ]),
      );

  void release() {
    if (hold.status != AnimationStatus.completed) hold.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).height < 700;
    final size = compact ? 150.0 : 210.0;
    final buttonExtent = compact ? 230.0 : 320.0;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFEDED), C.bg, C.bg],
            stops: [0, 0.35, 1]),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(children: [
            SizedBox(height: compact ? 4 : 12),
            Row(children: [
              Builder(
                builder: (context) => IconButton(
                  onPressed: widget.onMenuTap,
                  tooltip: 'Open menu',
                  icon: const Icon(Icons.menu_rounded, color: C.navy),
                ),
              ),
              const Expanded(
                  child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Emergency',
                          style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: C.dark)))),
              IconButton(
                onPressed: _openHelp,
                tooltip: 'Emergency help directory',
                icon: const Icon(Icons.help_outline_rounded, color: C.navy),
              ),
              IconButton(
                onPressed: _openSettings,
                tooltip: 'Emergency settings',
                icon: const Icon(Icons.settings_outlined, color: C.navy),
              ),
              IconButton.filledTonal(
                onPressed: widget.onVoiceModeTap,
                tooltip: 'Driving voice mode',
                icon: const Icon(Icons.mic_none_rounded),
              ),
            ]),
            SizedBox(height: compact ? 8 : 14),
            Row(children: [
              Expanded(child: chip(Icons.location_on_rounded, _gpsStatus)),
              if (_settings.tripTrackingEnabled)
                TextButton.icon(
                  onPressed: _toggleTrip,
                  icon: Icon(_settings.isTripActive
                      ? Icons.stop_circle_outlined
                      : Icons.play_circle_outline_rounded),
                  label:
                      Text(_settings.isTripActive ? 'End trip' : 'Start trip'),
                ),
            ]),
            const Spacer(),
            SizedBox(
              width: buttonExtent,
              height: buttonExtent,
              child: Stack(alignment: Alignment.center, children: [
                AnimatedBuilder(
                  animation: pulse,
                  builder: (_, __) => Stack(
                    alignment: Alignment.center,
                    children: [
                      for (var i = 0; i < 2; i++)
                        Builder(builder: (_) {
                          final t = (pulse.value + i * 0.5) % 1.0;
                          return Container(
                            width: size + t * (compact ? 60 : 110),
                            height: size + t * (compact ? 60 : 110),
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: C.sos.withValues(alpha: (1 - t) * 0.22)),
                          );
                        }),
                    ],
                  ),
                ),
                AnimatedBuilder(
                  animation: hold,
                  builder: (_, __) => SizedBox(
                    width: size + 26,
                    height: size + 26,
                    child: CircularProgressIndicator(
                        value: hold.value,
                        strokeWidth: 8,
                        strokeCap: StrokeCap.round,
                        color: C.sosDark,
                        backgroundColor: C.sos.withValues(alpha: 0.15)),
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'Start emergency call countdown',
                  onTap: () =>
                      unawaited(_beginEmergencyCall('sos_accessibility')),
                  child: GestureDetector(
                    onTapDown: (_) {
                      HapticFeedback.mediumImpact();
                      hold.forward();
                    },
                    onTapUp: (_) => release(),
                    onTapCancel: release,
                    child: AnimatedBuilder(
                      animation: hold,
                      builder: (_, child) => Transform.scale(
                          scale: 1 - hold.value * 0.06, child: child),
                      child: Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFFFF7A7A), C.sos, C.sosDark]),
                          boxShadow: [
                            BoxShadow(
                                color: C.sos.withValues(alpha: 0.5),
                                blurRadius: 40,
                                offset: const Offset(0, 16))
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.sos_rounded,
                                color: Colors.white70, size: compact ? 28 : 34),
                            Text('SOS',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: compact ? 40 : 52,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 2)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
            AnimatedBuilder(
              animation: hold,
              builder: (_, __) => Text(
                hold.value > 0
                    ? 'Keep holding… ${(2 - hold.value * 2).ceil()}s'
                    : 'Press and hold for 2 seconds',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: hold.value > 0
                        ? C.sosDark
                        : C.dark.withValues(alpha: 0.7)),
              ),
            ),
            const SizedBox(height: 4),
            Text('Location is requested only when emergency help is needed',
                style: TextStyle(
                    fontSize: 13, color: C.dark.withValues(alpha: 0.5))),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: OutlinedButton.icon(
                onPressed: _openHelp,
                icon: const Icon(Icons.support_agent_rounded),
                label: const Text('Emergency Help Directory'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: C.navy,
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            SizedBox(height: compact ? 22 : 110),
          ]),
        ),
      ),
    );
  }
}
