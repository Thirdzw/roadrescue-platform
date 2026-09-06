const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();
const db = getFirestore();

/**
 * Reactive rescue: when a new job is created, find nearby vetted mechanics
 * and notify them so they can accept it.
 *
 * TODO(backend-track): replace the naive "all verified mechanics" query
 * with a real proximity query (e.g. geohash-based) once you have enough
 * mechanic location data to make that meaningful.
 */
exports.onJobCreated = onDocumentCreated("jobs/{jobId}", async (event) => {
  const job = event.data.data();

  const mechanicsSnap = await db
    .collection("users")
    .where("role", "==", "mechanic")
    .where("verified", "==", true)
    .get();

  const tokens = mechanicsSnap.docs
    .map((doc) => doc.data().fcmToken)
    .filter(Boolean);

  if (tokens.length === 0) return;

  await getMessaging().sendEachForMulticast({
    tokens,
    notification: {
      title: "New rescue request nearby",
      body: "A motorist needs help. Open the app to accept.",
    },
    data: { jobId: event.params.jobId },
  });
});

/**
 * Emergency response: when a new alert is created, immediately push it to
 * the mock police/ambulance dispatch screen and mark it dispatched.
 *
 * Objective #6 in the tracker: get this under 60 seconds, 95%+ reliability.
 */
exports.onAlertCreated = onDocumentCreated("alerts/{alertId}", async (event) => {
  const alertRef = event.data.ref;

  // TODO(emergency-track): replace with a real call/webhook to whatever
  // system represents "nearest police station and ambulance" in your demo.
  console.log("Dispatching alert", event.params.alertId, event.data.data());

  await alertRef.update({ dispatched: true });
});

/**
 * Predictive maintenance: when a vehicle's health reading is updated,
 * check thresholds and flag a fault before it strands the driver.
 *
 * TODO(iot-track): move real threshold logic here from the client so it's
 * consistent across app versions (task tracker #13).
 */
exports.onVehicleHealthUpdated = onDocumentUpdated(
  "vehicles/{vehicleId}",
  async (event) => {
    const after = event.data.after.data();
    const reading = after.lastHealthReading || {};

    const isAbnormal = reading.engineTemp && reading.engineTemp > 110;
    if (!isAbnormal) return;

    console.log(
      `Vehicle ${event.params.vehicleId} flagged: engineTemp=${reading.engineTemp}`
    );
    // TODO: push a notification to the owner (see onJobCreated for the pattern).
  }
);
