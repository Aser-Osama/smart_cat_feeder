# Shelter Monitoring System - Setup & Testing Guide

This guide walks you through compiling, deploying, wiring, and testing the complete Shelter Monitoring System.

---

## Table of Contents

1. [Compilation & Deployment](#1-compilation--deployment)
2. [Hardware Wiring](#2-hardware-wiring)
3. [Testing Flutter App (With/Without IoT)](#3-testing-flutter-app)
4. [Testing IoT Parts (With/Without Sensors)](#4-testing-iot-parts)
5. [Full System Integration Testing](#5-full-system-testing)

---

## 1. Compilation & Deployment

### 1.1 ESP8266 Nodes (×4)

#### Prerequisites
- Arduino IDE 2.0+ or PlatformIO
- ESP8266 board package installed
- USB cable for each ESP8266

#### Install Arduino ESP8266 Core
```bash
# In Arduino IDE:
# File → Preferences → Additional Board Manager URLs:
# Add: http://arduino.esp8266.com/stable/package_esp8266com_index.json

# Then: Tools → Board Manager → Search "ESP8266" → Install
```

#### Required Libraries
Install via Arduino Library Manager (`Sketch → Include Library → Manage Libraries`):
- `PubSubClient` (MQTT client)
- `ArduinoJson` (JSON parsing)
- `ESP8266WiFi` (built-in)

#### Flash Each Node

```bash
# For each of the 4 nodes (W, X, Y, Z):

# 1. Open the firmware folder
cd smart_cat_feeder/iot/esp8266/shelter_node/

# 2. Edit config.h to set the node ID
nano config.h
# Change: #define NODE_ID "W"  → to "W", "X", "Y", or "Z"

# 3. Set your WiFi credentials in config.h
# #define WIFI_SSID "YourNetworkName"
# #define WIFI_PASSWORD "YourPassword"

# 4. Set Orange Pi's IP address
# #define MQTT_BROKER "192.168.1.100"  # Your Orange Pi's IP

# 5. In Arduino IDE:
#    - Open shelter_node.ino
#    - Select Board: "NodeMCU 1.0 (ESP-12E Module)" or "Generic ESP8266"
#    - Select Port: /dev/ttyUSB0 (Linux) or COM3 (Windows)
#    - Click Upload

# 6. Repeat for each node with different NODE_ID
```

#### Verify Upload
Open Serial Monitor (115200 baud) and check for:
```
[INIT] Shelter Node W starting...
[WIFI] Connecting to ShelterNet...
[WIFI] Connected! IP: 192.168.1.101
[MQTT] Connecting to broker...
[MQTT] Connected!
[SENSORS] Ultrasonic initialized
[SENSORS] Color sensor initialized
[BATTERY] Simulator started at 100%
```

---

### 1.2 Orange Pi Gateway

#### Prerequisites
- Orange Pi 3B with Armbian/Ubuntu
- Python 3.8+
- Network connection (same network as ESP8266 nodes)

#### Install Dependencies
```bash
# SSH into Orange Pi
ssh orangepi@192.168.1.100

# Update system
sudo apt update && sudo apt upgrade -y

# Install Mosquitto MQTT broker
sudo apt install -y mosquitto mosquitto-clients

# Install Python dependencies
sudo apt install -y python3-pip
pip3 install paho-mqtt firebase-admin

# Enable and start Mosquitto
sudo systemctl enable mosquitto
sudo systemctl start mosquitto
```

#### Configure Firebase Service Account
```bash
# 1. Go to Firebase Console → Project Settings → Service Accounts
# 2. Click "Generate new private key"
# 3. Save as serviceAccountKey.json
# 4. Copy to Orange Pi:

scp serviceAccountKey.json orangepi@192.168.1.100:~/smart_cat_feeder/iot/orangepi/
```

#### Deploy Gateway Script
```bash
# Copy gateway files to Orange Pi
scp -r smart_cat_feeder/iot/orangepi/* orangepi@192.168.1.100:~/shelter_gateway/

# SSH in and run
ssh orangepi@192.168.1.100
cd ~/shelter_gateway

# Test run
python3 shelter_gateway.py

# Expected output:
# [GATEWAY] Shelter Gateway starting...
# [MQTT] Connected to broker
# [MQTT] Subscribed to shelter/node/+/telemetry
# [MQTT] Subscribed to shelter/node/+/routing
# [MQTT] Subscribed to shelter/node/+/alert
# [FIREBASE] Initialized with service account
```

#### Run as Service (Optional)
```bash
# Create systemd service
sudo nano /etc/systemd/system/shelter-gateway.service
```

```ini
[Unit]
Description=Shelter Monitoring Gateway
After=network.target mosquitto.service

[Service]
Type=simple
User=orangepi
WorkingDirectory=/home/orangepi/shelter_gateway
ExecStart=/usr/bin/python3 shelter_gateway.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

```bash
# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable shelter-gateway
sudo systemctl start shelter-gateway

# Check status
sudo systemctl status shelter-gateway
```

---

### 1.3 Flutter App

#### Prerequisites
- Flutter 3.0+ SDK
- Android SDK (for Android builds)
- Physical device or emulator

#### Build & Run
```bash
cd smart_cat_feeder

# Get dependencies
flutter pub get

# Check for issues
flutter doctor

# Run on connected device
flutter run

# Or build APK for installation
flutter build apk --release

# APK location: build/app/outputs/flutter-apk/app-release.apk
```

#### Install on Android Device
```bash
# Via ADB
adb install build/app/outputs/flutter-apk/app-release.apk

# Or transfer APK to phone and install manually
```

---

## 2. Hardware Wiring

### 2.1 Component List (Per Node)

| Component | Quantity | Purpose |
|-----------|----------|---------|
| ESP8266 NodeMCU | 1 | Microcontroller |
| HC-SR04 Ultrasonic | 1 | Cat presence detection |
| TCS3200 Color Sensor | 1 | Food (RED) detection |
| LED (any color) | 1 | Status indicator |
| 220Ω Resistor | 1 | LED current limiting |
| Breadboard | 1 | Prototyping |
| Jumper wires | ~10 | Connections (simplified!) |
| USB cable | 1 | Power & programming |

> **📝 Note:** The wiring has been simplified! S2 and S3 pins on the TCS3200 are hardwired to GND, which permanently selects the RED color filter. This reduces GPIO usage and avoids boot-critical ESP8266 pins. Use **red-colored kibble or a red bowl marker** for food detection.

### 2.2 Wiring Diagram (Simplified - Only 6 GPIO Pins!)

```
                    ESP8266 NodeMCU
                   ┌───────────────┐
                   │               │
    [USB Power] ──►│ 5V        3V3 │──► TCS3200 VCC (or use 5V)
                   │               │
                   │ GND       GND │◄── All GND connections
                   │               │    (including TCS3200 S2, S3!)
                   │               │
                   │ D5 (GPIO14)   │──► HC-SR04 TRIG
                   │ D6 (GPIO12)   │◄── HC-SR04 ECHO
                   │               │
                   │ D1 (GPIO5)    │──► TCS3200 S0 (set HIGH)
                   │ D2 (GPIO4)    │──► TCS3200 S1 (set LOW)
                   │ D7 (GPIO13)   │◄── TCS3200 OUT
                   │               │
                   │ D0 (GPIO16)   │──► LED (+) via 220Ω
                   │               │
                   │ D3 (GPIO0)    │    ❌ NOT USED (boot pin)
                   │ D4 (GPIO2)    │    ❌ NOT USED (boot pin)
                   │ D8 (GPIO15)   │    ❌ NOT USED (boot pin)
                   │ RX (GPIO3)    │    ❌ NOT USED (serial)
                   │ TX (GPIO1)    │    ❌ NOT USED (serial)
                   └───────────────┘

    HC-SR04 Ultrasonic Sensor          TCS3200 Color Sensor (SIMPLIFIED)
    ┌─────────────────────┐            ┌─────────────────────────────┐
    │ VCC  TRIG  ECHO GND │            │ VCC  S0  S1  S2  S3  OUT GND │
    └──┬────┬─────┬────┬──┘            └──┬───┬───┬───┬───┬────┬───┬──┘
       │    │     │    │                  │   │   │   │   │    │   │
       │    │     │    │                  │   │   │   │   │    │   │
      5V   D5    D6   GND               3V3  D1  D2  GND GND  D7  GND
                                                     ▲   ▲
                                                     └───┴── HARDWIRED TO GND!
                                                             (Red filter selected)
```

> **⚠️ IMPORTANT:** S2 and S3 on the TCS3200 are connected directly to GND (not GPIO pins!).
> This selects the RED photodiode filter permanently, simplifying detection and freeing 2 GPIO pins.

### 2.3 Detailed Connections

#### HC-SR04 Ultrasonic Sensor
| HC-SR04 Pin | ESP8266 Pin | Notes |
|-------------|-------------|-------|
| VCC | 5V (VIN) | Needs 5V power |
| TRIG | D5 (GPIO14) | ✅ Safe GPIO - Trigger pulse output |
| ECHO | D6 (GPIO12) | ✅ Safe GPIO - Echo pulse input |
| GND | GND | Common ground |

#### TCS3200 Color Sensor (Simplified for RED Detection)
| TCS3200 Pin | Connection | Notes |
|-------------|------------|-------|
| VCC | 3.3V or 5V | Works with either voltage |
| S0 | D1 (GPIO5) | ✅ Safe GPIO - Set HIGH (freq scaling) |
| S1 | D2 (GPIO4) | ✅ Safe GPIO - Set LOW (2% output) |
| **S2** | **GND** | ⚡ **HARDWIRED** - Selects RED filter |
| **S3** | **GND** | ⚡ **HARDWIRED** - Selects RED filter |
| OUT | D7 (GPIO13) | ✅ Safe GPIO - Frequency output |
| GND | GND | Common ground |
| OE | GND | Output Enable (active low) |

> **Why hardwire S2/S3 to GND?**
> - S2=LOW, S3=LOW permanently selects the RED photodiode filter
> - Avoids boot-critical pins (GPIO0, GPIO2, GPIO15)
> - Simplifies code (no need to switch color channels)
> - Use **red/orange colored kibble** for reliable detection

#### Status LED
| LED | ESP8266 Pin | Notes |
|-----|-------------|-------|
| Anode (+) | D0 (GPIO16) via 220Ω | ✅ Safe for OUTPUT only (no PWM) |
| Cathode (-) | GND | Common ground |

#### GPIO Pin Summary
| GPIO | NodeMCU | Usage | Boot Safe? |
|------|---------|-------|------------|
| GPIO14 | D5 | Ultrasonic TRIG | ✅ Yes |
| GPIO12 | D6 | Ultrasonic ECHO | ✅ Yes |
| GPIO5 | D1 | Color S0 | ✅ Yes |
| GPIO4 | D2 | Color S1 | ✅ Yes |
| GPIO13 | D7 | Color OUT | ✅ Yes |
| GPIO16 | D0 | Status LED | ✅ Yes (limited) |
| GPIO0 | D3 | **NOT USED** | ❌ Boot pin |
| GPIO2 | D4 | **NOT USED** | ❌ Boot pin |
| GPIO15 | D8 | **NOT USED** | ❌ Boot pin |

### 2.4 Physical Placement

```
                    ┌─────────────────────────────────────┐
                    │           FOOD BOWL                 │
                    │     ┌───────────────────┐           │
                    │     │                   │           │
                    │     │   (Food Area)     │           │
                    │     │                   │           │
                    │     └───────────────────┘           │
                    │              ▲                      │
                    │              │ 3-5cm                │
                    │     ┌───────┴───────┐              │
                    │     │  TCS3200      │              │
                    │     │  Color Sensor │              │
                    │     │  (facing down)│              │
                    │     └───────────────┘              │
                    │                                     │
   ┌──────────┐     │                                     │
   │ HC-SR04  │◄────┼──── Mount 20-30cm above bowl        │
   │Ultrasonic│     │      Angled toward cat approach     │
   └──────────┘     │                                     │
                    └─────────────────────────────────────┘
```

---

## 3. Testing Flutter App

### 3.1 Without IoT (Demo Mode)

The app works fully without any hardware using **Demo Mode**.

#### Enable Demo Mode
```dart
// Demo mode activates automatically when:
// 1. Firebase is unreachable
// 2. No internet connection
// 3. Manually toggled in settings
```

#### Test Steps

1. **Launch App Without Firebase**
   ```bash
   # Disconnect from internet or use airplane mode
   flutter run
   ```
   
2. **Login with Demo Credentials**
   - Email: `demo@shelter.test` (any valid email format)
   - Password: `demo123` (any 6+ character password)
   - You'll see "Demo Mode" indicator

3. **Test Dashboard Features**
   - [ ] View 4 simulated nodes (W, X, Y, Z)
   - [ ] Each node shows random battery (60-100%)
   - [ ] Plate status cycles between Filled/Empty
   - [ ] Cat presence toggles randomly
   - [ ] Pull-to-refresh generates new random data

4. **Test Alerts**
   - [ ] Navigate to Alerts tab
   - [ ] See simulated empty plate alerts
   - [ ] Swipe to acknowledge alerts
   - [ ] Filter by alert type
   - [ ] Tap alert for details

5. **Test Settings**
   - [ ] Navigate to Settings tab
   - [ ] Toggle Demo Mode on/off
   - [ ] Check notification preferences

### 3.2 With Firebase (No Hardware)

#### Setup Firebase Project
```bash
# 1. Create Firebase project at console.firebase.google.com
# 2. Enable Authentication (Email/Password)
# 3. Create Firestore database
# 4. Download google-services.json to android/app/
# 5. Run FlutterFire CLI:

dart pub global activate flutterfire_cli
flutterfire configure
```

#### Seed Test Data
```javascript
// In Firebase Console → Firestore → Create collection manually
// Or use this script in Cloud Shell:

const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();

// Create test user document
const userId = 'TEST_USER_ID';  // Get from Auth console

// Seed node data
const nodes = ['W', 'X', 'Y', 'Z'];
for (const nodeId of nodes) {
  await db.collection('users').doc(userId)
    .collection('nodes').doc(nodeId).set({
      nodeId: nodeId,
      lastSeen: admin.firestore.FieldValue.serverTimestamp(),
      battery: { percent: 85, voltage: 3.8 },
      plate: { status: 'filled', color: { r: 140, g: 90, b: 50 } },
      catPresent: false,
      route: { nextHop: 'DIRECT', hops: 0 }
    });
}

// Seed test alert
await db.collection('users').doc(userId)
  .collection('alerts').add({
    nodeId: 'W',
    type: 'emptyPlate',
    severity: 'warning',
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    acknowledged: false
  });
```

#### Test with Firebase
1. **Login with Real Account**
   - Register new account or use test account
   - Verify Firestore rules allow access

2. **Test Real-Time Updates**
   - Open Firebase Console → Firestore
   - Manually change a node's `catPresent` to `true`
   - Watch Flutter app update within seconds

3. **Test Alert Creation**
   - Add alert document in Firestore
   - Verify push notification arrives
   - Check alert appears in app

---

## 4. Testing IoT Parts

### 4.1 Without Physical Sensors

Test ESP8266 firmware with simulated sensor data.

#### Enable Simulation Mode
Edit `config.h`:
```cpp
// Uncomment to enable sensor simulation
#define SIMULATE_SENSORS true

// Simulation will:
// - Generate random distances (5-50cm)
// - Generate random RGB values
// - Cycle through states every 10 seconds
```

#### Test MQTT Communication
```bash
# On Orange Pi, subscribe to all node topics:
mosquitto_sub -t "shelter/node/#" -v

# Expected output (every 5 seconds per node):
shelter/node/W/telemetry {"nodeId":"W","timestamp":1704067200000,"sensors":{"ultrasonic":{"distanceCm":15.2,"catPresent":true},"color":{"redPulses":45,"foodPresent":true}},"battery":{"percent":94,"voltage":3.92},"route":{"nextHop":"DIRECT","score":0.94}}
```

#### Test Individual Node
```bash
# Power on only Node W
# Check serial output shows proper initialization
# Check MQTT messages arrive at broker

# Test command reception:
mosquitto_pub -t "shelter/node/W/command" -m '{"action":"status"}'
# Node should respond with current state
```

#### Test Multi-Node Discovery
```bash
# Power on all 4 nodes
# Wait 30 seconds for neighbor discovery
# Check routing table updates in serial output:
# [ROUTING] Neighbors: X(-65dBm,85%), Y(-72dBm,78%), Z(-58dBm,92%)
```

### 4.2 With Physical Sensors

#### Test Ultrasonic Sensor
```bash
# Serial monitor should show distance readings:
# [SENSOR] Distance: 127.3cm (no object)
# [SENSOR] Distance: 23.5cm (hand above)
# [SENSOR] Distance: 15.2cm (cat present threshold)

# Test cat detection threshold (default 30cm):
# Place hand at various distances
# Verify "catPresent" changes at threshold
```

#### Test Color Sensor
```bash
# Serial monitor should show RED pulse count readings:
# [COLOR] Red pulses: 120 → NO FOOD (high count = less red)
# [COLOR] Red pulses: 35  → FOOD PRESENT (low count = red detected)

# Test with different objects:

# White/empty plate:
# [COLOR] Red pulses: 140+ → NOT RED (empty plate)

# Red kibble/marker:
# [COLOR] Red pulses: 30-50 → RED DETECTED (food present)

# Note: Lower pulse count = more red light reflected = food present
```

#### Calibrate Color Threshold
If red detection is inaccurate, adjust in `config.h`:
```cpp
// Adjust these values based on your calibration readings
#define COLOR_FOOD_PRESENT_THRESHOLD  50   // Below this = RED food present
#define COLOR_PLATE_EMPTY_THRESHOLD   150  // Above this = empty/no red
```

---

## 5. Full System Testing

### 5.1 End-to-End Test Checklist

#### Prerequisites
- [ ] All 4 ESP8266 nodes flashed and powered
- [ ] Orange Pi running gateway + MQTT broker
- [ ] Flutter app installed on phone
- [ ] Firebase project configured
- [ ] All devices on same WiFi network

#### Test Sequence

**A. Basic Connectivity (5 minutes)**
```bash
# 1. Verify all nodes connect to MQTT
mosquitto_sub -t "shelter/node/+/telemetry" -v
# Should see messages from W, X, Y, Z every 5 seconds

# 2. Verify gateway receives and processes
# Check gateway logs:
journalctl -u shelter-gateway -f
# Should show "Processing telemetry from node W/X/Y/Z"

# 3. Verify Firestore updates
# Open Firebase Console → Firestore
# Check users/{uid}/nodes/{W,X,Y,Z} documents update
```

**B. Cat Presence Detection (2 minutes)**
```bash
# 1. Wave hand 15cm above Node W's ultrasonic sensor
# 2. Hold for 3 seconds

# Expected:
# - Serial: [SENSOR] Distance: 15.2cm, Cat: YES
# - MQTT: catPresent: true in telemetry
# - Firestore: node W catPresent field updates
# - Flutter: Node W shows 🐱 icon
```

**C. Empty Plate Alert (3 minutes)**
```bash
# 1. Place RED object (red paper/kibble) under Node X's color sensor
#    (simulates filled plate with red food)
# 2. Verify Flutter shows "Filled" status

# 3. Remove red object (expose white/empty surface)
# 4. Remove hand from ultrasonic range (no cat)
# 5. Wait 10 seconds

# Expected:
# - Serial: [ALERT] Empty plate detected!
# - MQTT: Message on shelter/node/X/alert
# - Firestore: New alert document created
# - Flutter: Alert notification + alert in list
# - FCM: Push notification on phone
```

**D. Multi-Hop Routing (5 minutes)**
```bash
# 1. Note current route for Node Y (should be DIRECT)

# 2. Move Node Y physically farther from Orange Pi
#    (or place metal obstruction to weaken signal)

# 3. Wait 30 seconds for routing update

# Expected:
# - Serial (Node Y): [ROUTING] RSSI to SINK: -82dBm (below threshold)
# - Serial (Node Y): [ROUTING] Switching to relay via X (score: 0.78)
# - MQTT: routing message shows path: ["Y", "X", "SINK"]
# - Flutter: Node Y shows "via X" in route info
```

**E. Battery Drain Effect (10 minutes)**
```bash
# 1. Note Node X battery (e.g., 95%)
# 2. Note routing decisions through X

# 3. Accelerate drain (edit config.h):
#    #define BATTERY_DRAIN_MULTIPLIER 100

# 4. Reflash Node X, wait 5 minutes
# 5. Battery should drop to ~50%

# Expected:
# - Other nodes reduce preference for routing through X
# - Low battery alert generated at 20%
# - Flutter shows orange battery icon
```

**F. Offline Recovery (3 minutes)**
```bash
# 1. Disconnect Orange Pi from network (unplug ethernet/WiFi)
# 2. Wait 30 seconds
# 3. Flutter app should show nodes as "Offline"

# 4. Reconnect Orange Pi
# 5. Wait 30 seconds

# Expected:
# - Nodes automatically reconnect to MQTT
# - Queued data syncs to Firestore
# - Flutter shows nodes back "Online"
```

### 5.2 Demo Script for Presentation

Use this script to demonstrate all features in ~10 minutes:

```markdown
## Demo Script

### 1. Introduction (1 min)
- Show Flutter app dashboard with 4 nodes
- Explain: "Each node monitors one feeding station"
- Point out battery levels, plate status, cat presence

### 2. Live Sensor Demo (2 min)
- Place hand over Node W ultrasonic → Show cat detection
- Place brown paper under Node X → Show "Filled" status
- Remove paper + hand → Show empty plate alert appear

### 3. Multi-Hop Routing (2 min)
- Show current routing (all DIRECT)
- Move Node Y away from gateway
- Watch routing update to "via X"
- Explain: "Network self-heals around weak links"

### 4. Battery Management (2 min)
- Show Node Z battery at 90%
- Explain drain model (80mA idle, 170mA TX)
- Show how routing avoids low-battery nodes

### 5. Alert Management (2 min)
- Navigate to Alerts tab
- Show filtering options
- Acknowledge an alert (swipe)
- Show alert detail sheet

### 6. Q&A (1 min)
```

### 5.3 Troubleshooting

| Problem | Cause | Solution |
|---------|-------|----------|
| Node not appearing | WiFi not connected | Check SSID/password in config.h |
| No MQTT messages | Broker not running | `sudo systemctl start mosquitto` |
| Firestore not updating | Gateway error | Check gateway logs, verify serviceAccountKey.json |
| Wrong color detection | Calibration needed | Adjust BROWN_* thresholds in config.h |
| High latency | Network congestion | Reduce telemetry interval or switch to 5GHz WiFi |
| App shows "Offline" | Firebase unreachable | Check internet, Firebase status |

---

## Quick Reference

### Key MQTT Topics
```
shelter/node/W/telemetry    # Sensor data from Node W
shelter/node/X/routing      # Routing decisions from Node X
shelter/node/Y/alert        # Alerts from Node Y
shelter/node/Z/command      # Commands to Node Z
```

### Key Firestore Paths
```
users/{uid}/nodes/{W,X,Y,Z}     # Node status documents
users/{uid}/alerts              # Alert collection
users/{uid}/routing_logs        # Routing history
```

### Useful Commands
```bash
# Monitor all MQTT traffic
mosquitto_sub -t "#" -v

# Send test command to node
mosquitto_pub -t "shelter/node/W/command" -m '{"action":"ping"}'

# Check gateway status
sudo systemctl status shelter-gateway

# View gateway logs
journalctl -u shelter-gateway -f --no-pager

# Restart everything
sudo systemctl restart mosquitto shelter-gateway
```
