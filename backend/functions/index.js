const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { FieldValue, getFirestore } = require("firebase-admin/firestore");
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

  const tokenOwners = mechanicsSnap.docs
    .map((doc) => ({ userId: doc.id, token: doc.data().fcmToken }))
    .filter(({ token }) => typeof token === "string" && token.length > 0);
  const uniqueTokenOwners = [
    ...new Map(tokenOwners.map((owner) => [owner.token, owner])).values(),
  ];

  if (uniqueTokenOwners.length === 0) return;

  const messaging = getMessaging();
  for (let offset = 0; offset < uniqueTokenOwners.length; offset += 500) {
    const batch = uniqueTokenOwners.slice(offset, offset + 500);
    const result = await messaging.sendEachForMulticast({
      tokens: batch.map(({ token }) => token),
      notification: {
        title: "New rescue request nearby",
        body: "A motorist needs help. Open the app to accept.",
      },
      data: { jobId: event.params.jobId },
    });

    const staleUserIds = result.responses.flatMap((response, index) => {
      const errorCode = response.error?.code;
      if (
        response.success ||
        !["messaging/registration-token-not-registered", "messaging/invalid-registration-token"].includes(errorCode)
      ) {
        return [];
      }
      return [batch[index].userId];
    });

    await Promise.all(
      staleUserIds.map((userId) =>
        db.collection("users").doc(userId).update({
          fcmToken: FieldValue.delete(),
        })
      )
    );
  }
});

exports.onAlertCreated = onDocumentCreated("alerts/{alertId}", async (event) => {
  const alertRef = event.data.ref;
  const alert = event.data.data();
  const isTestAlert = alert.test === true;
  if (alert.type !== "crash") {
    await alertRef.update({
      dispatched: false,
      dispatchStatus: "integration_required",
    });
    console.warn("Emergency dispatch integration is not configured", {
      alertId: event.params.alertId,
    });
    return;
  }

  const recipientUserIds = Array.isArray(alert.recipientUserIds)
    ? [...new Set(
        alert.recipientUserIds.filter(
          (userId) =>
            typeof userId === "string" &&
            userId.length > 0 &&
            userId.length <= 128 &&
            userId !== alert.motoristId
        )
      )].slice(0, 100)
    : [];

  if (recipientUserIds.length === 0) {
    await alertRef.update({
      dispatched: false,
      dispatchStatus: "no_linked_circle_members",
    });
    console.warn("Crash alert has no linked Circle members", {
      alertId: event.params.alertId,
    });
    return;
  }

  const tokenOwners = [];
  for (const userId of recipientUserIds) {
    try {
      const reverseContacts = await db
        .collection("users")
        .doc(userId)
        .collection("emergencyContacts")
        .get();
      const hasMutualCircleLink = reverseContacts.docs.some((doc) => {
        const contact = doc.data();
        return (
          contact.type === "circleMember" &&
          contact.userId === alert.motoristId
        );
      });
      if (!hasMutualCircleLink) {
        console.warn("Crash push skipped without mutual Circle membership", {
          alertId: event.params.alertId,
          userId,
        });
        continue;
      }

      const user = await db.collection("users").doc(userId).get();
      const token = user.data()?.fcmToken;
      if (typeof token === "string" && token.length > 0) {
        tokenOwners.push({ userId, token });
      }
    } catch (error) {
      console.error("Could not load crash alert recipient", {
        alertId: event.params.alertId,
        userId,
        error,
      });
    }
  }

  const uniqueTokenOwners = [
    ...new Map(tokenOwners.map((owner) => [owner.token, owner])).values(),
  ];
  let successCount = 0;
  let failureCount = recipientUserIds.length - tokenOwners.length;
  const messaging = getMessaging();
  for (let offset = 0; offset < uniqueTokenOwners.length; offset += 500) {
    const batch = uniqueTokenOwners.slice(offset, offset + 500);
    try {
      const result = await messaging.sendEachForMulticast({
        tokens: batch.map(({ token }) => token),
        notification: {
          title: isTestAlert ? "TEST - Crash alert" : "Crash detected",
          body: isTestAlert && !String(alert.message || "").startsWith("TEST -")
            ? `TEST - ${alert.message || "A RoadRescue Circle member may need help."}`
            : alert.message || "A RoadRescue Circle member may need help.",
        },
        android: {
          priority: "high",
          notification: { channelId: "roadrescue_crash_alerts" },
        },
        data: {
          alertId: event.params.alertId,
          type: "crash",
          latitude: String(alert.latitude),
          longitude: String(alert.longitude),
        },
      });
      successCount += result.successCount;
      failureCount += result.failureCount;
      const staleUserIds = result.responses.flatMap((response, index) => {
        const errorCode = response.error?.code;
        if (
          response.success ||
          ![
            "messaging/registration-token-not-registered",
            "messaging/invalid-registration-token",
          ].includes(errorCode)
        ) {
          return [];
        }
        return [batch[index].userId];
      });
      for (const userId of staleUserIds) {
        try {
          await db.collection("users").doc(userId).update({
            fcmToken: FieldValue.delete(),
          });
        } catch (error) {
          console.error("Could not clear stale crash-alert token", {
            userId,
            error,
          });
        }
      }
    } catch (error) {
      failureCount += batch.length;
      console.error("Crash push batch failed", {
        alertId: event.params.alertId,
        error,
      });
    }
  }

  const dispatchStatus =
    successCount === 0
      ? "push_failed"
      : failureCount === 0
        ? "push_sent"
        : "push_partial";
  try {
    await alertRef.update({
      dispatched: false,
      dispatchStatus,
      pushSuccessCount: successCount,
      pushFailureCount: failureCount,
    });
  } catch (error) {
    console.error("Could not record crash push outcome", {
      alertId: event.params.alertId,
      error,
    });
  }
});
