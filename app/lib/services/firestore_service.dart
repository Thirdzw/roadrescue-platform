import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:geolocator/geolocator.dart';
import '../models/crash_evidence_score.dart';
import '../models/emergency_contact.dart';
import '../models/contact.dart';
import '../models/job.dart';
import '../models/vehicle.dart';
import '../models/alert.dart';
import 'demo_session.dart';

/// Thin wrapper around Firestore collections.
/// Collections: users, jobs, vehicles, alerts
class FirestoreService {
  DemoSession get _demo => DemoSession.instance;

  CollectionReference<Map<String, dynamic>> _emergencyContacts(String uid) =>
      _db.collection('users').doc(uid).collection('emergencyContacts');

  bool get _isAvailable {
    try {
      Firebase.app();
      return true;
    } catch (_) {
      return false;
    }
  }

  FirebaseFirestore get _db {
    if (!_isAvailable) {
      throw StateError('Firebase has not been initialized yet.');
    }
    return FirebaseFirestore.instance;
  }

  // ---- Jobs (reactive rescue) ----

  Future<String> createJob(Job job) async {
    if (_demo.isActive) return _demo.createJob(job);
    if (!_isAvailable) return '';
    final ref = await _db.collection('jobs').add(job.toMap());
    return ref.id;
  }

  Future<Job> createRescueRequest({
    required String serviceType,
    required Position position,
    String? notes,
  }) async {
    if (_demo.isActive) {
      return _demo.createRescueRequest(
        serviceType: serviceType,
        position: position,
        notes: notes,
      );
    }
    final motoristId = await currentUserId();
    final job = Job(
      id: '',
      motoristId: motoristId,
      latitude: position.latitude,
      longitude: position.longitude,
      status: JobStatus.requested,
      createdAt: DateTime.now().toUtc(),
      notes: notes,
      serviceType: serviceType,
      locationSharingEnabled: true,
    );
    final id = await createJob(job);
    if (id.isEmpty) {
      throw StateError('Could not create the rescue request.');
    }
    return Job(
      id: id,
      motoristId: job.motoristId,
      latitude: job.latitude,
      longitude: job.longitude,
      status: job.status,
      createdAt: job.createdAt,
      notes: job.notes,
      serviceType: job.serviceType,
      locationSharingEnabled: job.locationSharingEnabled,
    );
  }

  Stream<List<EmergencyContact>> watchEmergencyContacts() async* {
    if (_demo.isActive) {
      yield* _demo.watchEmergencyContacts();
      return;
    }
    if (!_isAvailable) {
      yield const [];
      return;
    }
    final user = FirebaseAuth.instance.currentUser ??
        (await FirebaseAuth.instance.signInAnonymously()).user;
    if (user == null) {
      yield const [];
      return;
    }
    yield* _emergencyContacts(user.uid).orderBy('createdAt').snapshots().map(
        (snapshot) => snapshot.docs
            .map((doc) => EmergencyContact.fromMap(doc.id, doc.data()))
            .toList());
  }

  Future<List<EmergencyContact>> loadEmergencyContacts() async {
    if (_demo.isActive) return _demo.contacts;
    if (!_isAvailable) {
      throw StateError('Firebase has not been initialized.');
    }
    final user = FirebaseAuth.instance.currentUser ??
        (await FirebaseAuth.instance.signInAnonymously()).user;
    if (user == null) throw StateError('Could not load emergency contacts.');
    final snapshot = await _emergencyContacts(user.uid).get();
    return snapshot.docs
        .map((doc) => EmergencyContact.fromMap(doc.id, doc.data()))
        .toList(growable: false);
  }

  Future<String> currentUserName() async {
    if (_demo.isActive) return _demo.profile['name'] as String;
    if (!_isAvailable) {
      throw StateError('Firebase has not been initialized.');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in before sending an alert.');
    final snapshot = await _db.collection('users').doc(user.uid).get();
    final name = snapshot.data()?['name'] as String?;
    if (name == null || name.trim().isEmpty) {
      throw StateError('Save your name before enabling crash alerts.');
    }
    return name.trim();
  }

  Future<Map<String, dynamic>> loadCurrentUserProfile() async {
    if (_demo.isActive) return Map<String, dynamic>.of(_demo.profile);
    if (!_isAvailable) {
      throw StateError('Firebase has not been initialized.');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in before loading your profile.');
    final snapshot = await _db.collection('users').doc(user.uid).get();
    final profile = snapshot.data();
    if (!snapshot.exists || profile == null) {
      throw StateError(
        'This account has no RoadRescue profile yet. Finish onboarding first.',
      );
    }
    return profile;
  }

  Future<String> currentUserId() async {
    if (_demo.isActive) return _demo.currentUserId;
    if (!_isAvailable) {
      throw StateError('Firebase has not been initialized.');
    }
    final user = FirebaseAuth.instance.currentUser ??
        (await FirebaseAuth.instance.signInAnonymously()).user;
    if (user == null) throw StateError('Could not load your RoadRescue ID.');
    return user.uid;
  }

  Future<void> saveCurrentUserFcmToken(String token) async {
    if (_demo.isActive) return;
    if (!_isAvailable) {
      throw StateError('Firebase has not been initialized.');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Sign in before registering push alerts.');
    }
    await _db.collection('users').doc(user.uid).update({
      'fcmToken': token,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addEmergencyContact({
    required String name,
    required String relationship,
    required String phone,
    ContactType type = ContactType.emergencyContact,
    String? userId,
  }) async {
    if (_demo.isActive) {
      _demo.addEmergencyContact(
        name: name,
        relationship: relationship,
        phone: phone,
        type: type,
        userId: userId,
      );
      return;
    }
    if (!_isAvailable) {
      throw StateError('Firebase has not been initialized.');
    }
    final user = FirebaseAuth.instance.currentUser ??
        (await FirebaseAuth.instance.signInAnonymously()).user;
    if (user == null) throw StateError('Could not authenticate this contact.');

    final contact = Contact(
      id: '',
      name: name,
      phone: phone,
      type: type,
      userId: userId,
      relationship: relationship,
    );
    await _emergencyContacts(user.uid).add({
      ...contact.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> createAutomaticCrashAlert({
    required List<String> recipientUserIds,
    required String message,
    required Position position,
    required CrashEvidenceScore evidenceScore,
    bool test = false,
  }) async {
    if (_demo.isActive) {
      _demo.recordAlert(
        EmergencyAlert(
          id: 'demo-alert-${DateTime.now().microsecondsSinceEpoch}',
          motoristId: _demo.currentUserId,
          vehicleId: DemoSession.motoristId,
          type: AlertType.crash,
          latitude: position.latitude,
          longitude: position.longitude,
          timestamp: DateTime.now().toUtc(),
        ),
      );
      return;
    }
    if (!_isAvailable) throw StateError('Firebase has not been initialized.');
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in before sending an alert.');
    await _db.collection('alerts').add({
      'motoristId': user.uid,
      'vehicleId': user.uid,
      'type': 'crash',
      'latitude': position.latitude,
      'longitude': position.longitude,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'dispatched': false,
      'recipientUserIds': recipientUserIds.toSet().toList(),
      'message': message,
      'crashEvidence': evidenceScore.toMap(),
      if (test) 'test': true,
    });
  }

  Stream<List<Job>> watchOpenJobs() {
    if (_demo.isActive) return _demo.watchOpenJobs();
    if (!_isAvailable) return const Stream.empty();
    return _db
        .collection('jobs')
        .where('status', isEqualTo: 'requested')
        .where('locationSharingEnabled', isEqualTo: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Job.fromMap(d.id, d.data())).toList());
  }

  Stream<List<Job>> watchMyJobs() async* {
    if (_demo.isActive) {
      yield* _demo.watchMyJobs();
      return;
    }
    if (!_isAvailable) {
      yield const [];
      return;
    }
    final motoristId = await currentUserId();
    yield* _db
        .collection('jobs')
        .where('motoristId', isEqualTo: motoristId)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((document) => Job.fromMap(document.id, document.data()))
            .toList(growable: false));
  }

  Stream<List<Job>> watchProviderJobs() async* {
    if (_demo.isActive) {
      yield* _demo.watchProviderJobs();
      return;
    }
    if (!_isAvailable) {
      yield const [];
      return;
    }
    final mechanicId = await currentUserId();
    yield* _db
        .collection('jobs')
        .where('mechanicId', isEqualTo: mechanicId)
        .where('status', whereIn: ['matched', 'enRoute'])
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((document) => Job.fromMap(document.id, document.data()))
            .toList(growable: false));
  }

  Stream<Job?> watchJob(String jobId) {
    if (_demo.isActive) return _demo.watchJob(jobId);
    if (!_isAvailable) return Stream.value(null);
    return _db.collection('jobs').doc(jobId).snapshots().map(
          (document) =>
              document.exists ? Job.fromMap(jobId, document.data()!) : null,
        );
  }

  Stream<Map<String, dynamic>?> watchJobLiveLocation(String jobId) {
    if (_demo.isActive) return _demo.watchJobLiveLocation(jobId);
    if (!_isAvailable) return Stream.value(null);
    return _db
        .collection('jobs')
        .doc(jobId)
        .collection('liveLocation')
        .doc('current')
        .snapshots()
        .map((document) => document.data());
  }

  Future<void> updateJobLiveLocation({
    required String jobId,
    required Position position,
  }) async {
    if (_demo.isActive) {
      _demo.updateJobLiveLocation(jobId: jobId, position: position);
      return;
    }
    if (!_isAvailable) throw StateError('Firebase is not initialized.');
    final job = _db.collection('jobs').doc(jobId);
    final batch = _db.batch();
    batch.set(job.collection('liveLocation').doc('current'), {
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracy': position.accuracy,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(job, {
      'latitude': FieldValue.delete(),
      'longitude': FieldValue.delete(),
    });
    await batch.commit();
  }

  Future<void> clearJobLiveLocation(String jobId) async {
    if (_demo.isActive) {
      _demo.updateJobLocationSharing(jobId: jobId, enabled: false);
      return;
    }
    if (!_isAvailable) throw StateError('Firebase is not initialized.');
    await _db
        .collection('jobs')
        .doc(jobId)
        .collection('liveLocation')
        .doc('current')
        .delete();
  }

  Future<void> stopCurrentUserLocationSharing() async {
    if (_demo.isActive) {
      for (final job in _demo.jobs.where(
        (job) =>
            job.motoristId == DemoSession.motoristId &&
            job.locationSharingEnabled,
      )) {
        _demo.updateJobLocationSharing(jobId: job.id, enabled: false);
      }
      return;
    }
    if (!_isAvailable) throw StateError('Firebase is not initialized.');
    final userId = await currentUserId();
    final jobs = await _db
        .collection('jobs')
        .where('motoristId', isEqualTo: userId)
        .where('locationSharingEnabled', isEqualTo: true)
        .get();
    if (jobs.docs.isEmpty) return;

    final batch = _db.batch();
    for (final job in jobs.docs) {
      batch.update(job.reference, {
        'locationSharingEnabled': false,
        'latitude': FieldValue.delete(),
        'longitude': FieldValue.delete(),
      });
      batch.delete(job.reference.collection('liveLocation').doc('current'));
    }
    await batch.commit();
  }

  Future<void> updateJobLocationSharing({
    required String jobId,
    required bool enabled,
  }) async {
    if (_demo.isActive) {
      _demo.updateJobLocationSharing(jobId: jobId, enabled: enabled);
      return;
    }
    if (!_isAvailable) throw StateError('Firebase is not initialized.');
    final data = <String, Object>{
      'locationSharingEnabled': enabled,
      if (!enabled) 'latitude': FieldValue.delete(),
      if (!enabled) 'longitude': FieldValue.delete(),
    };
    await _db.collection('jobs').doc(jobId).update(data);
    if (!enabled) await clearJobLiveLocation(jobId);
  }

  Future<void> updateJobStatus(String jobId, String status,
      {String? mechanicId}) async {
    if (_demo.isActive) {
      _demo.updateJobStatus(jobId, status, mechanicId: mechanicId);
      return;
    }
    if (!_isAvailable) return;
    final data = <String, dynamic>{'status': status};
    if (mechanicId != null) data['mechanicId'] = mechanicId;
    if (status == JobStatus.completed.name ||
        status == JobStatus.cancelled.name) {
      data['locationSharingEnabled'] = false;
      data['latitude'] = FieldValue.delete();
      data['longitude'] = FieldValue.delete();
    }
    await _db.collection('jobs').doc(jobId).update(data);
    if (status == JobStatus.completed.name ||
        status == JobStatus.cancelled.name) {
      await clearJobLiveLocation(jobId);
    }
  }

  // ---- Vehicles ----

  Future<void> saveOnboardingProfile({
    required String name,
    required String phone,
    required String nationalId,
    required String bloodType,
    required String vehicleMake,
    required String vehicleModel,
    required String vehicleRegistration,
    required bool acceptedHealthData,
    required String termsVersion,
  }) async {
    if (_demo.isActive) {
      _demo.profile = {
        'name': name,
        'phone': phone,
        'nationalId': nationalId,
        'bloodType': acceptedHealthData ? bloodType : 'Unknown',
        'termsAcceptedAt': DateTime.now().toUtc().toIso8601String(),
        'termsVersion': termsVersion,
      };
      _demo.vehicle = Vehicle(
        id: DemoSession.motoristId,
        ownerId: DemoSession.motoristId,
        make: vehicleMake,
        model: vehicleModel,
        plateNumber: vehicleRegistration,
      );
      return;
    }
    if (!_isAvailable) {
      throw StateError('Firebase has not been initialized.');
    }

    final auth = FirebaseAuth.instance;
    var user = auth.currentUser;
    if (user != null) {
      try {
        await user.reload();
      } on FirebaseAuthException catch (error) {
        if (!user.isAnonymous ||
            (error.code != 'user-not-found' &&
                error.code != 'invalid-user-token')) {
          rethrow;
        }
        await auth.signOut();
        user = null;
      }
    }
    user ??= (await auth.signInAnonymously()).user;
    if (user == null) throw StateError('Could not create your account.');

    final userRef = _db.collection('users').doc(user.uid);
    final vehicleRef = _db.collection('vehicles').doc(user.uid);
    final userSnapshot = await userRef.get();
    final vehicleSnapshot = await vehicleRef.get();
    if (vehicleSnapshot.exists &&
        vehicleSnapshot.data()?['ownerId'] != user.uid) {
      throw StateError('Your vehicle record is not owned by this account.');
    }

    final profile = <String, dynamic>{
      'name': name,
      'phone': phone,
      'nationalId': nationalId,
      'termsAcceptedAt': FieldValue.serverTimestamp(),
      'termsVersion': termsVersion,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (acceptedHealthData) {
      profile.addAll({
        'bloodType': bloodType,
        'healthDataConsentAt': FieldValue.serverTimestamp(),
        'healthDataConsentVersion': 'v1',
      });
    } else if (userSnapshot.exists) {
      profile.addAll({
        'bloodType': FieldValue.delete(),
        'healthDataConsentAt': FieldValue.delete(),
        'healthDataConsentVersion': FieldValue.delete(),
      });
    }
    if (!userSnapshot.exists) {
      profile.addAll({
        'role': 'motorist',
        'verified': false,
        'rating': null,
      });
    }

    final vehicle = <String, dynamic>{
      'ownerId': user.uid,
      'make': vehicleMake,
      'model': vehicleModel,
      'plateNumber': vehicleRegistration,
    };
    if (vehicleSnapshot.exists) {
      vehicle['updatedAt'] = FieldValue.serverTimestamp();
    } else {
      vehicle['createdAt'] = FieldValue.serverTimestamp();
    }

    final batch = _db.batch();
    batch.set(userRef, profile, SetOptions(merge: true));
    batch.set(vehicleRef, vehicle, SetOptions(merge: true));
    await batch.commit();
  }

  Stream<Vehicle?> watchVehicle(String vehicleId) {
    if (_demo.isActive) return Stream.value(_demo.vehicle);
    if (!_isAvailable) return const Stream.empty();
    return _db
        .collection('vehicles')
        .doc(vehicleId)
        .snapshots()
        .map((doc) => doc.exists ? Vehicle.fromMap(doc.id, doc.data()!) : null);
  }

  // ---- Alerts (emergency response) ----

  Future<String> createEmergencyAlert({
    required AlertType type,
    required Position location,
  }) async {
    if (_demo.isActive) {
      final alert = EmergencyAlert(
        id: 'demo-alert-${DateTime.now().microsecondsSinceEpoch}',
        motoristId: DemoSession.motoristId,
        vehicleId: DemoSession.motoristId,
        type: type,
        latitude: location.latitude,
        longitude: location.longitude,
        timestamp: DateTime.now().toUtc(),
      );
      _demo.recordAlert(alert);
      return alert.id;
    }
    if (!_isAvailable) {
      throw StateError('Firebase has not been initialized.');
    }

    final auth = FirebaseAuth.instance;
    final user = auth.currentUser ?? (await auth.signInAnonymously()).user;
    if (user == null) throw StateError('Could not authenticate this alert.');

    final userRef = _db.collection('users').doc(user.uid);
    final userSnapshot = await userRef.get();
    if (!userSnapshot.exists) {
      throw StateError('Save your profile before sending an alert.');
    }

    final vehicleRef = _db.collection('vehicles').doc(user.uid);
    final vehicleSnapshot = await vehicleRef.get();
    if (!vehicleSnapshot.exists) {
      throw StateError('Save your vehicle details before sending an alert.');
    } else if (vehicleSnapshot.data()?['ownerId'] != user.uid) {
      throw StateError('The registered vehicle is not owned by this account.');
    }

    return createAlert(
      EmergencyAlert(
        id: '',
        motoristId: user.uid,
        vehicleId: vehicleRef.id,
        type: type,
        latitude: location.latitude,
        longitude: location.longitude,
        timestamp: DateTime.now().toUtc(),
      ),
    );
  }

  Future<String> createAlert(EmergencyAlert alert) async {
    if (_demo.isActive) {
      _demo.recordAlert(alert);
      return alert.id.isEmpty
          ? 'demo-alert-${DateTime.now().microsecondsSinceEpoch}'
          : alert.id;
    }
    if (!_isAvailable) throw StateError('Firebase has not been initialized.');
    final ref = await _db.collection('alerts').add(alert.toMap());
    // The Cloud Function records dispatch status; external dispatch is not configured.
    return ref.id;
  }
}
