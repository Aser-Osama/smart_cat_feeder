# Smart Cat Feeder - Phase 3: IoT/WSN Implementation

This directory contains all IoT components for the Smart Cat Feeder Wireless Sensor Network.

## Architecture Overview

```
┌─────────────────┐      HTTPS/FCM      ┌─────────────────┐
│   Flutter App   │◄──────────────────►│  Firebase Cloud │
└─────────────────┘                     └────────┬────────┘
        │                                        │
        │ RTSP (on-demand)                       │ HTTPS (Firestore listener)
        ▼                                        ▼
┌─────────────────────────────────────────────────────────┐
│                    Orange Pi 3B (Node 2)                │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │ RTSP Camera  │  │ MQTT Broker  │  │ Python Gateway│  │
│  │   Server     │  │ (Mosquitto)  │  │ (Firebase ↔   │  │
│  │              │  │              │  │   MQTT)       │  │
│  └──────────────┘  └──────┬───────┘  └───────────────┘  │
└─────────────────────────────┼───────────────────────────┘
                              │ MQTT over WiFi
                              ▼
┌─────────────────────────────────────────────────────────┐
│                    ESP8266 (Node 1)                     │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │ LED Actuator │  │ MQTT Client  │  │ Button Sensor │  │
│  │ (GPIO pin)   │  │              │  │ (cat detect)  │  │
│  └──────────────┘  └──────────────┘  └───────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## Directory Structure

```
iot/
├── README.md                    # This file
├── orangepi/
│   ├── setup.sh                 # Orange Pi setup script
│   ├── gateway.py               # Python Firebase ↔ MQTT gateway
│   ├── gateway.service          # Systemd service file
│   └── requirements.txt         # Python dependencies
├── esp8266/
│   └── smart_cat_feeder/
│       └── smart_cat_feeder.ino # Arduino sketch for ESP8266
└── firebase/
    └── index.js                 # Updated Cloud Functions
```

## Quick Start

### 1. Orange Pi 3B Setup (Node 2 - Gateway)

```bash
cd iot/orangepi
chmod +x setup.sh
sudo ./setup.sh
```

### 2. ESP8266 Setup (Node 1 - Feeder)

1. Open `iot/esp8266/smart_cat_feeder/smart_cat_feeder.ino` in Arduino IDE
2. Update WiFi and MQTT broker settings
3. Upload to ESP8266

### 3. Deploy Updated Cloud Functions

```bash
cd smart-cat-feeder-fns
firebase deploy --only functions
```

## Communication Flow

### Manual Feeding (App → ESP)
1. User presses "Feed Now" in Flutter app
2. App writes command to Firestore: `users/{uid}/commands/feed`
3. Orange Pi gateway listens to Firestore and receives command
4. Gateway publishes to MQTT topic: `feeder/control/dispense`
5. ESP8266 receives MQTT message and activates LED/servo
6. ESP8266 publishes success to: `feeder/status/fed`
7. Gateway writes log to Firestore

### Cat Detection (ESP → App)
1. User presses button on ESP8266 (simulating ultrasonic/IR sensor)
2. ESP8266 publishes to MQTT: `feeder/status/cat_detected`
3. Gateway receives MQTT message
4. Gateway writes to Firestore: `users/{uid}/feeder/status`
5. Gateway triggers FCM notification via Firebase Admin SDK
6. Flutter app receives push notification

### Camera Streaming
1. User presses "View Camera" in app
2. App connects to RTSP: `rtsp://{ORANGE_PI_IP}:8554/live`
3. Orange Pi streams camera feed via GStreamer RTSP server
4. Stream is on-demand (starts when app connects)

