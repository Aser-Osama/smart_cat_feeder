/**
 * Smart Cat Feeder - Firebase Cloud Functions (v2)
 *
 * These functions handle:
 * 1. checkScheduledFeedings - Runs every minute via Cloud Scheduler
 * 2. onScheduleCreated - Sets up notifications when a schedule is created
 * 3. triggerManualFeed - HTTP callable function for IoT device integration
 * 4. triggerIoTFeed - NEW: Send feed command to IoT gateway via Firestore
 * 5. onCatDetected - NEW: Handle cat detection from IoT and send notification
 * 6. sendCatNotification - NEW: Send cat detection push notification
 */

const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onDocumentCreated, onDocumentUpdated} = require("firebase-functions/v2/firestore");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");

initializeApp();

const db = getFirestore();

// ============================================================================
// Scheduled Feeding Check (runs every minute)
// ============================================================================

/**
 * Cloud Scheduler Function - Runs every minute
 * Checks all users' schedules and triggers feedings when time matches
 */
exports.checkScheduledFeedings = onSchedule({
  schedule: "every 1 minutes",
  timeZone: "Africa/Cairo",
}, async (event) => {
  // Get current time in Cairo timezone (UTC+2)
  const now = new Date();
  const cairoTime = new Date(now.toLocaleString("en-US", {timeZone: "Africa/Cairo"}));
  const currentHour = cairoTime.getHours();
  const currentMinute = cairoTime.getMinutes();
  // Convert Sunday from 0 to 7 to match weekday format
  const currentDay = cairoTime.getDay() === 0 ? 7 : cairoTime.getDay();

  console.log(`⏰ Checking schedules at ${currentHour}:${String(currentMinute).padStart(2, "0")} Cairo time (day ${currentDay})`);

  try {
    // Get all users
    const usersSnapshot = await db.collection("users").get();

    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;

      // Get user's active schedules
      const schedulesSnapshot = await db
          .collection("users")
          .doc(userId)
          .collection("schedules")
          .where("isActive", "==", true)
          .get();

      for (const scheduleDoc of schedulesSnapshot.docs) {
        const schedule = scheduleDoc.data();
        const scheduleHour = schedule.timeHour;
        const scheduleMinute = schedule.timeMinute;
        const weekdays = schedule.weekdays || [1, 2, 3, 4, 5, 6, 7];

        // Debug: Log schedule being checked
        console.log(`📋 Checking schedule "${schedule.name}": ${scheduleHour}:${String(scheduleMinute).padStart(2, "0")} on days [${weekdays.join(",")}]`);

        // Check if current time matches schedule
        if (
          scheduleHour === currentHour &&
          scheduleMinute === currentMinute &&
          weekdays.includes(currentDay)
        ) {
          console.log(`🍽️ TIME MATCH! Triggering feeding for user ${userId}: ${schedule.name}`);
          await executeFeedingForUser(userId, schedule, scheduleDoc.id);
        }
      }
    }

    console.log("✅ Schedule check complete");
  } catch (error) {
    console.error("❌ Error checking schedules:", error);
    throw error;
  }
});

/**
 * Execute a feeding for a specific user
 * This now sends a command to the IoT gateway instead of just logging
 */
async function executeFeedingForUser(userId, schedule, scheduleId) {
  try {
    // Send command to IoT gateway via Firestore
    // The Orange Pi gateway listens to this and relays to ESP8266
    // IMPORTANT: Use add() to create unique documents - gateway listens for ADDED events
    await db
        .collection("users")
        .doc(userId)
        .collection("commands")
        .add({
          type: "feed",
          amount: parseFloat(schedule.amount) || 50.0,
          source: "scheduled",
          scheduleName: schedule.name,
          scheduleId: scheduleId,
          status: "pending",
          createdAt: FieldValue.serverTimestamp(),
        });

    console.log(`📤 IoT feed command sent for schedule: ${schedule.name}`);

    // NOTE: Feeding log will be created by the Orange Pi gateway when feeding completes
    // This ensures we only log successful feedings and have accurate timestamps

    // Update food level (decrease by ~5% per feeding)
    const feederStatusRef = db
        .collection("users")
        .doc(userId)
        .collection("feeder")
        .doc("status");

    const feederDoc = await feederStatusRef.get();
    if (feederDoc.exists) {
      const currentLevel = feederDoc.data().foodLevel || 100;
      const newLevel = Math.max(0, currentLevel - 5);
      await feederStatusRef.update({
        foodLevel: newLevel,
        lastUpdated: FieldValue.serverTimestamp(),
      });

      // Send low food alert if below 20%
      if (newLevel < 20 && newLevel > 0) {
        await sendLowFoodNotification(userId, newLevel);
      }
    }

    // Send push notification to user
    await sendFeedingNotification(userId, schedule);

    console.log(`✅ Feeding executed for ${schedule.name}`);
    return true;
  } catch (error) {
    console.error(`❌ Error executing feeding for user ${userId}:`, error);

    // Log failed command (not feeding - the command itself failed to send)
    await db
        .collection("users")
        .doc(userId)
        .collection("feeding_logs")
        .add({
          timestamp: FieldValue.serverTimestamp(),
          amount: parseFloat(schedule.amount) || 50.0,
          type: "scheduled",
          success: false,
          scheduleName: schedule.name,
          scheduleId: scheduleId,
          notes: `Command failed: ${error.message}`,
          source: "cloud_function",
        });

    return false;
  }
}

// ============================================================================
// Push Notifications
// ============================================================================

/**
 * Send push notification when feeding is completed
 */
async function sendFeedingNotification(userId, schedule) {
  try {
    // Get user's FCM tokens
    const tokensSnapshot = await db
        .collection("users")
        .doc(userId)
        .collection("fcm_tokens")
        .get();

    if (tokensSnapshot.empty) {
      console.log(`No FCM tokens found for user ${userId}`);
      return;
    }

    const tokens = tokensSnapshot.docs.map((doc) => doc.id);
    const messaging = getMessaging();

    const message = {
      notification: {
        title: "🍽️ Scheduled Feeding Complete!",
        body: `${schedule.name}: ${schedule.amount}g dispensed for your cat`,
      },
      data: {
        type: "scheduled_feeding",
        scheduleName: schedule.name,
        amount: String(schedule.amount),
        timestamp: new Date().toISOString(),
      },
      tokens: tokens,
    };

    const response = await messaging.sendEachForMulticast(message);
    console.log(`📱 Notifications sent: ${response.successCount} success, ${response.failureCount} failed`);

    // Clean up invalid tokens
    if (response.failureCount > 0) {
      const failedTokens = [];
      response.responses.forEach((resp, idx) => {
        if (!resp.success) {
          failedTokens.push(tokens[idx]);
        }
      });

      for (const token of failedTokens) {
        await db
            .collection("users")
            .doc(userId)
            .collection("fcm_tokens")
            .doc(token)
            .delete();
      }
    }
  } catch (error) {
    console.error("Error sending notification:", error);
  }
}

/**
 * Send low food level alert
 */
async function sendLowFoodNotification(userId, level) {
  try {
    const tokensSnapshot = await db
        .collection("users")
        .doc(userId)
        .collection("fcm_tokens")
        .get();

    if (tokensSnapshot.empty) return;

    const tokens = tokensSnapshot.docs.map((doc) => doc.id);
    const messaging = getMessaging();

    const message = {
      notification: {
        title: "⚠️ Low Food Alert!",
        body: `Food level is at ${level}%. Please refill the feeder soon.`,
      },
      data: {
        type: "low_food_alert",
        foodLevel: String(level),
      },
      tokens: tokens,
    };

    await messaging.sendEachForMulticast(message);
    console.log(`📱 Low food alert sent to user ${userId}`);
  } catch (error) {
    console.error("Error sending low food notification:", error);
  }
}

// ============================================================================
// Manual Feed Functions
// ============================================================================

/**
 * HTTP Callable function for manual feeding from app
 * This sends a command to the IoT gateway
 */
exports.triggerManualFeed = onCall(async (request) => {
  // Verify authentication
  if (!request.auth) {
    throw new HttpsError(
        "unauthenticated",
        "User must be authenticated to trigger feeding",
    );
  }

  const userId = request.auth.uid;
  const amount = parseFloat(request.data.amount) || 50.0;

  try {
    // Send command to IoT gateway via Firestore
    // The Orange Pi gateway listens to this collection
    // IMPORTANT: Use add() to create unique documents - gateway listens for ADDED events
    await db
        .collection("users")
        .doc(userId)
        .collection("commands")
        .add({
          type: "feed",
          amount: amount,
          source: "manual",
          status: "pending",
          createdAt: FieldValue.serverTimestamp(),
        });

    console.log(`📤 IoT feed command sent for user ${userId}: ${amount}g`);

    return {
      success: true,
      message: "Feed command sent to IoT gateway",
      amount: amount,
    };
  } catch (error) {
    console.error("Error triggering manual feed:", error);
    throw new HttpsError("internal", error.message);
  }
});

/**
 * Alternative: Direct Firestore write for IoT feed
 * App can write directly to commands collection, this handles the logging
 */
exports.onFeedCommandCreated = onDocumentCreated(
    "users/{userId}/commands/{commandId}",
    async (event) => {
      const command = event.data.data();
      const userId = event.params.userId;

      if (command.type !== "feed") return;

      console.log(`📥 Feed command received for user ${userId}`);

      // The gateway will handle the actual feeding
      // This function just logs and tracks the command

      // Optional: Send confirmation notification
      try {
        const tokensSnapshot = await db
            .collection("users")
            .doc(userId)
            .collection("fcm_tokens")
            .get();

        if (!tokensSnapshot.empty) {
          const tokens = tokensSnapshot.docs.map((doc) => doc.id);
          const messaging = getMessaging();

          await messaging.sendEachForMulticast({
            notification: {
              title: "🔄 Feeding in Progress",
              body: `Dispensing ${command.amount || 50}g of food...`,
            },
            data: {
              type: "feed_started",
              amount: String(command.amount || 50),
            },
            tokens: tokens,
          });
        }
      } catch (error) {
        console.error("Error sending feed started notification:", error);
      }
    },
);

// ============================================================================
// Cat Detection Notification
// ============================================================================

/**
 * Listen for cat detection status changes from IoT gateway
 * When cat is detected, send push notification
 */
exports.onCatDetected = onDocumentUpdated(
    "users/{userId}/feeder/status",
    async (event) => {
      const beforeData = event.data.before.data();
      const afterData = event.data.after.data();
      const userId = event.params.userId;

      // Check if cat detection changed from false to true
      const wasCatDetected = beforeData.catDetected || false;
      const isCatDetected = afterData.catDetected || false;

      if (!wasCatDetected && isCatDetected) {
        console.log(`🐱 Cat detected for user ${userId}!`);

        try {
          const tokensSnapshot = await db
              .collection("users")
              .doc(userId)
              .collection("fcm_tokens")
              .get();

          if (!tokensSnapshot.empty) {
            const tokens = tokensSnapshot.docs.map((doc) => doc.id);
            const messaging = getMessaging();

            await messaging.sendEachForMulticast({
              notification: {
                title: "🐱 Cat Detected!",
                body: "Your cat is at the feeder. Tap to view camera.",
              },
              data: {
                type: "cat_detected",
                timestamp: new Date().toISOString(),
              },
              tokens: tokens,
            });

            console.log(`📱 Cat detection notification sent to user ${userId}`);
          }
        } catch (error) {
          console.error("Error sending cat detection notification:", error);
        }
      }
    },
);

// ============================================================================
// Schedule Management
// ============================================================================

/**
 * Firestore trigger - When a new schedule is created
 * Useful for validation or sending confirmation
 */
exports.onScheduleCreated = onDocumentCreated(
    "users/{userId}/schedules/{scheduleId}",
    async (event) => {
      const schedule = event.data.data();
      const userId = event.params.userId;

      console.log(`📅 New schedule created for user ${userId}: ${schedule.name}`);

      // Send confirmation notification
      try {
        const tokensSnapshot = await db
            .collection("users")
            .doc(userId)
            .collection("fcm_tokens")
            .get();

        if (!tokensSnapshot.empty) {
          const tokens = tokensSnapshot.docs.map((doc) => doc.id);
          const messaging = getMessaging();

          const hour = schedule.timeHour;
          const minute = String(schedule.timeMinute).padStart(2, "0");
          const period = hour >= 12 ? "PM" : "AM";
          const displayHour = hour > 12 ? hour - 12 : (hour === 0 ? 12 : hour);

          await messaging.sendEachForMulticast({
            notification: {
              title: "📅 Schedule Created!",
              body: `"${schedule.name}" set for ${displayHour}:${minute} ${period}`,
            },
            data: {
              type: "schedule_created",
              scheduleName: schedule.name,
            },
            tokens: tokens,
          });
        }
      } catch (error) {
        console.error("Error sending schedule confirmation:", error);
      }
    },
);

// ============================================================================
// IoT Gateway Status (Optional)
// ============================================================================

/**
 * HTTP endpoint for IoT gateway to report status
 * Can be called by Orange Pi to confirm it's online
 */
exports.gatewayHeartbeat = onCall(async (request) => {
  // This could be called by the gateway to confirm it's connected
  // For security, you might want to use a service account or API key

  const gatewayId = request.data.gatewayId || "unknown";
  const status = request.data.status || {};

  console.log(`💓 Gateway heartbeat from ${gatewayId}:`, status);

  // Optionally store gateway status
  await db.collection("gateways").doc(gatewayId).set({
    lastHeartbeat: FieldValue.serverTimestamp(),
    status: status,
  }, {merge: true});

  return {success: true, timestamp: new Date().toISOString()};
});
