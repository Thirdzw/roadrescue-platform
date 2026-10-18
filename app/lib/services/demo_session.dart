import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../models/alert.dart';
import '../models/contact.dart';
import '../models/emergency_contact.dart';
import '../models/job.dart';
import '../models/vehicle.dart';

class DemoSession {
  DemoSession._();

  static final instance = DemoSession._();

  static const motoristId = 'demo-motorist-001';
  static const providerId = 'demo-provider-001';
  static const locationLatitude = -17.8252;
  static const locationLongitude = 31.0335;

  final _jobsController = StreamController<void>.broadcast();
  final _contactsController = StreamController<void>.broadcast();
  bool isActive = false;
  bool isProvider = false;
  int _nextId = 1;
  final List<Job> _jobs = [];
  final List<EmergencyContact> _contacts = [];
  final Map<String, Map<String, dynamic>> _liveLocations = {};
  final List<EmergencyAlert> alerts = [];
  Map<String, dynamic> profile = {};
  Vehicle? vehicle;

  String get currentUserId => isProvider ? providerId : motoristId;

  void start({required bool provider}) {
    isActive = true;
    isProvider = provider;
    _nextId = 1;
    _jobs
      ..clear()
      ..add(
        Job(
          id: 'demo-job-001',
          motoristId: motoristId,
          latitude: locationLatitude,
          longitude: locationLongitude,
          status: JobStatus.requested,
          createdAt: DateTime.now().toUtc(),
          notes: 'Sample client request · Flat tyre',
          serviceType: 'Tyre change',
          locationSharingEnabled: true,
        ),
      );
    _contacts
      ..clear()
      ..addAll(const [
        EmergencyContact(
          id: 'demo-contact-001',
          name: 'Tariro Moyo',
          phone: '+263771234567',
          relationship: 'Family',
        ),
        EmergencyContact(
          id: 'demo-contact-002',
          name: 'RoadRescue Circle',
          phone: '+263772345678',
          type: ContactType.circleMember,
          userId: 'demo-circle-001',
          relationship: 'Circle member',
        ),
      ]);
    _liveLocations
      ..clear()
      ..['demo-job-001'] = _locationData();
    alerts.clear();
    profile = {
      'name': isProvider ? 'Demo Provider' : 'Demo Motorist',
      'phone': '+263771234567',
      'nationalId': 'DEMO-ID-001',
      'bloodType': 'O+',
      'termsAcceptedAt': DateTime.now().toUtc().toIso8601String(),
      'termsVersion': 'demo',
    };
    vehicle = const Vehicle(
      id: motoristId,
      ownerId: motoristId,
      make: 'Toyota',
      model: 'Corolla',
      plateNumber: 'DEMO 123',
    );
    _notifyJobs();
    _notifyContacts();
  }

  void end() {
    isActive = false;
    isProvider = false;
    _jobs.clear();
    _contacts.clear();
    _liveLocations.clear();
    alerts.clear();
    profile = {};
    vehicle = null;
    _notifyJobs();
    _notifyContacts();
  }

  void setProviderMode(bool value) {
    isProvider = value;
  }

  Stream<List<Job>> watchOpenJobs() => _watchJobs(
        (job) =>
            job.status == JobStatus.requested && job.locationSharingEnabled,
      );

  Stream<List<Job>> watchMyJobs() => _watchJobs(
        (job) => job.motoristId == motoristId,
      );

  Stream<List<Job>> watchProviderJobs() => _watchJobs(
        (job) =>
            job.mechanicId == providerId &&
            (job.status == JobStatus.matched ||
                job.status == JobStatus.enRoute),
      );

  Stream<List<Job>> _watchJobs(bool Function(Job) matches) async* {
    List<Job> matchingJobs() => _jobs.where(matches).toList(growable: false);
    yield matchingJobs();
    yield* _jobsController.stream.map((_) => matchingJobs());
  }

  Stream<List<EmergencyContact>> watchEmergencyContacts() async* {
    List<EmergencyContact> current() => List.unmodifiable(_contacts);
    yield current();
    yield* _contactsController.stream.map((_) => current());
  }

  void addEmergencyContact({
    required String name,
    required String relationship,
    required String phone,
    required ContactType type,
    String? userId,
  }) {
    _contacts.add(
      EmergencyContact(
        id: 'demo-contact-${_nextId++}',
        name: name.trim(),
        relationship: relationship.trim(),
        phone: phone.trim(),
        type: type,
        userId: userId,
      ),
    );
    _notifyContacts();
  }

  Future<Job> createRescueRequest({
    required String serviceType,
    required Position position,
    String? notes,
  }) async {
    final id = 'demo-job-${_nextId++}';
    final job = Job(
      id: id,
      motoristId: motoristId,
      latitude: position.latitude,
      longitude: position.longitude,
      status: JobStatus.requested,
      createdAt: DateTime.now().toUtc(),
      notes: notes,
      serviceType: serviceType,
      locationSharingEnabled: true,
    );
    _jobs.add(job);
    _liveLocations[id] = _locationData(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
    );
    _notifyJobs();
    return job;
  }

  String createJob(Job job) {
    final id = 'demo-job-${_nextId++}';
    _jobs.add(
      Job(
        id: id,
        motoristId: job.motoristId,
        mechanicId: job.mechanicId,
        latitude: job.latitude,
        longitude: job.longitude,
        status: job.status,
        createdAt: job.createdAt,
        notes: job.notes,
        serviceType: job.serviceType,
        locationSharingEnabled: job.locationSharingEnabled,
      ),
    );
    _notifyJobs();
    return id;
  }

  Stream<Job?> watchJob(String id) => _watchJobs(
        (job) => job.id == id,
      ).map((jobs) => jobs.isEmpty ? null : jobs.first);

  Stream<Map<String, dynamic>?> watchJobLiveLocation(String id) =>
      _jobsController.stream
          .map((_) => _liveLocations[id])
          .startWith(_liveLocations[id]);

  void updateJobLiveLocation({
    required String jobId,
    required Position position,
  }) {
    _liveLocations[jobId] = _locationData(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
    );
    _notifyJobs();
  }

  void updateJobLocationSharing({
    required String jobId,
    required bool enabled,
  }) {
    final index = _jobs.indexWhere((job) => job.id == jobId);
    if (index < 0) return;
    final job = _jobs[index];
    _jobs[index] = _copyJob(job, locationSharingEnabled: enabled);
    if (enabled) {
      _liveLocations[jobId] ??= _locationData(
        latitude: job.latitude,
        longitude: job.longitude,
      );
    } else {
      _liveLocations.remove(jobId);
    }
    _notifyJobs();
  }

  void updateJobStatus(
    String jobId,
    String status, {
    String? mechanicId,
  }) {
    final index = _jobs.indexWhere((job) => job.id == jobId);
    if (index < 0) return;
    final job = _jobs[index];
    final nextStatus = JobStatus.values.firstWhere(
      (value) => value.name == status,
      orElse: () => job.status,
    );
    final ended =
        nextStatus == JobStatus.cancelled || nextStatus == JobStatus.completed;
    _jobs[index] = _copyJob(
      job,
      status: nextStatus,
      mechanicId: mechanicId ?? job.mechanicId,
      locationSharingEnabled: ended ? false : job.locationSharingEnabled,
    );
    if (ended) _liveLocations.remove(jobId);
    _notifyJobs();
  }

  void recordAlert(EmergencyAlert alert) {
    alerts.add(alert);
  }

  Map<String, dynamic>? jobLiveLocation(String jobId) => _liveLocations[jobId];

  List<Job> get jobs => List.unmodifiable(_jobs);
  List<EmergencyContact> get contacts => List.unmodifiable(_contacts);

  Job _copyJob(
    Job job, {
    JobStatus? status,
    String? mechanicId,
    bool? locationSharingEnabled,
  }) =>
      Job(
        id: job.id,
        motoristId: job.motoristId,
        mechanicId: mechanicId,
        latitude: job.latitude,
        longitude: job.longitude,
        status: status ?? job.status,
        createdAt: job.createdAt,
        notes: job.notes,
        serviceType: job.serviceType,
        locationSharingEnabled:
            locationSharingEnabled ?? job.locationSharingEnabled,
      );

  Map<String, dynamic> _locationData({
    double latitude = locationLatitude,
    double longitude = locationLongitude,
    double accuracy = 20,
  }) =>
      {
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'updatedAt': DateTime.now(),
      };

  void _notifyJobs() => _jobsController.add(null);
  void _notifyContacts() => _contactsController.add(null);
}

extension<T> on Stream<T> {
  Stream<T> startWith(T value) async* {
    yield value;
    yield* this;
  }
}
