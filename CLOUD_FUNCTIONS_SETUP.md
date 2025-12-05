# Firebase Cloud Functions - Automated Scheduled Feedings

This document explains the Cloud Functions implementation that enables **automated scheduled feedings** even when the app is closed.

---

## 📖 Overview

### What It Does
The Cloud Functions system automates the scheduled feeding feature:

1. **Cloud Scheduler** triggers a function every minute
2. **Cloud Function** checks all users' schedules against current Cairo time
3. When a schedule matches, it:
   - Creates a feeding log entry in Firestore
   - Decreases the food level by 5%
   - Sends a push notification to the user
   - (Future) Sends command to IoT hardware

### Architecture
```
┌─────────────────┐     ┌──────────────────────┐     ┌─────────────────┐
│ Cloud Scheduler │────▶│   Cloud Function     │────▶│    Firestore    │
│  (every 1 min)  │     │ checkScheduled       │     │  feeding_logs   │
└─────────────────┘     │ Feedings             │     │    schedules    │
                        │ (Cairo timezone)     │     │   feeder/status │
                        └──────────┬───────────┘     └─────────────────┘
                                   │
                                   ▼
                        ┌──────────────────────┐
                        │   Push Notification  │
                        │   via FCM to user    │
                        └──────────────────────┘
```

---

## 🗂️ Files Structure

```
smart-cat-feeder-fns/
├── index.js          # Main Cloud Functions code (3 functions)
├── package.json      # Node.js dependencies
├── .eslintrc.js      # ESLint configuration
└── node_modules/     # Dependencies

firebase.json         # Firebase project configuration
firestore.rules       # Firestore security rules
firestore.indexes.json # Database indexes
```

---

## ⚙️ Functions Explained

### 1. `checkScheduledFeedings`
**Trigger:** Cloud Scheduler (every 1 minute)  
**Timezone:** Africa/Cairo

**What it does:**
1. Gets current Cairo time (hour, minute, day of week)
2. Queries all users from Firestore
3. For each user, gets their active schedules
4. Compares schedule time with current time
5. If match found: executes feeding

**Matching Logic:**
```javascript
if (scheduleHour === currentHour &&
    scheduleMinute === currentMinute &&
    weekdays.includes(currentDay))
```

### 2. `onScheduleCreated`
**Trigger:** Firestore document creation at `users/{userId}/schedules/{scheduleId}`

**What it does:**
- Sends a confirmation push notification when user creates a new schedule
- Example: "📅 Schedule Created! Morning Feeding set for 8:00 AM"

### 3. `triggerManualFeed`
**Trigger:** HTTP Callable (from app or IoT device)

**What it does:**
- Allows authenticated users to trigger feeding remotely
- Logs the feeding and updates food level
- Prepared for future IoT integration

---

## 📊 Data Flow

### When a Scheduled Feeding Triggers:

```
1. Cloud Scheduler invokes function at :00, :01, :02... every minute

2. Function converts UTC to Cairo time:
   const cairoTime = new Date(now.toLocaleString("en-US", {timeZone: "Africa/Cairo"}));

3. Queries Firestore:
   users/{userId}/schedules WHERE isActive == true

4. For matching schedule, creates:
   users/{userId}/feeding_logs/{logId}
   {
     timestamp: serverTimestamp(),
     amount: 50,
     type: "scheduled",
     success: true,
     scheduleName: "Morning Feeding"
   }

5. Updates:
   users/{userId}/feeder/status
   { foodLevel: currentLevel - 5 }

6. Sends FCM notification to:
   users/{userId}/fcm_tokens/{token}
```

---

## 🔔 Push Notifications

For notifications to work, the Flutter app must:
1. Request notification permissions
2. Save FCM token to `users/{userId}/fcm_tokens/{token}`

**This is already implemented in:**
- `lib/services/notification_service.dart` - FCM token management
- `lib/providers/auth_provider.dart` - Saves token on login, removes on logout

---

## 🌍 Timezone Handling

**Important:** Cloud Functions run on Google's servers in UTC timezone.

The scheduler timezone (`Africa/Cairo`) only determines *when* the function runs.
Inside the function, we must convert UTC to Cairo time:

```javascript
const cairoTime = new Date(now.toLocaleString("en-US", {timeZone: "Africa/Cairo"}));
const currentHour = cairoTime.getHours();  // Cairo hour, not UTC
```

---

## 💰 Cost & Free Tier

| Resource | Free Tier | Your Usage |
|----------|-----------|------------|
| Function Invocations | 2M/month | ~43K/month (1/min) |
| GB-seconds | 400K/month | Minimal |
| Firestore Reads | 50K/day | ~Few hundred |
| FCM Messages | Unlimited | Minimal |

**You will likely never be charged** with normal usage.

---

## 🔧 Deployment Commands

```bash
# Deploy functions
firebase deploy --only functions

# View logs
firebase functions:log --only checkScheduledFeedings

# View all logs
firebase functions:log

# Set cleanup policy (if warning appears)
firebase functions:artifacts:setpolicy --location us-central1
```

---

## ⚠️ Troubleshooting

### DEVELOPER_ERROR in Logs
```
W/GoogleApiManager: ConnectionResult{statusCode=DEVELOPER_ERROR}
```

**Cause:** SHA-1 fingerprint not added to Firebase

**Fix:**
1. Get your SHA-1:
   ```bash
   cd android && ./gradlew signingReport
   ```
2. Go to Firebase Console → Project Settings → Your Android App
3. Add the SHA-1 fingerprint (under "SHA certificate fingerprints")
4. Download the new `google-services.json`
5. Replace `android/app/google-services.json`
6. Rebuild the app

### Scheduled Feeding Not Triggering
1. Check timezone is `Africa/Cairo` in `index.js`
2. Verify schedule `isActive: true` in Firestore
3. Check the day of week matches (1=Mon, 7=Sun)
4. View logs: `firebase functions:log --only checkScheduledFeedings`

### No Push Notifications
1. Ensure SHA-1 fingerprint is added (fixes DEVELOPER_ERROR)
2. Check FCM token exists in `users/{userId}/fcm_tokens/`
3. Verify notification permissions granted on device

---

## ✅ Current Status

| Component | Status |
|-----------|--------|
| Firebase Project | ✅ smart-cat-feeder-18b9e |
| Firestore Database | ✅ Working |
| Cloud Functions | ✅ Deployed |
| Timezone | ✅ Africa/Cairo |
| Push Notifications | ✅ Ready (needs SHA-1 for FCM) |
| Cleanup Policy | ✅ Configured |

---

## Remaining Steps

### Step 1: Upgrade to Blaze Plan (if not already)

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your project
3. Click **Upgrade** in the bottom left
4. Select **Blaze (pay as you go)**
5. Add a billing account

> **Cost**: You likely won't pay anything. Free tier includes:
> - 2 million function invocations/month
> - 400K GB-seconds/month

### Step 2: Deploy Cloud Functions

Run these commands from your project root:

```bash
cd /home/aser/coding/mobile-iot/smart_cat_feeder

# Deploy only the functions
firebase deploy --only functions
```

**Expected Output:**
```
✔  functions: Finished running predeploy script.
i  functions: preparing smart-cat-feeder-fns directory for uploading...
✔  functions: smart-cat-feeder-fns folder uploaded successfully
i  functions: creating Node.js 18 function checkScheduledFeedings(us-central1)...
i  functions: creating Node.js 18 function triggerManualFeed(us-central1)...
i  functions: creating Node.js 18 function onScheduleCreated(us-central1)...
✔  Deploy complete!
```

### Step 3: Verify Deployment

**In Firebase Console:**
1. Go to **Functions** in the left sidebar
2. You should see 3 functions deployed

**In Google Cloud Console:**
1. Go to [Cloud Scheduler](https://console.cloud.google.com/cloudscheduler)
2. Look for `firebase-schedule-checkScheduledFeedings-us-central1`

---

## How It Works

### When a Schedule is Created

1. User creates schedule in Flutter app → saved to Firestore
2. `onScheduleCreated` function triggers
3. Sends confirmation push notification: "Schedule Created!"

### Every Minute (Scheduled Check)

1. Cloud Scheduler triggers `checkScheduledFeedings`
2. Function queries all users' active schedules
3. For each schedule where:
   - `timeHour` == current hour
   - `timeMinute` == current minute
   - `weekdays` includes current day
4. Function:
   - Creates feeding log entry
   - Updates food level (-5%)
   - Sends push notification
   - (Future) Commands IoT device

### Push Notifications

For push notifications to work:
1. User must have notification permissions enabled
2. App must save FCM token to `users/{userId}/fcm_tokens/{token}`
3. This is already implemented in the Flutter app!

---

## Testing

### Test the Scheduler Function Manually

1. Go to Firebase Console → Functions
2. Click on `checkScheduledFeedings`
3. Click **"Test function"** or go to Cloud Scheduler and click **"Run now"**

### Create a Test Schedule

1. Open the app
2. Create a schedule for 1 minute from now
3. Wait and check:
   - Firebase Console → Firestore → users/{yourId}/feeding_logs
   - You should receive a push notification

### Check Function Logs

```bash
firebase functions:log
```

Or in Firebase Console → Functions → Logs

Look for messages like:
```
⏰ Checking schedules at 14:35 (day 5)
🍽️ Triggering feeding for user abc123: Morning Feeding
✅ Feeding executed for Morning Feeding
📱 Notifications sent: 1 success, 0 failed
```

---

## Troubleshooting

### Function Not Triggering

1. **Check Cloud Scheduler** - Is the job enabled?
2. **Check Timezone** - Is it correct in the function?
3. **Check Schedule Data** - Is `isActive: true`?

### No Push Notification

1. **Check FCM Token** - Is it saved in Firestore?
   ```
   users/{userId}/fcm_tokens/{token}
   ```
2. **Check Permissions** - Did user allow notifications?
3. **Check Logs** - Any errors in function logs?

### Function Errors

```bash
# View recent logs
firebase functions:log --only checkScheduledFeedings

# View all function logs
firebase functions:log
```

---

## Cost Estimation

Firebase Cloud Functions pricing (as of 2024):

| Resource | Free Tier | Cost After |
|----------|-----------|------------|
| Invocations | 2M/month | $0.40/million |
| GB-seconds | 400K/month | $0.0000025/GB-s |
| CPU-seconds | 200K/month | $0.00001/GHz-s |

**For this app:**
- 1 invocation/minute = ~43,200/month
- Well within free tier for small-medium usage

---

## Files Reference

| File | Purpose |
|------|---------|
| `smart-cat-feeder-fns/index.js` | Cloud Functions code |
| `smart-cat-feeder-fns/package.json` | Node.js dependencies |
| `firebase.json` | Firebase configuration |
| `firestore.rules` | Firestore security rules |
| `firestore.indexes.json` | Firestore indexes |

---

## Next Steps (IoT Integration)

When you add hardware (ESP32/Raspberry Pi), uncomment and implement `sendIoTCommand()` in `smart-cat-feeder-fns/index.js`:

```javascript
// Option 1: MQTT
const mqtt = require('mqtt');
const client = mqtt.connect('mqtt://your-broker');
client.publish(`feeder/${userId}/feed`, JSON.stringify({ amount }));

// Option 2: HTTP to device
const axios = require('axios');
await axios.post('http://device-ip/api/feed', { amount });

// Option 3: Firebase Realtime Database (for ESP32)
await admin.database().ref(`feeders/${userId}/command`).set({
  action: 'feed',
  amount: amount,
  timestamp: Date.now()
});
```

---

## Commands Summary

```bash
# Login to Firebase
firebase login

# Deploy everything
firebase deploy

# Deploy only functions
firebase deploy --only functions

# Deploy only Firestore rules
firebase deploy --only firestore:rules

# View function logs
firebase functions:log

# Run functions locally (emulator)
cd smart-cat-feeder-fns && npm run serve
```

---

## Troubleshooting

### "Error: Cloud Functions requires Blaze plan"
→ Upgrade your Firebase project to Blaze (pay-as-you-go)

### "Permission denied" on deploy
→ Run `firebase login` again

### Schedules not triggering
1. Check timezone is correct (`Africa/Cairo`)
2. Verify schedule `isActive: true` in Firestore
3. Check function logs: `firebase functions:log`

### No push notifications
1. Make sure app has saved FCM token to `users/{userId}/fcm_tokens/`
2. Check notification permissions on device
3. Check function logs for FCM errors

---

## Support

If you encounter issues:
1. Check Firebase Console → Functions → Logs
2. Run `firebase functions:log` for detailed errors
3. Ensure Blaze plan is active
4. Verify timezone is `Africa/Cairo`

