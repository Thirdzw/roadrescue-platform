# RoadRescue

## Phone-only crash detection

Automatic crash detection is opt-in under **Emergency settings** and uses only
phone sensors: GPS speed, accelerometer impact/free-fall/stillness, gyroscope,
and (when present) barometer. A foreground service owns sensor tracking,
verification, alert countdowns, alarms, and emergency dispatch; the screen only
shows the service's current countdown and sends an "I'm OK" cancellation.

The microphone impact cue is optional under **Emergency settings**. It requires
microphone permission, analyzes audio levels on-device only while the app is in
the foreground, and does not save or transmit audio. The gyroscope and
barometer can continue as supplemental signals in the background service.
Barometer readings vary with device handling, weather, and altitude; they are
not a reliable airbag sensor.

An impact candidate requires a >4 g spike, at least 25 mph within the prior 10
seconds, and no <0.4 g free-fall sample in the preceding 600 ms. The service
checks evidence after 3 seconds and again up to 12 seconds. Impact is required
for every action. Evidence points are impact +2, speed below 5 mph +3,
stillness +1, and a gyroscope spike, pressure change, or loud-sound cue +1
each. Scores of 3-4 show a non-escalating check notification; 5-6 start a
30-second response countdown; scores of 7+ or severe events scoring 5+ start a
10-second countdown. Severity uses peak g-force and speed loss. These are
starting thresholds, not validated crash classifications; collect real-drive
logs and tune for potholes, braking, and dropped phones before relying on them.
Tunable values are named in `lib/logic/crash_fusion.dart` and
`lib/models/emergency_config.dart`.

The alarm player uses Android's alarm audio usage and loops a generated tone,
with repeated vibration. This does not override a muted alarm-volume setting,
all Do Not Disturb modes, manufacturer battery restrictions, or Android's
full-screen-intent policy. If full-screen access is unavailable, the countdown
still runs in the foreground service and the user receives a normal
notification instead. Review alarm volume and battery/autostart settings for
the phone brand. The opted-in service is configured to restart after device
reboot and app replacement, subject to Android and manufacturer restrictions.

Add emergency contacts and Circle members under **Safety**. SMS goes to all
saved contacts. To receive in-app push alerts, Circle members must enter each
other's RoadRescue user IDs; the backend checks for that mutual link and sends
high-priority Firebase Cloud Messaging notifications through
`backend/functions/index.js`. Deploy the Firebase Functions and Firestore rules
from `../backend/functions/` and `../backend/firestore.rules` before enabling
push alerts.

## Provider live client map

Motorists can request roadside help from **Mechanics**. Sending a request
requires an explicit location-sharing confirmation. Verified providers can
see the request location while it is waiting to be accepted; after acceptance,
only that assigned provider can read live GPS updates. The request feed is
currently global rather than proximity-filtered. The motorist can pause
sharing or cancel the request at any time; completing or cancelling a job
disables sharing, removes its latest stored GPS fix, and removes the request
coordinates from the job record. On Android, active sharing uses a visible
location foreground-service notification and continues while the app is
backgrounded where the OS allows it.

Providers can open **Provider mode → Open live provider workspace**. Accepting
a request assigns it to that provider; accepted jobs appear under **Clients you
are helping** and open on an OpenStreetMap-based map. Mark the job complete to
end sharing. Provider registration and approval screens are still prototype
UI: a trusted administrator must set the Firebase user profile's `role` to
`mechanic` and `verified` to `true`. Firestore rules enforce this before
providers can read or accept requests; do not let clients set their own
verified role.

Deploy the rules and composite indexes from the backend directory before
testing:

```text
firebase deploy --only firestore:rules,firestore:indexes
```

The map uses OpenStreetMap's public tile service and includes attribution.
That service has a usage policy and is not intended as an unrestricted
production tile backend; use a contracted tile provider for production-scale
traffic. Live locations require internet access and a usable GPS fix.

## Debug crash-alert testing

Debug builds include **Emergency settings → DEBUG TESTING ONLY**. Test mode is
persisted for the foreground-service isolate; simulated alerts are restricted
to contacts entered on that device and stored in local debug preferences. No
tester phone numbers are embedded in source. Add a phone number for SMS; a
Circle test contact also needs a real RoadRescue user ID and a mutual Circle
link to receive an FCM push.

Enable crash monitoring and grant the requested permissions first. In debug
test mode, use **Simulate crash (TEST)** to bypass sensors and run the short
countdown and dispatch path. Test SMS is sent directly through Android's SMS
permission/SIM and is prefixed `TEST -`; carrier charges may apply. The
foreground service submits a test-marked crash document to Firebase so the
deployed function can send a test-marked Circle push. Disable SMS permission
to verify that SMS can be skipped while the Firebase path is still attempted.
After dispatch completes, **FALSE ALARM (TEST)** sends a local follow-up SMS to
the configured test numbers. It does not create a backend all-clear event.

The current backend supports Circle FCM push only. It does **not** integrate a
provider for backend SMS or voice calls, so provider-only SMS/voice tests are
not supported. Android's SMS send callback reports send status, not confirmed
carrier delivery; the current telephony plugin does not expose the carrier's
send result code for asynchronous failures, and delivery reports may be
unavailable. Immediate platform exceptions are logged and do not stop sends
to other contacts. A Firestore submission likewise does not prove that a push
reached or was seen by a recipient. Keep physical-device test results separate
from logs and Firestore records, and do not run an alert test without informing
the recipients.

Record manual results in a test log with columns such as:
`Test | Date | Phone | Network | Contact | SMS time | Push received | Link OK | Notes`.
Include failed numbers, permission/network conditions, observed delays, and
provider cost where applicable. Manual device/network tests have not been
performed as part of this implementation.

## GPS trip processing

Trip location fixes pass through a shared 50 m accuracy and impossible-jump
filter, then a simple accuracy-weighted Kalman smoother. The trip/map stream
uses the smoothed coordinates; maintenance mileage sums accepted filtered
positions. Crash arming and speed-collapse checks use the original
`Position.speed` Doppler reading, not speed calculated from smoothed points.

While a user-started trip is being tracked, raw GPS speed drives a conservative
motion heuristic: sustained speed above 10 mph enters driving after 10 seconds,
sustained 1-5 mph enters walking after 30 seconds, and speed below 2 mph for
two minutes ends the driving state. Sampling adapts between best-navigation
driving, high-accuracy walking, and low-power stationary settings. This uses
GPS speed only; Android Activity Recognition and step-pattern detection are
not currently integrated, so stationary-to-moving transitions can be delayed
by the lower-power sampling interval.

The emergency foreground monitor intentionally keeps its GPS stream at
best-navigation accuracy with one-second updates while enabled. It does not
reuse the trip sampler's low-power intervals, because delayed speed fixes can
miss the raw-speed collapse used by crash verification. This favors detection
latency over battery life during crash monitoring.

`shouldUploadLocation` captures the proposed 50 m / two-minute upload throttle,
with emergency uploads always immediate. The app currently has no routine
trip-location upload endpoint, so ordinary trip fixes remain on-device; only
the emergency alert path sends a location. Geofences, nearest-responder
ranking, road matching, dead reckoning, and path simplification are not yet
implemented.

Crash detection explains and requests foreground/background location, SMS, and
notification permissions when enabled. Full-screen alert access is requested
but optional; Android may require it to be enabled in system settings.
Microphone permission is requested only if its optional cue is enabled.

## Maintenance reminders

The Mechanic screen offers service reminders based on a mileage/date record
entered by the user and GPS distance accumulated during explicitly started
trips. GPS mileage is an estimate; these reminders are not vehicle diagnostics
or breakdown predictions. Use the vehicle manufacturer's maintenance schedule.

## Android emulator test checklist

1. Enable automatic crash detection and grant its explained permissions in the
   emulator. Confirm its persistent monitoring notification remains visible
   after turning the screen off.
2. In **Extended controls → Virtual sensors**, use the accelerometer controls
   to create an impact above 4 g. Test both a direct spike and a free-fall below
   0.4 g followed by a spike.
3. Use **Extended controls → Location → Routes/Playback** with a GPX route that
   moves above 25 mph (40 km/h), then comes to a stop. Test normal braking and
   a sudden stop separately.
4. Verify low scores are ignored or produce only a silent check, and that
   higher scores show the matching 10- or 30-second “Are you OK?” prompt.
   Press **I'M OK** and confirm the service cancels the countdown and alarm.
5. Ordinary debug crash alerts remain dry-run previews. The explicit debug
   test-mode simulation is the exception: it can send real, chargeable SMS to
   locally configured test numbers and submit a test alert to Firebase.

RoadRescue is a safety aid, not a guaranteed safety system. Sensors, Android
process management, battery/audio settings, connectivity, carrier delivery,
and recipient availability can all prevent or delay an alert.

## Existing accounts and mode demos

The welcome screen offers **Already have an account? Log in** for Firebase
email/password accounts. Successful login requires an existing RoadRescue
profile and current terms acceptance. Use **Sign out** from the navigation menu
to return to the welcome screen; active client location sharing is revoked
before the session ends.

The Motorist and Provider demo buttons open the regular app navigation in a
local simulation, not Firebase accounts. Demo contacts, requests, job status,
location sharing, maintenance reminders, crash settings, and provider workflows
use in-memory sample data shared between the two demo roles and are discarded
when the demo exits.
Location is simulated at a sample point in Harare. SOS countdowns and crash
alerts can be exercised, but no Firebase writes, device GPS/sensors, phone
calls, SMS, push alerts, or payouts are performed. The demo verification code
is displayed in the login screen and is for preview purposes only; it is not
production two-factor authentication.

To test real Firebase provider access, use test accounts and have an
administrator verify the provider's Firestore profile.
