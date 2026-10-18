import 'package:flutter/material.dart';

import '../widgets/common_widgets.dart';
import 'main_navigation.dart';

enum DemoAccountMode { motorist, provider }

class DemoAccountScreen extends StatelessWidget {
  final DemoAccountMode mode;
  final VoidCallback onExit;

  const DemoAccountScreen({
    super.key,
    required this.mode,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                color: const Color(0xFFFFF1DE),
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'DEMO SIMULATION · Sample data only; no real calls, GPS or account changes',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: C.dark,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: onExit,
                      child: const Text('Exit'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: MainNavigation(
                  isDemo: true,
                  startInProviderMode: mode == DemoAccountMode.provider,
                  onSignOut: () async => onExit(),
                ),
              ),
            ],
          ),
        ),
      );
}
