# What Works, What's Persistent, What's a Placeholder

Clear breakdown of the app's current functionality status.

---

## ✅ FULLY FUNCTIONAL (Works Now)

### Authentication

| Feature | Persistent? | Details |
|---------|-------------|---------|
| Login | ✅ Yes | Email/password validated, session persists across app restarts |
| Register | ✅ Yes | Creates account, saves to Firebase (or local if offline) |
| Logout | ✅ Yes | Clears session, returns to login |
| Password Reset | ⚡ Firebase only | Sends email if Firebase configured |

**Data Storage:**
- With Firebase: Stored in Firebase Auth
- Without Firebase: Stored in SharedPreferences

---

### Feeding (Home Screen)

| Feature | Persistent? | Details |
|---------|-------------|---------|
| Feed Now button | ✅ Yes | 3-sec animation, creates log entry |
| Feeding logs | ✅ Yes | Saved to Firestore or local storage |
| Food level display | 🔄 Session only | Decreases by 5% per feed, resets on restart |
| Today's count | ✅ Yes | Calculated from saved logs |
| Last feeding time | ✅ Yes | Read from logs |

**What happens when you press Feed Now:**
1. Button shows loading animation (3 seconds)
2. New log entry created with timestamp
3. Log saved to Firestore (if configured) or local list
4. Food level decreases by 5%
5. Success snackbar shown

---

### Feeding History

| Feature | Persistent? | Details |
|---------|-------------|---------|
| Log list | ✅ Yes | All feeding events with timestamps |
| Statistics | ✅ Yes | Today/week/total calculated from logs |
| Date grouping | ✅ Yes | "Today", "Yesterday", or full date |
| Pull to refresh | ✅ Yes | Reloads from Firestore |

**Data stored per log:**
- Timestamp
- Amount (grams)
- Type (manual/scheduled)
- Success status
- Schedule name (if scheduled)

---

### Schedules

| Feature | Persistent? | Details |
|---------|-------------|---------|
| View schedules | ✅ Yes | List of all schedules |
| Create schedule | ✅ Yes | Full form with validation |
| Edit schedule | ✅ Yes | Modify name, time, amount, days |
| Delete schedule | ✅ Yes | With confirmation |
| Toggle active | ✅ Yes | Enable/disable schedule |

**Validation rules:**
- Name: Required, max 30 characters
- Time: Required, via time picker
- Amount: 10-200 grams
- Days: At least one day selected

**Note:** Schedules are saved but don't auto-execute. That requires IoT hardware integration (Phase 3).

---

### Camera (RTSP Streaming)

| Feature | Persistent? | Details |
|---------|-------------|---------|
| Stream URL | ✅ Yes | Saved in SharedPreferences |
| VLC player | ⚡ Functional | Connects to RTSP streams |
| Start/stop | ✅ Session | Controls streaming |
| Play/pause | ✅ Session | VLC playback control |
| Snapshot | ⚡ Conditional | Works when stream active |

**What works:**
- Connects to any RTSP URL you configure
- Uses VLC for low-latency streaming (~300ms)
- Hardware-accelerated playback

**What's needed for real use:**
- Orange Pi running GStreamer RTSP server
- Device on same network (or VPN tunnel)

---

### Settings (SharedPreferences)

| Setting | Persistent? | Default |
|---------|-------------|---------|
| Notifications enabled | ✅ Yes | true |
| Feeding notifications | ✅ Yes | true |
| Cat detection notifications | ✅ Yes | true |
| Default portion size | ✅ Yes | 50g |
| Camera stream URL | ✅ Yes | rtsp://192.168.1.100:8554/live |
| Theme mode | ✅ Yes | light |
| User name | ✅ Yes | From login |
| User email | ✅ Yes | From login |

---

## 🔄 PLACEHOLDERS (UI Only, No Backend)

### Cat Detection

| Feature | Status | What it shows |
|---------|--------|---------------|
| Cat detected badge | Placeholder | Static "Not Detected" |
| Detection notifications | Placeholder | Would trigger from IoT sensor |

**To make functional:** Needs ESP8266 with IR sensor publishing to MQTT/Firebase.

---

### Profile Settings

These items show "Coming soon" when tapped:

- Edit profile
- Change email
- Change password (works with Firebase)
- Device management
- Connection settings
- Portion settings UI
- Push notification settings
- Sound & alerts
- Theme toggle (always light)
- Language selection
- Help & FAQ
- Privacy policy

---

### Night Vision Toggle

Shows message: "Requires IoT hardware support"

**To make functional:** Needs IR LED control via Orange Pi/ESP8266.

---

### Snapshot Gallery

Shows message: "Phase 3 feature"

**To make functional:** Needs file storage and gallery UI.

---

## 📱 OFFLINE MODE

When Firebase is not configured, the app runs in **Demo Mode**:

| Feature | Behavior |
|---------|----------|
| Login indicator | Shows "Demo Mode (Firebase not configured)" |
| Authentication | Any valid email + 6-char password works |
| Data storage | Uses SharedPreferences (local only) |
| Session | Persists until logout |
| Feeding logs | Stored in memory + mock data |
| Schedules | Stored in memory |

**Limitations:**
- Data doesn't sync between devices
- Data may be lost on app uninstall
- Password reset doesn't send email

---

## 🔌 IoT INTEGRATION STATUS

| Component | Status | Required For |
|-----------|--------|--------------|
| ESP8266 | Not connected | Actual feeding, sensors |
| Orange Pi | Not connected | Camera streaming |
| MQTT | Not connected | Real-time sensor data |
| FCM | Not configured | Push notifications |

**Current state:** The app simulates feeding actions. To control real hardware:

1. Set up ESP8266 with servo motor
2. Set up Orange Pi with GStreamer
3. Configure Firestore triggers or MQTT bridge
4. Connect app to real RTSP stream

---

## 📊 SUMMARY TABLE

| Feature Category | Working | Persistent | Placeholder |
|------------------|---------|------------|-------------|
| Authentication | ✅ | ✅ | - |
| Feed Now | ✅ | ✅ | - |
| Feeding History | ✅ | ✅ | Filter |
| Schedules CRUD | ✅ | ✅ | Auto-execute |
| Camera Stream | ✅ | URL only | - |
| Cat Detection | - | - | ✅ |
| Food Level Sensor | - | - | ✅ |
| Push Notifications | - | - | ✅ |
| Profile Settings | - | - | ✅ |

---

## 🧪 QUICK TEST

1. **Login:** Enter any email + 6-char password
2. **Feed:** Press orange "Feed Now" button
3. **History:** Check feeding appeared in History tab
4. **Schedule:** Add new schedule via FAB
5. **Camera:** Configure RTSP URL and test stream
6. **Logout:** Confirm session clears

