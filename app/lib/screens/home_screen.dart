import 'package:flutter/material.dart';
import 'sos_screen.dart';
import 'vehicle_health_screen.dart';
import 'mechanic_dashboard_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RoadRescue')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Reactive rescue · Predictive maintenance · Emergency response',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            _NavCard(
              icon: Icons.sos,
              label: 'SOS — Request rescue',
              color: Colors.redAccent,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SosScreen())),
            ),
            const SizedBox(height: 12),
            _NavCard(
              icon: Icons.health_and_safety,
              label: 'Vehicle health',
              color: Colors.orange,
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const VehicleHealthScreen())),
            ),
            const SizedBox(height: 12),
            _NavCard(
              icon: Icons.build,
              label: 'Mechanic dashboard',
              color: Colors.blueGrey,
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const MechanicDashboardScreen())),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _NavCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color, size: 32),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
