# Smart Cat Feeder Mobile App 🐱

Flutter mobile application for remotely controlling and monitoring an IoT-enabled smart cat feeder.

---

## Quick Start

```bash
cd smart_cat_feeder
flutter pub get
flutter run
```

**Test Login**: Any email + 6+ character password (e.g., `test@example.com` / `password123`)

---

## Current Status (Phase 2) ✅

### Fully Implemented Features

| Feature | Status | Persistence |
|---------|--------|-------------|
| **Authentication** | ✅ Working | Firebase or local fallback |
| **Feed Now** | ✅ Working | Logs saved to Firestore/local |
| **Feeding History** | ✅ Working | Full history with stats |
| **Schedule CRUD** | ✅ Working | Create, edit, delete, toggle |
| **Camera Streaming** | ✅ Working | VLC-based RTSP/HTTP player |
| **Profile & Settings** | ✅ Working | SharedPreferences |
| **Notifications Service** | ✅ Initialized | Ready for FCM |

### Key Improvements in Phase 2
- **Firebase Integration**: Auth, Firestore ready (works offline with local fallback)
- **VLC Video Player**: RTSP/HTTP streaming with demo streams
- **Robust Error Handling**: Graceful degradation when services unavailable
- **Full Schedule Management**: Complete CRUD with validation
- **Persistent Settings**: All preferences saved locally

---

## Running on Android Emulator

### Prerequisites
- Flutter SDK 3.0+
- Android Studio with Android SDK
- Android Emulator (API 30+ recommended)

### Setup Steps

```bash
# 1. Check Flutter setup
flutter doctor

# 2. List available emulators
flutter emulators

# 3. Launch an emulator (or start from Android Studio Device Manager)
flutter emulators --launch <emulator_name>

# 4. Run the app
cd smart_cat_feeder
flutter run
```

### Creating an Emulator (if needed)

**Via Android Studio:**
1. Open Android Studio → **Tools** → **Device Manager**
2. Click **Create Device** → Select phone (e.g., Pixel 6)
3. Select system image (API 34 recommended)
4. Click **Finish** → Launch with play button

**Via Command Line:**
```bash
# Create AVD
avdmanager create avd -n pixel6_api34 -k "system-images;android-34;google_apis;x86_64"

# Launch
emulator -avd pixel6_api34
```

### Installing APK Directly

```bash
# Build debug APK
flutter build apk --debug

# Install via ADB
adb install build/app/outputs/flutter-apk/app-debug.apk
```

---

## Project Structure

```
lib/
├── main.dart                    # Entry point with Firebase init
├── config/theme.dart           # Design system (purple/pink/orange)
├── models/
│   ├── feeding_log.dart        # Feeding log data model
│   └── schedule.dart           # Schedule data model
├── providers/
│   ├── auth_provider.dart      # Authentication state
│   └── feeder_provider.dart    # Feeder & schedule state
├── screens/
│   ├── splash_screen.dart      # App launch screen
│   ├── main_navigation.dart    # Bottom nav controller
│   ├── auth/                   # Login & Register
│   ├── home/                   # Dashboard with Feed Now
│   ├── camera/                 # VLC RTSP streaming
│   ├── history/                # Feeding logs
│   ├── schedule/               # Schedule management
│   └── profile/                # Settings & profile
├── services/
│   ├── firebase_service.dart   # Firestore operations
│   ├── notification_service.dart # FCM setup
│   └── preferences_service.dart  # Local storage
└── widgets/
    ├── custom_button.dart      # Reusable button
    └── custom_text_field.dart  # Reusable input
```

---

## Tech Stack

| Category | Technology |
|----------|------------|
| Framework | Flutter 3.0+ |
| Language | Dart |
| State Management | Provider |
| Backend | Firebase (Auth, Firestore, FCM) |
| Video Streaming | flutter_vlc_player (RTSP/HTTP) |
| Local Storage | SharedPreferences |
| Design | Material Design 3, Google Fonts |

---

## Build Commands

```bash
# Run on connected device/emulator
flutter run

# Run on specific device
flutter run -d emulator-5554    # Android emulator
flutter run -d linux            # Linux desktop

# Build Android APK
flutter build apk --debug
flutter build apk --release

# Build for Linux
flutter build linux --debug

# Clean and rebuild
flutter clean && flutter pub get && flutter run

# Analyze code
flutter analyze
```

**Build outputs:**
- Android: `build/app/outputs/flutter-apk/app-debug.apk`
- Linux: `build/linux/x64/debug/bundle/smart_cat_feeder`

---

## Testing the App

### Quick Test Checklist

1. **Login**: Enter `test@example.com` / `password123`
2. **Feed Now**: Press orange button → watch 3-sec animation
3. **History**: Verify feeding appeared in History tab
4. **Schedule**: Tap + FAB → create new schedule
5. **Camera**: Select a demo stream or enter custom URL
6. **Profile**: Check settings persist after restart

### Demo Streams (Camera Tab)

The app includes working demo video streams for testing:
- Big Buck Bunny (HTTP)
- Sintel Trailer (HTTP)
- Tears of Steel (HTTP)
- Elephant Dream (HTTP)

For real IoT use, configure your RTSP URL (e.g., `rtsp://192.168.1.100:8554/live`).

---

## Firebase Configuration (Optional)

The app works in **offline demo mode** by default. To enable Firebase:

1. Create a Firebase project at [console.firebase.google.com](https://console.firebase.google.com)
2. Add Android app with package name `com.example.smart_cat_feeder`
3. Download `google-services.json` to `android/app/`
4. Enable Authentication (Email/Password)
5. Create Firestore database

See **[FIREBASE_SETUP.md](FIREBASE_SETUP.md)** for detailed instructions.

---

## Phase Roadmap

| Phase | Status | Features |
|-------|--------|----------|
| **Phase 1** | ✅ Complete | UI/UX, Navigation, Mock functionality |
| **Phase 2** | ✅ Complete | Firebase, VLC streaming, Full CRUD, Services |
| **Phase 3** | 🔜 Next | IoT hardware integration (ESP8266, Orange Pi) |
| **Phase 4** | 📋 Planned | ML cat detection, advanced analytics |

---

## Documentation

- **[FUNCTIONALITY.md](FUNCTIONALITY.md)** - Detailed feature status and persistence info
- **[FIREBASE_SETUP.md](FIREBASE_SETUP.md)** - Firebase configuration guide

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "No devices found" | Start emulator: `flutter emulators --launch <name>` |
| "Gradle failed" | Run `flutter clean && flutter pub get` |
| Firebase errors | App works offline; ignore if not configured |
| VLC errors on Linux | VLC plugin has limited Linux support; use Android |
| NDK error | Delete `.gradle` folder, let it re-download |

---

## License

MIT License - Built for IoT/Mobile coursework.
