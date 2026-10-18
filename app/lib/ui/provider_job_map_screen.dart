import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/job.dart';
import '../services/firestore_service.dart';

class ProviderJobMapScreen extends StatefulWidget {
  final String jobId;

  const ProviderJobMapScreen({super.key, required this.jobId});

  @override
  State<ProviderJobMapScreen> createState() => _ProviderJobMapScreenState();
}

class _ProviderJobMapScreenState extends State<ProviderJobMapScreen> {
  final _mapController = MapController();
  bool _mapReady = false;
  bool _followClient = true;

  void _followLocation(LatLng point) {
    if (!_mapReady || !_followClient) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _mapReady && _followClient) {
        _mapController.move(point, _mapController.camera.zoom);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final firestore = FirestoreService();
    return Scaffold(
      appBar: AppBar(title: const Text('Client location')),
      body: StreamBuilder<Job?>(
        stream: firestore.watchJob(widget.jobId),
        builder: (context, jobSnapshot) {
          if (jobSnapshot.hasError) {
            return _centerMessage('Could not load this rescue job.');
          }
          final job = jobSnapshot.data;
          if (job == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!job.locationSharingEnabled ||
              job.status == JobStatus.completed ||
              job.status == JobStatus.cancelled) {
            return _centerMessage(
              'Live location sharing is off or this rescue job has ended.',
            );
          }
          return StreamBuilder<Map<String, dynamic>?>(
            stream: firestore.watchJobLiveLocation(widget.jobId),
            builder: (context, locationSnapshot) {
              if (locationSnapshot.hasError) {
                return _centerMessage(
                  'Live location is unavailable. The client may have stopped sharing.',
                );
              }
              if (!locationSnapshot.hasData || locationSnapshot.data == null) {
                return _centerMessage('Waiting for the client GPS update…');
              }
              final location = locationSnapshot.data!;
              final latitude = (location['latitude'] as num?)?.toDouble();
              final longitude = (location['longitude'] as num?)?.toDouble();
              if (latitude == null ||
                  longitude == null ||
                  !latitude.isFinite ||
                  !longitude.isFinite ||
                  latitude < -90 ||
                  latitude > 90 ||
                  longitude < -180 ||
                  longitude > 180) {
                return _centerMessage('The latest client location is invalid.');
              }
              final point = LatLng(latitude, longitude);
              _followLocation(point);
              final accuracy = (location['accuracy'] as num?)?.toDouble() ?? 0;
              final updatedAt = _updatedAt(location['updatedAt']);
              final isStale = updatedAt == null ||
                  DateTime.now().difference(updatedAt) >
                      const Duration(seconds: 30);
              return Column(
                children: [
                  Expanded(
                    child: FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: point,
                        initialZoom: 15,
                        onMapReady: () {
                          if (mounted) setState(() => _mapReady = true);
                        },
                        onPositionChanged: (_, hasGesture) {
                          if (hasGesture && _followClient) {
                            setState(() => _followClient = false);
                          }
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.roadrescue',
                          maxZoom: 19,
                        ),
                        CircleLayer(
                          circles: [
                            CircleMarker(
                              point: point,
                              radius: accuracy.clamp(8.0, 100.0).toDouble(),
                              useRadiusInMeter: true,
                              color: Colors.blue.withValues(alpha: 0.12),
                              borderColor: Colors.blue.withValues(alpha: 0.45),
                              borderStrokeWidth: 1.5,
                            ),
                          ],
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: point,
                              width: 52,
                              height: 52,
                              child: const Icon(
                                Icons.person_pin_circle_rounded,
                                color: Color(0xFFB00020),
                                size: 48,
                              ),
                            ),
                          ],
                        ),
                        RichAttributionWidget(
                          attributions: [
                            TextSourceAttribution(
                              '© OpenStreetMap contributors',
                              onTap: () => launchUrl(
                                Uri.parse(
                                    'https://openstreetmap.org/copyright'),
                              ),
                            ),
                          ],
                        ),
                        Positioned(
                          top: 12,
                          right: 12,
                          child: FloatingActionButton.small(
                            tooltip: 'Follow client location',
                            onPressed: _mapReady
                                ? () {
                                    setState(() => _followClient = true);
                                    _mapController.move(
                                      point,
                                      _mapController.camera.zoom,
                                    );
                                  }
                                : null,
                            child: Icon(
                              _followClient
                                  ? Icons.gps_fixed_rounded
                                  : Icons.gps_not_fixed_rounded,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '${job.serviceType} · ${job.status.name}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            updatedAt == null
                                ? 'Waiting for location timestamp · ±${accuracy.round()} m'
                                : '${isStale ? 'Last update' : 'Updated'} '
                                    '${TimeOfDay.fromDateTime(updatedAt).format(context)} · '
                                    '±${accuracy.round()} m'
                                    '${isStale ? ' · GPS may be stale' : ''}',
                          ),
                          const SizedBox(height: 10),
                          if (job.status == JobStatus.matched)
                            FilledButton.icon(
                              onPressed: () => _updateStatus(
                                context,
                                firestore,
                                job.id,
                                JobStatus.enRoute,
                              ),
                              icon: const Icon(Icons.directions),
                              label: const Text('Start travelling'),
                            )
                          else if (job.status == JobStatus.enRoute)
                            FilledButton.icon(
                              onPressed: () => _updateStatus(
                                context,
                                firestore,
                                job.id,
                                JobStatus.completed,
                              ),
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text('Complete rescue job'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  static DateTime? _updatedAt(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static Widget _centerMessage(String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message, textAlign: TextAlign.center),
        ),
      );

  static Future<void> _updateStatus(
    BuildContext context,
    FirestoreService firestore,
    String jobId,
    JobStatus status,
  ) async {
    try {
      final currentUserId = await firestore.currentUserId();
      await firestore.updateJobStatus(
        jobId,
        status.name,
        mechanicId: currentUserId,
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update rescue job: $error')),
      );
    }
  }
}
