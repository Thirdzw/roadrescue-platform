class MaintenanceSchedule {
  final double lastServiceOdometerKm;
  final DateTime lastServiceDate;
  final double distanceSinceServiceKm;
  final double serviceIntervalKm;
  final int serviceIntervalDays;

  const MaintenanceSchedule({
    required this.lastServiceOdometerKm,
    required this.lastServiceDate,
    required this.distanceSinceServiceKm,
    required this.serviceIntervalKm,
    required this.serviceIntervalDays,
  });

  double get estimatedOdometerKm =>
      lastServiceOdometerKm + distanceSinceServiceKm;
  double get nextServiceOdometerKm => lastServiceOdometerKm + serviceIntervalKm;
  DateTime get nextServiceDate =>
      lastServiceDate.add(Duration(days: serviceIntervalDays));
  double get remainingDistanceKm => nextServiceOdometerKm - estimatedOdometerKm;

  int remainingDays(DateTime now) => nextServiceDate.difference(now).inDays;

  bool isDueAt(DateTime now) =>
      estimatedOdometerKm >= nextServiceOdometerKm ||
      !now.isBefore(nextServiceDate);
}
