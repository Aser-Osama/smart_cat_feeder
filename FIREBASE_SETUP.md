# Firebase Setup Guide

Step-by-step instructions for setting up Firebase for the Smart Cat Feeder app.

---

## Step 1: Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click **"Create a project"**
3. Enter project name: `smart-cat-feeder` (or your choice)
4. Disable Google Analytics (optional, not needed for this app)
5. Click **"Create project"**
6. Wait for project creation, then click **"Continue"**

---

## Step 2: Add Android App

1. In Firebase Console, click the **Android icon** to add an Android app
2. Enter the package name: `com.example.smart_cat_feeder`
   - Find this in `android/app/build.gradle.kts` under `applicationId`
3. Enter app nickname: `Smart Cat Feeder Android`
4. Skip SHA-1 for now (only needed for Google Sign-In)
5. Click **"Register app"**

### Download Config File

1. Click **"Download google-services.json"**
2. Move the file to: `android/app/google-services.json`

```bash
# Example command
mv ~/Downloads/google-services.json android/app/
```

3. Click **"Next"** through the remaining steps (Flutter handles the SDK setup)

---

## Step 3: Enable Authentication

1. In Firebase Console sidebar, click **"Build" → "Authentication"**
2. Click **"Get started"**
3. Go to **"Sign-in method"** tab
4. Click **"Email/Password"**
5. Toggle **"Enable"** on
6. Click **"Save"**

---

## Step 4: Create Firestore Database

1. In Firebase Console sidebar, click **"Build" → "Firestore Database"**
2. Click **"Create database"**
3. Select **"Start in test mode"** (for development)
   - Note: Change to production rules before deploying
4. Select your preferred location (e.g., `us-central1`)
5. Click **"Enable"**

### Set Security Rules (Development)

In Firestore → Rules tab, use these rules for development:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users can only access their own data
    match /users/{userId}/{document=**} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

Click **"Publish"** to save.

---

## Step 5: Verify Android Configuration

Check that `android/app/build.gradle.kts` has the correct minSdk:

```kotlin
defaultConfig {
    minSdk = 21  // Required for Firebase
    // ... other config
}
```

If using older Flutter template, you may need to update `minSdkVersion` from `flutter.minSdkVersion` to `21`.

---

## Step 6: Run the App

```bash
cd smart_cat_feeder
flutter clean
flutter pub get
flutter run
```

### Test Authentication

1. Open the app
2. Go to Register screen
3. Create a new account with email/password
4. Login should work and data syncs to Firebase

---

## Step 7: Verify in Firebase Console

### Check Authentication

1. Go to **Authentication** → **Users** tab
2. You should see registered users listed

### Check Firestore Data

1. Go to **Firestore Database** → **Data** tab
2. You should see:
   - `users` collection
   - User document with their UID
   - Sub-collections: `feeding_logs`, `schedules`, `feeder`

---

## Data Structure

The app uses this Firestore structure:

```
users/
  {userId}/
    feeding_logs/
      {logId}/
        timestamp: Timestamp
        amount: number
        type: "manual" | "scheduled"
        success: boolean
        scheduleName?: string
    
    schedules/
      {scheduleId}/
        name: string
        timeHour: number
        timeMinute: number
        amount: number
        isActive: boolean
        weekdays: number[]
        createdAt: string
    
    feeder/
      status/
        foodLevel: number
        catDetected: boolean
        lastUpdated: Timestamp
```

---

## Troubleshooting

### "No Firebase App" Error

Make sure `google-services.json` is in `android/app/` directory.

### "Permission Denied" Error

Check Firestore rules allow authenticated users to read/write their data.

### Build Fails

```bash
flutter clean
flutter pub get
cd android && ./gradlew clean && cd ..
flutter run
```

### App Works Without Firebase

The app has offline fallback mode. If Firebase isn't configured, it uses local SharedPreferences storage instead. Look for "Demo Mode" indicator on login screen.

---

## iOS Setup (If Needed)

1. In Firebase Console, add an iOS app
2. Bundle ID: `com.example.smartCatFeeder`
3. Download `GoogleService-Info.plist`
4. Add to `ios/Runner/` using Xcode
5. Follow Firebase iOS setup instructions

---

## Production Checklist

Before deploying:

- [ ] Update Firestore rules to production mode
- [ ] Enable App Check for security
- [ ] Set up proper error reporting
- [ ] Configure Firebase billing alerts

