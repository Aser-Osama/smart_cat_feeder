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

## What's Built (Phase 1)

### ✅ Complete Features
- **7 Screens**: Splash, Login, Register, Home, Camera, History, Schedule, Profile
- **Bottom Navigation**: 5 tabs with state persistence
- **Feed Now**: Press button → 3-sec animation → adds to history
- **Feeding History**: Chronological log with statistics
- **Schedule Management**: View/toggle/delete schedules
- **Responsive Design**: Works on all screen sizes
- **Professional UI**: Purple/pink/orange theme, smooth animations

### 🔄 Ready for Phase 2 (UI complete, no backend)
- Firebase Authentication (currently mock)
- Real IoT feeding (ESP8266 connection)
- Live video streaming (Orange Pi camera)
- Push notifications (FCM)
- Cloud database sync (Firestore)
- Real sensor data (cat detection, food level)

See **[FEATURES.md](FEATURES.md)** for complete list.

---

## Project Structure

```
lib/
├── main.dart                    # Entry point
├── config/theme.dart           # Design system
├── models/feeding_log.dart     # Data models
├── providers/                  # State management
│   ├── auth_provider.dart
│   └── feeder_provider.dart
├── screens/                    # All app screens
│   ├── splash_screen.dart
│   ├── main_navigation.dart
│   ├── auth/
│   ├── home/
│   ├── camera/
│   ├── history/
│   ├── schedule/
│   └── profile/
└── widgets/                    # Reusable components
    ├── custom_button.dart
    └── custom_text_field.dart
```

---

## Tech Stack

- **Framework**: Flutter 3.0+
- **Language**: Dart
- **State Management**: Provider
- **Design**: Material Design 3, Google Fonts
- **Backend (Phase 2)**: Firebase (Auth, Firestore, FCM)

---

## Build Commands

```bash
# Run on connected device
flutter run

# Build Android APK
flutter build apk --debug

# Build for Linux
flutter build linux --debug

# Analyze code
flutter analyze
```

**Build outputs**:
- Android: `build/app/outputs/flutter-apk/app-debug.apk`
- Linux: `build/linux/x64/debug/bundle/smart_cat_feeder`

---

## Phase Roadmap

**Phase 1 (✅ Complete)**: UI/UX, Navigation, Mock functionality  
**Phase 2 (Next)**: Firebase integration, IoT connection, video streaming  
**Phase 3 (Future)**: Advanced features, polish, optimization

---

## Development

### Requirements
- Flutter SDK 3.0+
- Android Studio or Xcode
- Connected device or emulator

### Quick Setup
```bash
flutter doctor              # Check setup
flutter pub get            # Install dependencies
flutter run                # Run app
```

### Common Issues
**"No devices found"**: Start emulator or connect phone  
**"Gradle failed"**: Run `flutter clean && flutter pub get`  
**NDK error**: Delete and let it re-download automatically

----