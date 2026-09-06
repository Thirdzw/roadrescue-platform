import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/job.dart';
import '../models/vehicle.dart';
import '../models/alert.dart';

/// Thin wrapper around Firestore collections.
/// Collections: users, jobs, vehicles, alerts
class FirestoreService {
  final _db = FirebaseFirestore.instance;

  // ---- Jobs (reactive rescue) ----

  Future<String> createJob(Job job) async {
    final ref = await _db.collection('jobs').add(job.toMap());
    return ref.id;
  }

  Stream<List<Job>> watchOpenJobs() {
    return _db
        .collection('jobs')
        .where('status', isEqualTo: 'requested')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Job.fromMap(d.id, d.data())).toList());
  }

  Future<void> updateJobStatus(String jobId, String status,
      {String? mechanicId}) {
    final data = <String, dynamic>{'status': status};
    if (mechanicId != null) data['mechanicId'] = mechanicId;
    return _db.collection('jobs').doc(jobId).update(data);
  }

  // ---- Vehicles (predictive maintenance) ----

  Future<void> updateVehicleHealth(
      String vehicleId, Map<String, dynamic> reading) {
    return _db
        .collection('vehicles')
        .doc(vehicleId)
        .update({'lastHealthReading': reading});
  }

  Stream<Vehicle?> watchVehicle(String vehicleId) {
    return _db.collection('vehicles').doc(vehicleId).snapshots().map(
        (doc) => doc.exists ? Vehicle.fromMap(doc.id, doc.data()!) : null);
  }

  // ---- Alerts (emergency response) ----

  Future<String> createAlert(EmergencyAlert alert) async {
    final ref = await _db.collection('alerts').add(alert.toMap());
    // A Cloud Function trigger (see backend/functions) picks this up
    // and pushes it to the police/ambulance dispatch screen.
    return ref.id;
  }
}
