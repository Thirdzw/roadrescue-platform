import 'package:flutter/material.dart';
import '../widgets/floating_nav_bar.dart';
import 'driving_voice_mode_sheet.dart';
import 'provider_mode_screen.dart';
import 'sos_screen.dart';
import 'home_screen.dart';
import 'mechanic_dashboard_screen.dart';
import '../services/demo_session.dart';

class MainNavigation extends StatefulWidget {
  final Future<void> Function()? onSignOut;
  final bool isDemo;
  final bool startInProviderMode;

  const MainNavigation({
    super.key,
    this.onSignOut,
    this.isDemo = false,
    this.startInProviderMode = false,
  });
  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _index = 0;
  bool _drawerOpen = false;

  @override
  void initState() {
    super.initState();
    if (widget.isDemo &&
        (widget.startInProviderMode || DemoSession.instance.isProvider)) {
      _index = 3;
    }
  }

  void _openProviderMode() {
    if (widget.isDemo) DemoSession.instance.setProviderMode(true);
    setState(() {
      _drawerOpen = false;
      _index = 3;
    });
  }

  void _returnToMotorist() {
    if (widget.isDemo) DemoSession.instance.setProviderMode(false);
    setState(() => _index = 0);
  }

  Future<void> _openDrivingVoiceMode() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DrivingVoiceModeSheet(
        onNavigate: _navigateFromVoice,
      ),
    );
  }

  void _navigateFromVoice(int destination) {
    setState(() => _index = destination);
    final confirmation = switch (destination) {
      0 => 'Emergency screen opened. Hold SOS to send an alert.',
      1 => 'Safety screen opened.',
      _ => 'Mechanics screen opened.',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 108),
        content: Text(confirmation),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Stack(children: [
        Positioned.fill(
          child: IndexedStack(
            index: _index,
            children: [
              SosScreen(
                onMenuTap: () => setState(() => _drawerOpen = true),
                onVoiceModeTap: _openDrivingVoiceMode,
              ),
              const HomeScreen(),
              const MechanicScreen(),
              ProviderModeScreen(
                onSwitchToMotorist: _returnToMotorist,
                isDemo: widget.isDemo,
              ),
            ],
          ),
        ),
        if (_drawerOpen)
          Positioned.fill(
            child: Row(children: [
              SizedBox(
                width: MediaQuery.sizeOf(context).width < 440
                    ? MediaQuery.sizeOf(context).width * 0.82
                    : 360,
                child: Material(
                  color: Colors.white,
                  elevation: 12,
                  child: SafeArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.car_crash_rounded,
                                  color: Color(0xFF4B5B94), size: 30),
                              const SizedBox(height: 12),
                              const Text('RoadRescue',
                                  style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF2E3A66))),
                              Text(
                                widget.isDemo &&
                                        DemoSession.instance.isProvider
                                    ? 'Provider demo mode'
                                    : 'Motorist mode',
                                style: const TextStyle(color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.swap_horiz_rounded),
                          title: const Text('Switch to Provider'),
                          subtitle:
                              const Text('Register or open provider mode'),
                          onTap: _openProviderMode,
                        ),
                        if (widget.onSignOut != null)
                          ListTile(
                            leading: const Icon(Icons.logout_rounded),
                            title: Text(widget.isDemo
                                ? 'Exit demo'
                                : 'Sign out'),
                            onTap: () async {
                              setState(() => _drawerOpen = false);
                              try {
                                await widget.onSignOut!();
                              } catch (error) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Could not safely sign out: $error',
                                    ),
                                  ),
                                );
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _drawerOpen = false),
                  child: const ColoredBox(color: Colors.black54),
                ),
              ),
            ]),
          ),
      ]),
      bottomNavigationBar: _index < 3
          ? FloatingNav(
              currentIndex: _index,
              onTap: (next) => setState(() => _index = next),
            )
          : null,
    );
  }
}
