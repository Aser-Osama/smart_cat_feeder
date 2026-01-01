# Shelter Cat Monitoring System - Pivot Documentation

## Executive Summary

This document details the pivot from a **pet owner feeder** to a **shelter owner monitoring system**. The system now tracks which cat bowls have food across multiple locations using a real Wireless Sensor Network (WSN) with 4 ESP8266 nodes.

---

## Current Architecture (Before Pivot)

```
Flutter App ↔ Firebase Cloud ↔ Orange Pi 3B (Gateway) ↔ MQTT ↔ ESP8266 (Single Node)
                                    │
                              RTSP Camera
```

**Existing Components:**
- Single ESP8266 with button (cat detection) and LED (actuator simulation)
- Orange Pi 3B as MQTT broker + Firebase bridge
- Flutter app for single pet owner with Feed Now, schedules, history

---

## New Architecture (Shelter Monitoring WSN)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              FLUTTER APP                                      │
│                     (Shelter Owner Dashboard)                                 │
└─────────────────────────────────┬────────────────────────────────────────────┘
                                  │ HTTPS / FCM
                                  ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                           FIREBASE CLOUD                                      │
│  Collections:                                                                 │
│   - users/{uid}/nodes/{W,X,Y,Z} - Node status (battery, plate, presence)      │
│   - users/{uid}/alerts - Empty plate warnings                                 │
│   - users/{uid}/routing_logs - Multi-hop routing decisions                    │
└─────────────────────────────────┬────────────────────────────────────────────┘
                                  │ HTTPS (Firestore listener)
                                  ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                      ORANGE PI 3B (SINK NODE)                                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐               │
│  │  MQTT Broker    │  │  Python Gateway │  │  RTSP Camera    │               │
│  │  (Mosquitto)    │  │  (Multi-node)   │  │  (Optional)     │               │
│  └────────┬────────┘  └─────────────────┘  └─────────────────┘               │
└───────────┼──────────────────────────────────────────────────────────────────┘
            │ MQTT over WiFi (with multi-hop routing)
            │
    ┌───────┴───────┬───────────────┬───────────────┐
    ▼               ▼               ▼               ▼
┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐
│ Node W  │   │ Node X  │   │ Node Y  │   │ Node Z  │
│ ESP8266 │◄─►│ ESP8266 │◄─►│ ESP8266 │◄─►│ ESP8266 │
│         │   │         │   │         │   │         │
│ Sensors:│   │ Sensors:│   │ Sensors:│   │ Sensors:│
│ -Ultra. │   │ -Ultra. │   │ -Ultra. │   │ -Ultra. │
│ -Color  │   │ -Color  │   │ -Color  │   │ -Color  │
│ -Batt.  │   │ -Batt.  │   │ -Batt.  │   │ -Batt.  │
│  (sim)  │   │  (sim)  │   │  (sim)  │   │  (sim)  │
└─────────┘   └─────────┘   └─────────┘   └─────────┘
    Bowl W        Bowl X        Bowl Y        Bowl Z
```

---

## Hardware Configuration Per Node

### Pin Definitions (Simplified - Only 6 GPIOs!)
| Component | Pin | GPIO | Description |
|-----------|-----|------|-------------|
| Ultrasonic TRIG | D5 | GPIO14 | ✅ Trigger for HC-SR04 |
| Ultrasonic ECHO | D6 | GPIO12 | ✅ Echo for HC-SR04 |
| Color Sensor S0 | D1 | GPIO5 | ✅ TCS3200 frequency scaling (HIGH) |
| Color Sensor S1 | D2 | GPIO4 | ✅ TCS3200 frequency scaling (LOW) |
| Color Sensor S2 | **GND** | - | ⚡ Hardwired to GND (RED filter) |
| Color Sensor S3 | **GND** | - | ⚡ Hardwired to GND (RED filter) |
| Color Sensor OUT | D7 | GPIO13 | ✅ TCS3200 frequency output |
| Status LED | D0 | GPIO16 | ✅ Node status indicator |

> **Note:** S2/S3 are hardwired to GND to permanently select RED detection and avoid boot-critical pins (GPIO0, GPIO2).

### Sensor Specifications
- **Ultrasonic (HC-SR04):** Range 2cm-400cm, detects cat presence within 30cm
- **Color Sensor (TCS3200/HW-531):** Detects RED food (S2/S3 hardwired to GND for red filter)

---

## Message Formats

### 1. Sensor Telemetry (Node → Sink)
```json
{
  "nodeId": "W",
  "timestamp": 1704067200000,
  "sensors": {
    "ultrasonic": {
      "distanceCm": 15.5,
      "catPresent": true
    },
    "color": {
      "redPulses": 45,
      "foodPresent": true,
      "plateStatus": "filled"
    }
  },
  "battery": {
    "percentage": 78.5,
    "voltage": 3.85,
    "capacityMah": 2000,
    "drainedMah": 430
  },
  "network": {
    "rssi": -65,
    "hopCount": 2,
    "route": ["Y", "X", "SINK"],
    "nextHop": "X"
  }
}
```

### 2. Routing Decision (Node → Sink)
```json
{
  "nodeId": "W",
  "timestamp": 1704067200000,
  "routingDecision": {
    "previousNextHop": "X",
    "newNextHop": "Y",
    "reason": "Better RSSI+battery score",
    "candidates": [
      {"target": "X", "rssi": -75, "battery": 45, "score": 60.5},
      {"target": "Y", "rssi": -60, "battery": 85, "score": 82.0},
      {"target": "SINK", "rssi": -85, "battery": 100, "score": 57.5}
    ],
    "selectedScore": 82.0
  }
}
```

### 3. Alert Payload (Gateway → Firebase/Flutter)
```json
{
  "alertId": "alert_W_1704067200",
  "nodeId": "W",
  "type": "empty_plate",
  "timestamp": 1704067200000,
  "details": {
    "plateStatus": "empty",
    "catPresent": false,
    "colorReading": {"red": 200, "green": 195, "blue": 190},
    "batteryPercent": 78.5
  },
  "severity": "warning",
  "acknowledged": false
}
```

---

## Routing Algorithm

### Metric Calculation
```
score = (RSSI_weight * normalized_rssi) + (Battery_weight * battery_percent)

Where:
- RSSI_weight = 0.4
- Battery_weight = 0.6
- normalized_rssi = (rssi + 100) / 50  // Maps -100..-50 dBm to 0..1
- battery_percent = battery / 100       // Already 0..1
```

### Loop Prevention
- **TTL (Time-To-Live):** Max 4 hops, decremented at each hop
- **Visited Set:** Payload carries list of visited node IDs
- **Direct-to-Sink Fallback:** If no valid next hop, attempt direct transmission

### Routing Table Update Frequency
- Every 30 seconds during normal operation
- Immediate update on significant RSSI change (>10 dBm)
- Immediate update on battery level drop below 20%

---

## Battery Simulation Model

### Parameters
| Parameter | Value | Source |
|-----------|-------|--------|
| Battery Capacity | 2000 mAh | Typical 18650 cell |
| ESP8266 Deep Sleep | 20 µA | Datasheet |
| ESP8266 Active/Idle | 80 mA | Measured |
| ESP8266 WiFi TX | 170 mA | Datasheet (peak) |
| ESP8266 WiFi RX | 50 mA | Datasheet |
| Sensor Read | 15 mA | Combined estimate |

### Drain Calculation (per cycle, ~10 second interval)
```cpp
// Base drain per cycle (10 seconds active)
float baseDrainMah = (80.0 * 10.0) / 3600.0;  // ~0.22 mAh

// Sensor read drain (200ms)
float sensorDrainMah = (15.0 * 0.2) / 3600.0; // ~0.0008 mAh

// WiFi TX drain (per packet, ~50ms)
float txDrainMah = (170.0 * 0.05) / 3600.0;   // ~0.0024 mAh

// WiFi RX drain (listening, ~100ms)
float rxDrainMah = (50.0 * 0.1) / 3600.0;     // ~0.0014 mAh

// Total per cycle (with 1 TX, 1 RX)
float totalDrainMah = baseDrainMah + sensorDrainMah + txDrainMah + rxDrainMah;
// ≈ 0.225 mAh per 10-second cycle
```

### Battery Life Estimate
- 2000 mAh / 0.225 mAh per cycle = ~8889 cycles
- At 10-second intervals = ~24.7 hours continuous operation
- This is intentionally accelerated for demo purposes

---

## Files to Modify/Create

### ESP8266 Firmware
| File | Action | Description |
|------|--------|-------------|
| `iot/esp8266/shelter_node/shelter_node.ino` | CREATE | New multi-node firmware with sensors, routing, battery |
| `iot/esp8266/shelter_node/config.h` | CREATE | Per-node configuration (NODE_ID, etc.) |
| `iot/esp8266/shelter_node/sensors.h` | CREATE | Ultrasonic and color sensor drivers |
| `iot/esp8266/shelter_node/routing.h` | CREATE | Multi-hop routing logic |
| `iot/esp8266/shelter_node/battery.h` | CREATE | Battery simulation model |

### Orange Pi Gateway
| File | Action | Description |
|------|--------|-------------|
| `iot/orangepi/gateway.py` | MODIFY | Handle multi-node topics, alerts, routing logs |

### Flutter App
| File | Action | Description |
|------|--------|-------------|
| `lib/models/shelter_node.dart` | CREATE | Node status model |
| `lib/models/alert.dart` | CREATE | Alert model |
| `lib/providers/shelter_provider.dart` | CREATE | Multi-node state management |
| `lib/screens/shelter/dashboard_screen.dart` | CREATE | Main dashboard with 4 node cards |
| `lib/screens/shelter/alerts_screen.dart` | CREATE | Alerts list and history |
| `lib/screens/shelter/node_detail_screen.dart` | CREATE | Detailed node view |
| `lib/screens/shelter/settings_screen.dart` | CREATE | Thresholds, notification toggles |
| `lib/screens/main_navigation.dart` | MODIFY | Update navigation for shelter app |
| `lib/widgets/node_card.dart` | CREATE | Reusable node status card |

### Firebase
| Collection | Action | Description |
|------------|--------|-------------|
| `users/{uid}/nodes/{nodeId}` | CREATE | Per-node status documents |
| `users/{uid}/alerts` | CREATE | Alert history |
| `users/{uid}/routing_logs` | CREATE | Routing decision logs |

---

## MQTT Topics

### Node → Sink (via routing)
| Topic | Description |
|-------|-------------|
| `shelter/node/{nodeId}/telemetry` | Sensor readings + battery |
| `shelter/node/{nodeId}/routing` | Routing decisions |
| `shelter/node/{nodeId}/alert` | Immediate alerts |

### Sink → Nodes (broadcast or unicast)
| Topic | Description |
|-------|-------------|
| `shelter/broadcast/config` | Configuration updates |
| `shelter/node/{nodeId}/config` | Per-node config |

### Inter-Node (for routing)
| Topic | Description |
|-------|-------------|
| `shelter/mesh/forward` | Message forwarding between nodes |
| `shelter/mesh/neighbor` | Neighbor discovery beacons |

---

## Demo Checklist

### 1. Prove Multi-Hop Routing
- [ ] Start with Node W far from sink, Node X in between
- [ ] Serial logs show: "W → X → SINK" route
- [ ] MQTT topic `shelter/node/W/routing` shows hop path
- [ ] Move Node X away - observe route change to "W → SINK" or "W → Y → SINK"

### 2. Prove Battery Affects Routing
- [ ] Configure Node X with initial battery 30%, Node Y with 90%
- [ ] Observe routing prefers Y despite similar RSSI
- [ ] Drain X further (simulated) - see permanent route change
- [ ] Routing log shows battery in decision metrics

### 3. Prove Empty Plate Alert Logic
- [ ] Place RED object (red kibble/paper) under color sensor - show "Filled" status
- [ ] Remove food (white/empty plate visible) - NO alert while cat present
- [ ] Remove cat (ultrasonic > 30cm) - Alert triggers within 10 seconds
- [ ] Flutter app shows alert notification and log entry

### 4. Prove 4-Node Operation
- [ ] All 4 nodes (W, X, Y, Z) visible in Flutter dashboard
- [ ] Each shows independent battery, plate status, presence
- [ ] Changing one node's status doesn't affect others

---

## Demo Verification Script

### Phase A: Hardware Setup & Initial Verification

#### Step A.1: Flash All Nodes
```bash
# For each node (W, X, Y, Z):
# 1. Open iot/esp8266/shelter_node/config.h
# 2. Change NODE_ID to "W", "X", "Y", or "Z"
# 3. Flash to the corresponding ESP8266

# Verify serial output shows:
# [INIT] Node W starting...
# [WIFI] Connected to ShelterNet
# [MQTT] Connected to broker
# [SENSORS] Ultrasonic: OK, Color: OK
```

#### Step A.2: Start Gateway Services
```bash
# On Orange Pi:
cd ~/mobile-iot/smart_cat_feeder/iot/orangepi

# Start MQTT broker (if not running)
sudo systemctl start mosquitto

# Start gateway
python3 shelter_gateway.py

# Expected output:
# [GATEWAY] Started for nodes: W, X, Y, Z
# [MQTT] Subscribed to shelter/node/+/telemetry
# [FIREBASE] Connected as service account
```

#### Step A.3: Verify MQTT Traffic
```bash
# In separate terminal on Orange Pi:
mosquitto_sub -t "shelter/node/+/telemetry" -v

# Should see messages every 5 seconds like:
# shelter/node/W/telemetry {"nodeId":"W","timestamp":1704067200000,...}
```

---

### Phase B: Multi-Hop Routing Demo

#### Step B.1: Normal Operation (All Direct)
| Node | Expected Route | RSSI | Battery |
|------|---------------|------|---------|
| W | DIRECT | -55 dBm | 85% |
| X | DIRECT | -60 dBm | 90% |
| Y | DIRECT | -58 dBm | 75% |
| Z | DIRECT | -52 dBm | 95% |

**Verification:**
- [ ] Flutter dashboard shows "Direct" route for all nodes
- [ ] Routing section shows "All nodes connected directly"

#### Step B.2: Force Multi-Hop (Move Node Y)
1. Physically move Node Y farther from Orange Pi (RSSI drops to -80 dBm)
2. Node Y should switch to routing through Node X or Z

**Expected MQTT routing message:**
```json
{
  "nodeId": "Y",
  "timestamp": 1704067500000,
  "route": {
    "path": ["Y", "X", "SINK"],
    "hops": 1,
    "reason": "RSSI below threshold (-75 dBm)"
  }
}
```

**Verification:**
- [ ] Flutter shows Node Y route changed to "via X"
- [ ] Routing log entry appears with timestamp

#### Step B.3: Battery-Weighted Routing
1. Simulate low battery on Node X (config drain multiplier)
2. Node Y should prefer routing through Node Z instead

**Expected behavior:**
```
Previous: Y → X → SINK (X at 85% battery)
New:      Y → Z → SINK (X at 15% battery, Z at 90%)
```

**Verification:**
- [ ] Flutter shows Node Y route updated to "via Z"
- [ ] Low battery warning appears for Node X
- [ ] Routing log shows "route_change" entry

---

### Phase C: Sensor & Alert Demo

#### Step C.1: Cat Presence Detection
1. Place hand 15cm above Node W's ultrasonic sensor
2. Hold for 3 seconds

**Expected:**
- [ ] Serial output: `[SENSOR] Distance: 15.2cm, Cat: YES`
- [ ] Flutter dashboard: Node W shows 🐱 icon
- [ ] No empty plate alert while cat present

#### Step C.2: Red Food Detection
1. Place RED object (red kibble, red paper) under color sensor
2. Observe pulse count readings

**Expected serial output:**
```
[COLOR] Red pulses: 45, Food present: YES
```

**Verification:**
- [ ] Flutter shows Node W plate: "Filled"

#### Step C.3: Empty Plate Alert Trigger
1. Remove red object (expose white/empty plate surface)
2. Move hand away (no cat present)
3. Wait 10 seconds

**Expected:**
- [ ] Serial: `[ALERT] Empty plate detected, publishing...`
- [ ] MQTT message to `shelter/node/W/alert`
- [ ] Flutter: New alert appears with "🍽️ Empty Plate at W"
- [ ] FCM push notification (if enabled)

**Verification:**
- [ ] Swipe alert to acknowledge
- [ ] Alert moves to "acknowledged" list
- [ ] Dashboard stats update

---

### Phase D: Battery Simulation Demo

#### Step D.1: Normal Drain
1. Let system run for 5 minutes
2. Observe gradual battery decrease

**Expected drain rates:**
| State | Current Draw | 2000mAh Duration |
|-------|-------------|------------------|
| Idle | 80mA | 25 hours |
| WiFi TX | 170mA | 11.7 hours |
| Sensors Active | 15mA (added) | - |

**Verification:**
- [ ] Battery percentage decreases ~0.1% per minute under load
- [ ] Flutter shows accurate percentage for each node

#### Step D.2: Low Battery Warning
1. Accelerate drain simulation (set `BATTERY_DRAIN_MULTIPLIER = 10`)
2. Wait until Node X reaches 20%

**Expected:**
- [ ] Alert generated: "🔋 Low Battery at Node X (18%)"
- [ ] Dashboard shows orange battery icon for Node X
- [ ] Routing updates to prefer other nodes as relays

#### Step D.3: Critical Battery
1. Continue until Node X reaches 5%

**Expected:**
- [ ] Critical alert: "⚠️ Node X battery critical (5%)"
- [ ] Node attempts to reduce transmission frequency
- [ ] Other nodes stop routing through Node X

---

### Phase E: Full System Integration

#### Step E.1: Multi-Node Parallel Updates
1. Simultaneously trigger changes on all 4 nodes:
   - Node W: Cat arrives
   - Node X: Food removed
   - Node Y: Route changes
   - Node Z: Battery drops

**Verification:**
- [ ] All 4 updates appear in Flutter within 3 seconds
- [ ] No data corruption or cross-contamination
- [ ] Dashboard reflects correct state for each node

#### Step E.2: Network Resilience
1. Briefly disconnect Orange Pi WiFi (10 seconds)
2. Reconnect

**Expected:**
- [ ] Nodes continue collecting data locally
- [ ] After reconnection, queued telemetry is sent
- [ ] Flutter shows temporary "Offline" status, then recovers

#### Step E.3: App Demo Mode
1. Toggle "Demo Mode" in Flutter settings
2. Observe simulated data

**Verification:**
- [ ] Mock nodes appear with realistic changing values
- [ ] Alerts auto-generate periodically
- [ ] Routing changes simulate dynamically

---

## Quick Start

### 1. Flash ESP8266 Nodes
```bash
# Edit config.h to set NODE_ID for each node (W, X, Y, Z)
# Upload shelter_node.ino to each ESP8266
```

### 2. Start Orange Pi Services
```bash
cd iot/orangepi
sudo systemctl restart mosquitto
python3 shelter_gateway.py
```

### 3. Run Flutter App
```bash
cd smart_cat_feeder
flutter run
```

---

## Color Detection Threshold

### Brown Food Detection (TCS3200)
```cpp
// Brown color threshold (adjust based on actual food color)
bool isBrown(int red, int green, int blue) {
  // Brown typically has: R > G > B, with R being dominant
  // And relatively low overall brightness
  int brightness = (red + green + blue) / 3;
  
  bool redDominant = red > green && red > blue;
  bool brownRatio = (green > blue * 0.7) && (green < red * 0.9);
  bool notTooBright = brightness < 180;
  bool notTooDark = brightness > 40;
  
  return redDominant && brownRatio && notTooBright && notTooDark;
}
```

### Empty Plate Alert Rule
```
IF (ultrasonic.distanceCm > CAT_PRESENCE_THRESHOLD_CM) 
   AND (NOT isBrown(color))
THEN trigger_empty_plate_alert()
```

---

## Troubleshooting

### Node Not Appearing in Dashboard
1. Check serial output for WiFi/MQTT connection
2. Verify NODE_ID in config.h matches expected (W, X, Y, Z)
3. Check MQTT broker is running: `systemctl status mosquitto`
4. Verify gateway is subscribed: `mosquitto_sub -t "shelter/node/+/telemetry"`

### Incorrect Color Readings
1. Ensure TCS3200 has stable 5V power
2. Calibrate in well-lit environment
3. Adjust `BROWN_*` thresholds in config.h
4. Test with serial monitor showing raw RGB values

### Battery Draining Too Fast/Slow
1. Adjust `BATTERY_DRAIN_MULTIPLIER` in config.h
2. For real deployment, connect actual battery monitor to ADC

### Routing Not Updating
1. Check RSSI readings in serial output
2. Verify `RSSI_THRESHOLD_DBM` setting (-75 default)
3. Ensure neighbor beacons are being received
4. Check `ROUTING_UPDATE_INTERVAL_MS` isn't too long

---

## Files Created/Modified

### New Files
| Path | Description |
|------|-------------|
| `lib/models/shelter_node.dart` | Node, PlateStatus, ColorReading models |
| `lib/models/alert.dart` | Alert, AlertType, AlertSeverity models |
| `lib/providers/shelter_provider.dart` | State management for 4 nodes |
| `lib/widgets/node_card.dart` | NodeCard widget with status display |
| `lib/screens/shelter/dashboard_screen.dart` | Main monitoring dashboard |
| `lib/screens/shelter/alerts_screen.dart` | Alert list with filtering |
| `iot/esp8266/shelter_node/config.h` | Node configuration & pin defs |
| `iot/esp8266/shelter_node/sensors.h` | Ultrasonic & color sensor classes |
| `iot/esp8266/shelter_node/battery.h` | Battery simulator class |
| `iot/esp8266/shelter_node/routing.h` | Multi-hop routing table |
| `iot/esp8266/shelter_node/shelter_node.ino` | Main firmware |
| `iot/orangepi/shelter_gateway.py` | Multi-node MQTT→Firebase gateway |

### Modified Files
| Path | Changes |
|------|---------|
| `lib/main.dart` | Added ShelterProvider to provider tree |
| `lib/screens/main_navigation.dart` | Updated to shelter-focused 3-tab nav |
