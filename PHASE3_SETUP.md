# Phase 3: IoT/WSN Integration Guide

This comprehensive guide covers setting up the complete IoT Wireless Sensor Network for the Smart Cat Feeder project.

---

## Table of Contents

1. [Overview](#overview)
2. [Hardware Requirements](#hardware-requirements)
3. [Network Planning](#network-planning)
4. [ESP8266 Setup (Node 1)](#step-1-esp8266-setup-node-1)
5. [Orange Pi 3B Setup (Node 2)](#step-2-orange-pi-3b-setup-node-2)
6. [MQTT Broker Configuration](#step-3-mqtt-broker-configuration)
7. [Video RTSP Server Setup (Demo)](#step-4-video-rtsp-server-setup-demo-mode)
8. [Python Gateway Service](#step-5-python-gateway-service)
9. [Firebase Configuration](#step-6-firebase-configuration)
10. [Flutter App Updates](#step-7-flutter-app-updates)
11. [Cloud Functions Deployment](#step-8-cloud-functions-deployment)
12. [Complete System Testing](#step-9-complete-system-testing)
13. [Troubleshooting Guide](#troubleshooting-guide)
14. [Architecture Reference](#architecture-reference)
15. [Future: USB Camera Setup](#future-usb-camera-setup)
16. [Security Hardening](#security-hardening)

---

## Overview

Phase 3 implements a multi-node IoT Wireless Sensor Network (WSN):

| Component                 | Role                                                  | Communication   |
| ------------------------- | ----------------------------------------------------- | --------------- |
| **ESP8266 (Node 1)**      | Feeder controller with LED actuator and button sensor | MQTT over WiFi  |
| **Orange Pi 3B (Node 2)** | Gateway with camera, MQTT broker, Firebase bridge     | WiFi + Internet |
| **Firebase Cloud**        | User auth, data storage, push notifications           | HTTPS           |
| **Flutter App**           | Remote control and monitoring                         | HTTPS + RTSP    |

### Communication Flow

```
┌─────────────┐          ┌─────────────┐          ┌─────────────┐
│ Flutter App │◄──HTTPS──►│  Firebase   │◄──HTTPS──►│ Orange Pi   │
│             │          │   Cloud     │          │  Gateway    │
│             │◄───RTSP────────────────────────────►│             │
└─────────────┘          └─────────────┘          └──────┬──────┘
                                                         │ MQTT
                                                         ▼
                                                  ┌─────────────┐
                                                  │   ESP8266   │
                                                  │   Feeder    │
                                                  └─────────────┘
```

---

## Hardware Requirements

### Complete Bill of Materials

| Component             | Model/Specification                 | Purpose              | Qty | Approx. Cost |
| --------------------- | ----------------------------------- | -------------------- | --- | ------------ |
| Single Board Computer | Orange Pi 3B (4GB RAM recommended)  | Gateway + Camera     | 1   | $35-50       |
| Camera Module         | Orange Pi Camera (OV5647 or OV5640) | Video streaming      | 1   | $10-15       |
| Microcontroller       | ESP8266 NodeMCU V3 (ESP-12E)        | Feeder control       | 1   | $5-8         |
| LED                   | 5mm LED (any color)                 | Actuator indicator   | 1   | $0.10        |
| Resistor              | 220Ω 1/4W                           | LED current limiting | 1   | $0.05        |
| Push Button           | 6mm tactile switch                  | Cat detection sim    | 1   | $0.20        |
| Power Supply          | 5V 3A USB-C (for Orange Pi)         | Power                | 1   | $10          |
| Power Supply          | 5V 1A Micro USB (for ESP8266)       | Power                | 1   | $5           |
| MicroSD Card          | 16GB+ Class 10 (for Orange Pi)      | OS storage           | 1   | $8           |
| Breadboard            | 400-tie point                       | Prototyping          | 1   | $5           |
| Jumper Wires          | Male-to-male                        | Connections          | 10  | $3           |
| Ethernet Cable        | Cat5e (optional)                    | Initial setup        | 1   | $5           |

**Total estimated cost: ~$85-115**

### Alternative Hardware Options

**ESP8266 Alternatives:**

- Wemos D1 Mini (smaller, recommended for final build)
- ESP-12F module (requires external programmer)
- NodeMCU V2 (slightly different pinout)

**Orange Pi Alternatives:**

- Raspberry Pi 4 (more documentation, higher cost)
- Orange Pi Zero 2 (smaller, no CSI camera)
- Any Linux SBC with camera and WiFi

### Software Requirements

| Component          | Required Software            | Notes                                                              |
| ------------------ | ---------------------------- | ------------------------------------------------------------------ |
| **Orange Pi 3B**   | Official Ubuntu Jammy Server | **Image:** `Orangepi3b_1.0.8_ubuntu_jammy_server_linux5.10.160.7z` |
|                    | Linux Kernel 5.10.160        | ⚠️ **Do NOT use Armbian** - camera not supported on 6.x kernels    |
| **ESP8266**        | Arduino IDE 2.x              | With ESP8266 board support package                                 |
|                    | PubSubClient library         | MQTT client                                                        |
|                    | ArduinoJson library          | JSON parsing                                                       |
| **Development PC** | Firebase CLI                 | For deploying Cloud Functions                                      |
|                    | Flutter SDK                  | Already installed from Phase 1-2                                   |

---

## Network Planning

Before starting, plan your network setup:

### IP Address Planning

| Device         | Suggested Static IP | Notes                        |
| -------------- | ------------------- | ---------------------------- |
| Router/Gateway | 192.168.1.1         | Your router                  |
| Orange Pi 3B   | 192.168.1.100       | MQTT broker + camera         |
| ESP8266        | DHCP (dynamic)      | Or set static: 192.168.1.101 |
| Development PC | DHCP                | For programming devices      |

### Required Ports

| Port | Protocol | Service              | Access             |
| ---- | -------- | -------------------- | ------------------ |
| 1883 | TCP      | MQTT (Mosquitto)     | Local network only |
| 8554 | TCP/UDP  | RTSP (Camera stream) | Local network only |
| 22   | TCP      | SSH (Orange Pi)      | Local network only |

### WiFi Requirements

- **Frequency**: 2.4GHz (ESP8266 doesn't support 5GHz)
- **Security**: WPA2-PSK recommended
- **Signal**: Strong signal in feeder location
- **SSID**: No special characters recommended

---

## Step 1: ESP8266 Setup (Node 1)

### 1.1 Hardware Wiring

#### Complete Wiring Diagram

```
                    ┌─────────────────────────────────────┐
                    │         ESP8266 NodeMCU V3          │
                    │                                     │
                    │    [RST]  [A0]                      │
                    │    [EN]   [D0/GPIO16]               │
                    │    [3V3]──────────────┐             │
                    │    [GND]──────────────┼──┐          │
     Built-in LED◄──│    [D4/GPIO2]         │  │          │
                    │    [D3/GPIO0]         │  │          │
         Button────►│    [D2/GPIO4]─────────┼──┼──[BTN]   │
  Actuator LED────►│    [D1/GPIO5]───[R]───│──┼──[LED+]  │
                    │    [RX]               │  │          │
                    │    [TX]               │  │          │
                    │    [GND]              │  │          │
                    │    [3V3]              │  │          │
                    │    [Vin]              │  │          │
                    │                       │  │          │
                    └───────────────────────┴──┴──────────┘
                                            │  │
                                            │  └── LED(-) and Button(GND)
                                            └───── Button(+) (3.3V)

    [R] = 220Ω resistor
    [BTN] = Tactile push button
    [LED+] = LED anode (longer leg)
    LED(-) = LED cathode (shorter leg, to GND)
```

#### Pin Reference Table

| NodeMCU Pin | GPIO  | Function                  | Connection                |
| ----------- | ----- | ------------------------- | ------------------------- |
| D1          | GPIO5 | Actuator LED output       | LED (+) via 220Ω resistor |
| D2          | GPIO4 | Button input (pull-up)    | Button to GND             |
| D4          | GPIO2 | Built-in LED (active LOW) | On-board LED              |
| 3V3         | -     | 3.3V power                | Button other terminal     |
| GND         | -     | Ground                    | LED (-), Button common    |

#### Step-by-Step Wiring

1. **LED Circuit (Actuator Simulation)**
   
   ```
   D1 (GPIO5) ──► 220Ω Resistor ──► LED Anode (+, long leg)
                                    LED Cathode (-, short leg) ──► GND
   ```
   
   - The 220Ω resistor limits current to ~15mA (safe for ESP8266)
   - LED will light when GPIO5 is HIGH

2. **Button Circuit (Sensor Simulation)**
   
   ```
   D2 (GPIO4) ──────────┬──► Button Terminal 1
                        │
   Internal Pull-up     │
   (enabled in code)    │
                        │
   Button Terminal 2 ───┴──► GND
   ```
   
   - Uses internal pull-up resistor (no external resistor needed)
   - Button press connects GPIO4 to GND (reads LOW)
   - Released = HIGH (due to pull-up)

### 1.2 Arduino IDE Setup

#### Install Arduino IDE

**Ubuntu/Debian:**

```bash
# Method 1: Snap (recommended, auto-updates)
sudo snap install arduino

# Method 2: APT (may be older version)
sudo apt update
sudo apt install arduino

# Method 3: AppImage (download from arduino.cc)
wget https://downloads.arduino.cc/arduino-ide/arduino-ide_2.3.2_Linux_64bit.AppImage
chmod +x arduino-ide_2.3.2_Linux_64bit.AppImage
./arduino-ide_2.3.2_Linux_64bit.AppImage
```

**Fedora:**

```bash
# Flatpak
flatpak install flathub cc.arduino.IDE2

# Or download AppImage from arduino.cc
```

**Windows/macOS:**

- Download from [arduino.cc/en/software](https://www.arduino.cc/en/software)

#### Add ESP8266 Board Support

1. Open Arduino IDE
2. Go to **File → Preferences** (or **Arduino IDE → Settings** on macOS)
3. In "Additional boards manager URLs", add:
   
   ```
   https://arduino.esp8266.com/stable/package_esp8266com_index.json
   ```
   
   (If you have other URLs, separate with commas)
4. Click **OK**
5. Go to **Tools → Board → Boards Manager**
6. Search for "**esp8266**"
7. Install "**ESP8266 by ESP8266 Community**" (latest version)
8. Wait for installation to complete

#### Install Required Libraries

1. Go to **Sketch → Include Library → Manage Libraries**

2. Search and install:
   
   | Library      | Author          | Version    | Purpose      |
   | ------------ | --------------- | ---------- | ------------ |
   | PubSubClient | Nick O'Leary    | 2.8+       | MQTT client  |
   | ArduinoJson  | Benoît Blanchon | 6.x or 7.x | JSON parsing |

3. Click **Install** for each

#### Configure Board Settings

1. Go to **Tools → Board → ESP8266 Boards**

2. Select "**NodeMCU 1.0 (ESP-12E Module)**"

3. Configure settings:
   
   | Setting       | Value                                  | Notes                           |
   | ------------- | -------------------------------------- | ------------------------------- |
   | Board         | NodeMCU 1.0 (ESP-12E Module)           |                                 |
   | Upload Speed  | 115200                                 | Increase to 921600 if stable    |
   | CPU Frequency | 80 MHz                                 | Can use 160 MHz for performance |
   | Flash Size    | 4MB (FS:2MB OTA:~1019KB)               | Default for NodeMCU             |
   | Debug Port    | Disabled                               | Enable for debugging            |
   | Debug Level   | None                                   |                                 |
   | lwIP Variant  | v2 Lower Memory                        |                                 |
   | VTables       | Flash                                  |                                 |
   | Exceptions    | Legacy                                 |                                 |
   | Erase Flash   | Only Sketch                            |                                 |
   | SSL Support   | All SSL ciphers                        |                                 |
   | Port          | /dev/ttyUSB0 (Linux) or COM3 (Windows) |                                 |

### 1.3 ESP8266 Code Configuration

#### Open the Sketch

```bash
# Navigate to the sketch
cd smart_cat_feeder/iot/esp8266/smart_cat_feeder/
# Open with Arduino IDE
arduino smart_cat_feeder.ino
```

Or in Arduino IDE: **File → Open → Navigate to the .ino file**

#### Update Configuration Constants

Edit lines 28-42 in `smart_cat_feeder.ino`:

```cpp
// ============================================================================
// Configuration - UPDATE THESE VALUES
// ============================================================================

// WiFi credentials - MUST MATCH YOUR NETWORK EXACTLY
const char* WIFI_SSID = "YourWiFiName";           // Case-sensitive!
const char* WIFI_PASSWORD = "YourWiFiPassword";   // Case-sensitive!

// MQTT Broker (Orange Pi IP address)
// Find with: hostname -I (on Orange Pi)
const char* MQTT_BROKER = "192.168.1.100";  // Your Orange Pi's IP
const int MQTT_PORT = 1883;                 // Default MQTT port
const char* MQTT_CLIENT_ID = "esp8266-feeder";

// Firebase User ID - Get from app login or Firebase Console
// Format: 28 character alphanumeric string
const char* USER_ID = "abc123def456ghi789jkl012mno";  // Your Firebase UID
```

#### How to Find Your Firebase User ID

**Method 1: From Flutter App Debug Console**

```
Run the app, log in, and look for:
✅ Firebase initialized successfully
Current user ID: Xk9mN2pQ7rS4tU1vW3xY5zA8bC
```

**Method 2: From Firebase Console**

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your project
3. Go to **Authentication → Users**
4. Find your email and copy the "User UID" column

### 1.4 Upload to ESP8266

#### Connect ESP8266 to Computer

1. Connect NodeMCU to your computer via Micro USB cable
2. Wait for driver installation (usually automatic)

#### Identify the Port

**Linux:**

```bash
# Before connecting
ls /dev/ttyUSB*  # Note existing devices

# After connecting
ls /dev/ttyUSB*  # New device is your ESP8266

# Usually: /dev/ttyUSB0

# If permission denied:
sudo usermod -a -G dialout $USER
# Log out and back in
```

**macOS:**

```bash
ls /dev/cu.usbserial*
# Usually: /dev/cu.usbserial-0001 or similar
```

**Windows:**

- Open Device Manager
- Look under "Ports (COM & LPT)"
- Usually: COM3, COM4, etc.

#### Upload the Code

1. Select the correct port: **Tools → Port → /dev/ttyUSB0**
2. Click the **Upload** button (→ arrow)
3. Wait for compilation and upload:
   
   ```
   Sketch uses 287456 bytes (27%) of program storage space.
   Global variables use 28104 bytes (34%) of dynamic memory.
   Uploading...
   ...............
   Done uploading.
   ```

#### Troubleshooting Upload Issues

| Issue             | Solution                                       |
| ----------------- | ---------------------------------------------- |
| Port not found    | Try different USB cable (some are charge-only) |
| Permission denied | Run: `sudo chmod 666 /dev/ttyUSB0`             |
| Upload fails      | Hold FLASH button while clicking Upload        |
| Timeout           | Lower upload speed to 115200                   |
| esptool.py error  | Install: `pip install esptool`                 |

### 1.5 Verify ESP8266 Operation

#### Open Serial Monitor

1. **Tools → Serial Monitor** (or Ctrl+Shift+M)
2. Set baud rate to **115200** (bottom right dropdown)
3. Press the **RST** button on NodeMCU

#### Expected Output

```
=======================================
Smart Cat Feeder - ESP8266 Node
=======================================
📡 Connecting to WiFi: YourWiFiName...
.....
✅ WiFi connected!
   IP address: 192.168.1.101
🔌 Connecting to MQTT broker: 192.168.1.100... ✅ connected!
   Subscribed to: feeder/control/dispense
💓 Heartbeat sent
✅ Setup complete!
Press the button to simulate cat detection
```

#### Test Button Press

1. Press the button connected to D2
2. Serial Monitor should show:
   
   ```
   🐱 Cat detected! (button pressed)
   📤 Published to feeder/status/cat_detected: {"userId":"...","detected":true,"timestamp":12345}
   ```
3. Built-in LED should blink 3 times

---

## Step 2: Orange Pi 3B Setup (Node 2)

### 2.1 Download and Flash Official Orange Pi Ubuntu Image

> **Important:** We use the official Orange Pi Ubuntu image with Linux 5.10 kernel instead of Armbian. 
> The newer Armbian kernels (6.x) have compatibility issues with the Orange Pi camera module.

#### Download Official Image

1. Go to [Orange Pi Downloads](http://www.orangepi.org/html/hardWare/computerAndMicrocontrollers/service-and-support/Orange-Pi-3B.html)

2. Download: **`Orangepi3b_1.0.8_ubuntu_jammy_server_linux5.10.160.7z`**

3. Extract the .7z file to get the .img file:
   
   ```bash
   # Install 7z if needed
   sudo apt install p7zip-full   # Debian/Ubuntu
   sudo dnf install p7zip        # Fedora
   
   # Extract
   7z x Orangepi3b_1.0.8_ubuntu_jammy_server_linux5.10.160.7z
   ```

#### Why This Image?

| Image                  | Kernel       | Camera Support              |
| ---------------------- | ------------ | --------------------------- |
| Armbian (latest)       | 6.1 / 6.12   | ❌ Camera module not working |
| **Orange Pi Official** | **5.10.160** | ✅ **Full camera support**   |

#### Flash to SD Card

**Using balenaEtcher (Recommended):**

1. Download [balenaEtcher](https://www.balena.io/etcher/)
2. Insert SD card into computer (16GB+ recommended)
3. Open Etcher → Select the extracted .img file → Select drive → Flash

**Using dd (Linux command line):**

```bash
# Find your SD card device
lsblk

# Unmount if mounted
sudo umount /dev/sdX*

# Flash (CAREFUL: replace sdX with your actual device!)
sudo dd if=Orangepi3b_1.0.8_ubuntu_jammy_server_linux5.10.160.img of=/dev/sdX bs=4M status=progress
sudo sync
```

### 2.2 Initial Orange Pi Boot

#### First Boot

1. Insert SD card into Orange Pi 3B
2. Connect:
   - Ethernet cable (recommended for initial setup)
   - Or configure WiFi headlessly later
   - 5V 3A USB-C power supply
3. Connect HDMI + keyboard (optional but helpful)
4. Power on

#### Initial Login

For the official Orange Pi Ubuntu image:

- **Default username:** `orangepi`
- **Default password:** `orangepi`
- **Root password:** `orangepi`

```bash
# SSH into the Orange Pi (find IP from router or use HDMI)
ssh orangepi@192.168.1.XXX

# Password: orangepi
```

#### First Boot Configuration

```bash
# Change default passwords immediately!
passwd                    # Change orangepi user password
sudo passwd root          # Change root password

# Update system
sudo apt update && sudo apt upgrade -y

# Set timezone
sudo timedatectl set-timezone Africa/Cairo

# Set hostname (optional)
sudo hostnamectl set-hostname smart-cat-feeder

# Verify kernel version (should be 5.10.160)
uname -r
# Expected output: 5.10.160-rockchip-rk356x
```

### 2.3 Network Configuration

#### Check Current IP Address

```bash
# Show all IP addresses
ip addr show

# Or simpler
hostname -I
```

#### Configure Static IP (Recommended)

**Method 1: Using nmtui (interactive)**

```bash
sudo nmtui
# Select "Edit a connection"
# Select your connection (eth0 or wlan0)
# Change IPv4 from "Automatic" to "Manual"
# Add address: 192.168.1.100/24
# Add gateway: 192.168.1.1
# Add DNS: 8.8.8.8, 8.8.4.4
# Save and Quit
# Reactivate the connection
```

**Method 2: Using nmcli (command line)**

```bash
# For Ethernet
sudo nmcli con mod "Wired connection 1" \
  ipv4.addresses 192.168.1.100/24 \
  ipv4.gateway 192.168.1.1 \
  ipv4.dns "8.8.8.8 8.8.4.4" \
  ipv4.method manual

# For WiFi
sudo nmcli con mod "YourWiFiSSID" \
  ipv4.addresses 192.168.1.100/24 \
  ipv4.gateway 192.168.1.1 \
  ipv4.dns "8.8.8.8 8.8.4.4" \
  ipv4.method manual

# Restart networking
sudo nmcli con down "Wired connection 1" && sudo nmcli con up "Wired connection 1"
```

#### Configure WiFi

```bash
# Scan for networks
sudo nmcli dev wifi list

# Connect to WiFi
sudo nmcli dev wifi connect "YourSSID" password "YourPassword"

# Verify connection
ip addr show wlan0
```

### 2.4 Video Stream Setup (Demo Mode)

> **Note:** The Orange Pi CSI camera module may have hardware compatibility issues with certain 
> Orange Pi 3B boards. For the demo, we'll stream a pre-recorded video file. 
> See [Future: USB Camera Setup](#future-usb-camera-setup) for live camera options.

#### Demo Video Approach

For the project demonstration, we'll use a looping video file instead of a live camera feed. 
This provides:

- ✅ Reliable demo without camera hardware issues
- ✅ Consistent video quality for presentation
- ✅ Same RTSP protocol the app expects
- ✅ Easy to set up and test

#### Download or Create Demo Video

**Option 1: Download a sample video**

```bash
# Create video directory
sudo mkdir -p /opt/smart-cat-feeder/videos

# Download a sample cat video (Creative Commons)
cd /opt/smart-cat-feeder/videos

# Big Buck Bunny (reliable test video)
wget -O demo.mp4 "https://sample-videos.com/video321/mp4/720/big-buck-bunny_trailer_720p.mp4"

# Or use youtube-dl for a cat video (if available)
# youtube-dl -f 'best[height<=720]' -o demo.mp4 "https://www.youtube.com/watch?v=YE7VzlLtp-4"
```

**Option 2: Create your own demo video**

```bash
# Record a short video on your phone
# Transfer to Orange Pi:
scp cat_demo.mp4 orangepi@192.168.1.100:/opt/smart-cat-feeder/videos/demo.mp4
```

**Option 3: Generate a test pattern video**

```bash
# Create a 1-minute test pattern video with GStreamer
gst-launch-1.0 -e videotestsrc pattern=smpte num-buffers=1800 ! \
    video/x-raw,width=640,height=480,framerate=30/1 ! \
    x264enc ! mp4mux ! \
    filesink location=/opt/smart-cat-feeder/videos/demo.mp4
```

#### Verify Video File

```bash
# Check video file exists and is valid
ls -lh /opt/smart-cat-feeder/videos/demo.mp4

# Get video info
ffprobe /opt/smart-cat-feeder/videos/demo.mp4 2>&1 | grep -E "Duration|Video:"

# Test playback (if HDMI connected)
gst-launch-1.0 filesrc location=/opt/smart-cat-feeder/videos/demo.mp4 ! \
    decodebin ! videoconvert ! autovideosink
```

#### Install Required Packages

```bash
sudo apt update
sudo apt install -y \
    gstreamer1.0-tools \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-libav \
    ffmpeg
```

### 2.5 System Updates and Dependencies

```bash
# Update system (already done in first boot, but repeat for latest packages)
sudo apt update && sudo apt upgrade -y

# Install all required packages for IoT Gateway
sudo apt install -y \
    mosquitto \
    mosquitto-clients \
    python3-pip \
    python3-venv \
    gstreamer1.0-tools \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-rtsp \
    gstreamer1.0-libav \
    gstreamer1.0-rockchip1 \
    libgstrtspserver-1.0-0 \
    v4l-utils \
    git \
    curl \
    python3-gi \
    gir1.2-gst-rtsp-server-1.0

# Verify installations
mosquitto -h       # Should show help
python3 --version  # Should show 3.10+
gst-launch-1.0 --version  # Should show GStreamer version
```

> **Note:** The `gstreamer1.0-rockchip1` package provides hardware-accelerated video encoding 
> specific to the RK3566 SoC on Orange Pi 3B, which improves streaming performance.

---

## Step 3: MQTT Broker Configuration

### 3.1 Mosquitto Installation

Mosquitto should already be installed from the previous step. Verify:

```bash
# Check if installed
mosquitto -v

# Check service status
sudo systemctl status mosquitto
```

### 3.2 Configure Mosquitto

Create a custom configuration:

```bash
# Create configuration file
sudo nano /etc/mosquitto/conf.d/smart_cat_feeder.conf
```

Add the following content:

```conf
# Smart Cat Feeder MQTT Configuration
# ====================================

# Listen on all interfaces
listener 1883

# Allow anonymous connections (for development)
# IMPORTANT: Disable in production and use authentication
allow_anonymous true

# Logging
log_dest file /var/log/mosquitto/mosquitto.log
log_type all

# Connection settings
max_connections 50
autosave_interval 60

# Keep-alive settings
max_keepalive 120

# For production, uncomment these lines:
# allow_anonymous false
# password_file /etc/mosquitto/passwd
```

Restart Mosquitto:

```bash
sudo systemctl restart mosquitto
sudo systemctl enable mosquitto
```

### 3.3 Test MQTT Broker

Open two terminal windows/tabs:

**Terminal 1 - Subscribe to all topics:**

```bash
mosquitto_sub -h localhost -t '#' -v
```

**Terminal 2 - Publish a test message:**

```bash
mosquitto_pub -h localhost -t 'test/hello' -m 'Hello MQTT!'
```

Terminal 1 should show:

```
test/hello Hello MQTT!
```

### 3.4 MQTT Topics Reference

| Topic                        | Direction     | Purpose          | Payload Example                  |
| ---------------------------- | ------------- | ---------------- | -------------------------------- |
| `feeder/control/dispense`    | Gateway → ESP | Trigger feeding  | `{"command":"feed","amount":50}` |
| `feeder/status/fed`          | ESP → Gateway | Feeding complete | `{"success":true,"amount":50}`   |
| `feeder/status/cat_detected` | ESP → Gateway | Cat presence     | `{"detected":true}`              |
| `feeder/status/heartbeat`    | ESP → Gateway | Keep-alive       | `{"uptime":12345}`               |

---

## Step 4: Video RTSP Server Setup (Demo Mode)

### 4.1 Understanding RTSP Streaming

RTSP (Real-Time Streaming Protocol) allows the Flutter app to view the video feed on-demand. 
For the demo, we stream a looping video file that simulates a live camera feed.

### 4.2 Create RTSP Server Script (Video File Mode)

```bash
# Create directory (if not already created)
sudo mkdir -p /opt/smart-cat-feeder

# Create RTSP server script
sudo nano /opt/smart-cat-feeder/rtsp_server.py
```

Add the following content:

```python
#!/usr/bin/env python3
"""
Smart Cat Feeder - RTSP Video Server (Demo Mode)
Streams a looping video file on rtsp://<IP>:8554/live

For demo purposes - simulates live camera feed.
See USB camera section for live streaming setup.
"""

import gi
gi.require_version('Gst', '1.0')
gi.require_version('GstRtspServer', '1.0')
from gi.repository import Gst, GstRtspServer, GLib
import sys
import os

# Initialize GStreamer
Gst.init(None)

# Configuration
VIDEO_FILE = "/opt/smart-cat-feeder/videos/demo.mp4"
RTSP_PORT = 8554
MOUNT_POINT = "/live"

class VideoRTSPServer:
    def __init__(self, video_file, port=8554, mount_point="/live"):
        # Verify video file exists
        if not os.path.exists(video_file):
            print(f"ERROR: Video file not found: {video_file}")
            print("Please download or create a demo video first.")
            print("See PHASE3_SETUP.md section 2.4 for instructions.")
            sys.exit(1)

        self.server = GstRtspServer.RTSPServer()
        self.server.set_service(str(port))

        # Create media factory
        factory = GstRtspServer.RTSPMediaFactory()

        # GStreamer pipeline for looping video file
        # multifilesrc loops the video, decodebin handles any format
        pipeline = (
            f"( filesrc location={video_file} ! "
            "qtdemux ! h264parse ! "
            "rtph264pay name=pay0 pt=96 config-interval=1 )"
        )

        # Alternative pipeline for non-H264 videos (transcodes to H264):
        # pipeline = (
        #     f"( multifilesrc location={video_file} loop=true ! "
        #     "decodebin ! videoconvert ! "
        #     "x264enc tune=zerolatency bitrate=1500 speed-preset=superfast ! "
        #     "rtph264pay name=pay0 pt=96 config-interval=1 )"
        # )

        factory.set_launch(pipeline)
        factory.set_shared(True)  # Allow multiple clients

        # Add mount point
        mount_points = self.server.get_mount_points()
        mount_points.add_factory(mount_point, factory)

        # Attach server
        self.server.attach(None)

        # Get actual IP
        import socket
        hostname = socket.gethostname()
        try:
            # Get the actual network IP, not localhost
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            ip_addr = s.getsockname()[0]
            s.close()
        except:
            ip_addr = "192.168.1.100"

        print("=" * 55)
        print("Smart Cat Feeder - RTSP Video Server (Demo Mode)")
        print("=" * 55)
        print(f"Video file: {video_file}")
        print(f"Stream URL: rtsp://{ip_addr}:{port}{mount_point}")
        print(f"Local URL:  rtsp://localhost:{port}{mount_point}")
        print("")
        print("Test with:")
        print(f"  ffplay rtsp://{ip_addr}:{port}{mount_point}")
        print(f"  vlc rtsp://{ip_addr}:{port}{mount_point}")
        print("=" * 55)

def main():
    print("Starting RTSP video server...")

    # Check if video file exists
    if not os.path.exists(VIDEO_FILE):
        print(f"\n❌ ERROR: Demo video not found at {VIDEO_FILE}")
        print("\nTo fix this, run one of:")
        print("  1. Download a sample video:")
        print("     wget -O /opt/smart-cat-feeder/videos/demo.mp4 \\")
        print("       'https://sample-videos.com/video321/mp4/720/big-buck-bunny_trailer_720p.mp4'")
        print("\n  2. Copy your own video:")
        print("     scp video.mp4 orangepi@IP:/opt/smart-cat-feeder/videos/demo.mp4")
        sys.exit(1)

    server = VideoRTSPServer(VIDEO_FILE, RTSP_PORT, MOUNT_POINT)

    loop = GLib.MainLoop()
    try:
        print("\nServer running. Press Ctrl+C to stop.")
        loop.run()
    except KeyboardInterrupt:
        print("\nShutting down...")
        sys.exit(0)

if __name__ == "__main__":
    main()
```

Make executable:

```bash
sudo chmod +x /opt/smart-cat-feeder/rtsp_server.py
```

### 4.3 Test RTSP Server

```bash
# Make sure demo video exists
ls -la /opt/smart-cat-feeder/videos/demo.mp4

# Run manually first to test
python3 /opt/smart-cat-feeder/rtsp_server.py
```

From another device on the network:

```bash
# Using ffplay (part of ffmpeg)
ffplay rtsp://192.168.1.100:8554/live

# Using VLC
vlc rtsp://192.168.1.100:8554/live

# Using GStreamer
gst-launch-1.0 rtspsrc location=rtsp://192.168.1.100:8554/live latency=0 ! \
    decodebin ! videoconvert ! autovideosink
```

### 4.4 Looping Video Playback

If you want the video to loop continuously (useful for demos):

```bash
# Create a looping RTSP server script
sudo nano /opt/smart-cat-feeder/rtsp_server_loop.py
```

```python
#!/usr/bin/env python3
"""
RTSP Server with Looping Video
Continuously loops a video file for demo purposes.
"""

import gi
gi.require_version('Gst', '1.0')
gi.require_version('GstRtspServer', '1.0')
from gi.repository import Gst, GstRtspServer, GLib
import sys
import os

Gst.init(None)

VIDEO_FILE = "/opt/smart-cat-feeder/videos/demo.mp4"

class LoopingRTSPServer:
    def __init__(self):
        self.server = GstRtspServer.RTSPServer()
        self.server.set_service("8554")

        factory = GstRtspServer.RTSPMediaFactory()

        # Pipeline that loops the video file
        # Uses playbin with video-sink as a fakesink to just get the stream
        pipeline = (
            f"( filesrc location={VIDEO_FILE} ! "
            "decodebin ! videoconvert ! videoscale ! "
            "video/x-raw,width=640,height=480 ! "
            "x264enc tune=zerolatency bitrate=1500 speed-preset=superfast ! "
            "rtph264pay name=pay0 pt=96 config-interval=1 )"
        )

        factory.set_launch(pipeline)
        factory.set_shared(True)

        self.server.get_mount_points().add_factory("/live", factory)
        self.server.attach(None)

        print("Looping RTSP server running on rtsp://0.0.0.0:8554/live")

if __name__ == "__main__":
    if not os.path.exists(VIDEO_FILE):
        print(f"Video not found: {VIDEO_FILE}")
        sys.exit(1)

    server = LoopingRTSPServer()
    GLib.MainLoop().run()
```

### 4.4 Create Systemd Service for RTSP

```bash
sudo nano /etc/systemd/system/smart-cat-feeder-camera.service
```

Add:

```ini
[Unit]
Description=Smart Cat Feeder RTSP Camera Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/smart-cat-feeder
ExecStart=/usr/bin/python3 /opt/smart-cat-feeder/rtsp_server.py
Restart=always
RestartSec=5
StandardOutput=append:/var/log/smart-cat-feeder-camera.log
StandardError=append:/var/log/smart-cat-feeder-camera.log

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable smart-cat-feeder-camera
sudo systemctl start smart-cat-feeder-camera

# Check status
sudo systemctl status smart-cat-feeder-camera

# View logs
sudo tail -f /var/log/smart-cat-feeder-camera.log
```

---

## Step 5: Python Gateway Service

### 5.1 Create Python Virtual Environment

```bash
# Create directory structure
sudo mkdir -p /opt/smart-cat-feeder
cd /opt/smart-cat-feeder

# Create virtual environment
sudo python3 -m venv venv

# Activate virtual environment
source venv/bin/activate

# Upgrade pip
pip install --upgrade pip
```

### 5.2 Install Python Dependencies

Create requirements file:

```bash
sudo nano /opt/smart-cat-feeder/requirements.txt
```

Add:

```
paho-mqtt>=1.6.0,<2.0
firebase-admin>=6.0.0
python-dotenv>=1.0.0
```

Install:

```bash
source /opt/smart-cat-feeder/venv/bin/activate
pip install -r /opt/smart-cat-feeder/requirements.txt
```

### 5.3 Create Gateway Script

```bash
sudo nano /opt/smart-cat-feeder/gateway.py
```

The gateway script is already in `iot/orangepi/gateway.py`. Copy it:

```bash
# From your development machine
scp iot/orangepi/gateway.py orangepi@192.168.1.100:/opt/smart-cat-feeder/

# Or create manually by copying the content
```

### 5.4 Create Systemd Service for Gateway

```bash
sudo nano /etc/systemd/system/smart-cat-feeder-gateway.service
```

Add:

```ini
[Unit]
Description=Smart Cat Feeder Gateway (Firebase-MQTT Bridge)
After=network.target mosquitto.service
Wants=mosquitto.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/smart-cat-feeder
Environment="GOOGLE_APPLICATION_CREDENTIALS=/opt/smart-cat-feeder/firebase-credentials.json"
ExecStart=/opt/smart-cat-feeder/venv/bin/python /opt/smart-cat-feeder/gateway.py
Restart=always
RestartSec=10
StandardOutput=append:/var/log/smart-cat-feeder-gateway.log
StandardError=append:/var/log/smart-cat-feeder-gateway.log

[Install]
WantedBy=multi-user.target
```

Enable the service (don't start yet - need Firebase credentials first):

```bash
sudo systemctl daemon-reload
sudo systemctl enable smart-cat-feeder-gateway
```

---

## Step 6: Firebase Configuration

### 6.1 Generate Service Account Key

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your Smart Cat Feeder project
3. Click the **gear icon** → **Project settings**
4. Go to **Service accounts** tab
5. Click **Generate new private key**
6. Click **Generate key** in the confirmation dialog
7. A JSON file will download (e.g., `smart-cat-feeder-firebase-adminsdk-xxxxx.json`)

### 6.2 Upload Credentials to Orange Pi

```bash
# From your development machine
scp ~/Downloads/smart-cat-feeder-firebase-adminsdk-*.json \
    orangepi@192.168.1.100:/opt/smart-cat-feeder/firebase-credentials.json

# Or use secure method with key
scp -i ~/.ssh/id_rsa ~/Downloads/smart-cat-feeder-firebase-adminsdk-*.json \
    orangepi@192.168.1.100:/opt/smart-cat-feeder/firebase-credentials.json
```

Set proper permissions:

```bash
# On Orange Pi
sudo chmod 600 /opt/smart-cat-feeder/firebase-credentials.json
sudo chown root:root /opt/smart-cat-feeder/firebase-credentials.json
```

### 6.3 Update Firestore Security Rules

Go to Firebase Console → Firestore Database → Rules and update:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // User documents - only accessible by the user
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;

      // User's sub-collections
      match /{document=**} {
        allow read, write: if request.auth != null && request.auth.uid == userId;
      }
    }

    // Gateway status (optional - for monitoring)
    match /gateways/{gatewayId} {
      // Only server (admin SDK) can write
      allow read: if request.auth != null;
    }
  }
}
```

### 6.4 Start Gateway Service

```bash
# Start the gateway
sudo systemctl start smart-cat-feeder-gateway

# Check status
sudo systemctl status smart-cat-feeder-gateway

# View logs in real-time
sudo tail -f /var/log/smart-cat-feeder-gateway.log
```

Expected log output:

```
2024-01-15 10:30:00 - INFO - ✅ Firebase initialized successfully
2024-01-15 10:30:01 - INFO - ✅ MQTT connected to localhost:1883
2024-01-15 10:30:01 - INFO - 📡 Subscribed to ESP8266 topics
2024-01-15 10:30:01 - INFO - 🚀 Smart Cat Feeder Gateway starting...
2024-01-15 10:30:01 - INFO - 🔄 Setting up Firestore listeners...
```

---

## Step 7: Flutter App Updates

### 7.1 Configure Camera URL in App

1. Open the Flutter app on your phone
2. Navigate to **Camera** screen
3. Tap the **URL** button (or link icon)
4. Enter: `rtsp://192.168.1.100:8554/live`
5. Tap **Play Stream**

### 7.2 Verify IoT Connection

On the **Home** screen, you should see:

- **IoT Gateway Connected** (green status banner)
- Last update timestamp

If showing "Offline":

- Check if gateway service is running
- Verify Firebase credentials
- Check network connectivity

### 7.3 Test Manual Feeding

1. Press **Feed Now** button in app
2. Watch ESP8266 Serial Monitor:
   
   ```
   📨 MQTT received [feeder/control/dispense]: {"command":"feed"...}
   🍽️ Feed command received! Amount: 50g
   🔄 Dispensing food...
   ✅ Feeding complete!
   📤 Published to feeder/status/fed
   ```
3. LED should light up for 3 seconds
4. App should show "Feeding successful!"

---

## Step 8: Cloud Functions Deployment

### 8.1 Install Firebase CLI

```bash
# Install Node.js if not present
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs

# Install Firebase CLI
npm install -g firebase-tools

# Login to Firebase
firebase login
```

### 8.2 Deploy Functions

```bash
cd smart_cat_feeder/smart-cat-feeder-fns

# Install dependencies
npm install

# Deploy
firebase deploy --only functions
```

Expected output:

```
=== Deploying to 'smart-cat-feeder-xxxxx'...

i  functions: preparing codebase default for deployment
✔  functions: functions folder uploaded successfully
i  functions: creating Node.js 18 function checkScheduledFeedings...
i  functions: creating Node.js 18 function triggerManualFeed...
i  functions: creating Node.js 18 function onScheduleCreated...
i  functions: creating Node.js 18 function onFeedCommandCreated...
i  functions: creating Node.js 18 function onCatDetected...
✔  functions[checkScheduledFeedings]: Successful create operation.
✔  functions[triggerManualFeed]: Successful create operation.
...

✔  Deploy complete!
```

### 8.3 Verify Deployment

1. Go to Firebase Console → Functions
2. Verify all functions are listed and active
3. Check for any deployment errors in the logs

---

## Step 9: Complete System Testing

### 9.1 Test Checklist

| Test             | Steps                                   | Expected Result          | ✓   |
| ---------------- | --------------------------------------- | ------------------------ | --- |
| ESP8266 WiFi     | Check Serial Monitor                    | "WiFi connected" message | ☐   |
| ESP8266 MQTT     | Check Serial Monitor                    | "MQTT connected" message | ☐   |
| MQTT Broker      | `mosquitto_sub -h localhost -t '#' -v`  | Receives messages        | ☐   |
| Camera Stream    | `ffplay rtsp://192.168.1.100:8554/live` | Video displays           | ☐   |
| Gateway Firebase | Check gateway logs                      | "Firebase initialized"   | ☐   |
| Gateway MQTT     | Check gateway logs                      | "MQTT connected"         | ☐   |
| App IoT Status   | Home screen                             | Shows "Connected"        | ☐   |
| Manual Feed      | Press Feed Now                          | LED lights, app confirms | ☐   |
| Cat Detection    | Press ESP button                        | Notification received    | ☐   |
| Camera in App    | Open Camera, enter URL                  | Live video displays      | ☐   |

### 9.2 End-to-End Test: Manual Feeding

1. **Open 4 monitoring windows:**
   
   **Terminal 1 - ESP8266 Serial Monitor** (Arduino IDE)
   
   **Terminal 2 - MQTT messages:**
   
   ```bash
   mosquitto_sub -h 192.168.1.100 -t '#' -v
   ```
   
   **Terminal 3 - Gateway logs:**
   
   ```bash
   sudo tail -f /var/log/smart-cat-feeder-gateway.log
   ```
   
   **Terminal 4 - Firebase Console open in browser**

2. **Press "Feed Now" in app**

3. **Expected flow:**
   
   ```
   App → Firestore write
   Gateway detects Firestore change
   Gateway → MQTT: feeder/control/dispense
   ESP8266 receives, LED ON
   ESP8266 → MQTT: feeder/status/fed
   Gateway receives, writes to Firestore
   App receives Firestore update
   Gateway sends FCM notification
   ```

### 9.3 End-to-End Test: Cat Detection

1. **Same 4 monitoring windows**

2. **Press button on ESP8266**

3. **Expected flow:**
   
   ```
   Button pressed on ESP8266
   ESP8266 → MQTT: feeder/status/cat_detected
   Gateway receives MQTT
   Gateway → Firestore update
   Cloud Function triggers
   FCM notification sent
   App receives notification
   App UI updates (cat icon)
   ```

---

## Troubleshooting Guide

### ESP8266 Issues

#### Won't Connect to WiFi

```
Symptom: Serial shows ".........." forever
```

| Check             | Solution                      |
| ----------------- | ----------------------------- |
| SSID exact match  | WiFi names are case-sensitive |
| Password correct  | Check for special characters  |
| 2.4GHz band       | ESP8266 doesn't support 5GHz  |
| Signal strength   | Move closer to router         |
| Router MAC filter | Add ESP8266 MAC address       |

```cpp
// Debug: Print MAC address
Serial.println(WiFi.macAddress());
```

#### Won't Connect to MQTT

```
Symptom: "MQTT connection failed, rc=-2"
```

| Return Code | Meaning            | Solution               |
| ----------- | ------------------ | ---------------------- |
| -4          | Connection timeout | Check IP address       |
| -3          | Connection lost    | Check network          |
| -2          | Connect failed     | Mosquitto not running  |
| -1          | Disconnected       | Check broker address   |
| 1           | Bad protocol       | Update PubSubClient    |
| 2           | Client ID rejected | Change MQTT_CLIENT_ID  |
| 4           | Bad credentials    | Check if auth required |
| 5           | Not authorized     | Check Mosquitto ACL    |

```bash
# On Orange Pi, verify Mosquitto is listening
netstat -tlnp | grep 1883
# Should show: tcp 0 0 0.0.0.0:1883 0.0.0.0:* LISTEN
```

### Orange Pi Issues

#### Camera Not Detected

```bash
# Check camera module connection
dmesg | grep -i camera
dmesg | grep -i video

# List video devices
ls -la /dev/video*

# Check kernel module
lsmod | grep -i video
```

Solutions:

1. Reseat the camera ribbon cable
2. Check ribbon cable orientation (contacts face board)
3. Add camera overlay in `/boot/armbianEnv.txt`
4. Try different camera device: `/dev/video1`, `/dev/video2`

#### RTSP Stream Fails

```bash
# Test camera directly
gst-launch-1.0 v4l2src device=/dev/video0 ! fakesink

# Check GStreamer plugins
gst-inspect-1.0 x264enc
gst-inspect-1.0 rtph264pay
```

If x264enc not found:

```bash
sudo apt install gstreamer1.0-plugins-ugly
```

#### Gateway Firebase Errors

```
ERROR - Firebase initialization failed
```

1. Verify credentials file exists:
   
   ```bash
   ls -la /opt/smart-cat-feeder/firebase-credentials.json
   ```

2. Verify JSON is valid:
   
   ```bash
   python3 -c "import json; json.load(open('/opt/smart-cat-feeder/firebase-credentials.json'))"
   ```

3. Check file permissions:
   
   ```bash
   sudo chmod 600 /opt/smart-cat-feeder/firebase-credentials.json
   ```

### Network Issues

#### Find Device IP Addresses

```bash
# On router - check connected devices list

# On Orange Pi
hostname -I

# On ESP8266 (Serial Monitor)
# Look for: "IP address: 192.168.x.x"

# Network scan from any Linux machine
nmap -sn 192.168.1.0/24
```

#### Firewall Issues

```bash
# On Orange Pi - check firewall
sudo ufw status

# If active, allow MQTT and RTSP
sudo ufw allow 1883/tcp
sudo ufw allow 8554/tcp
sudo ufw reload
```

### Flutter App Issues

#### Camera Not Playing

1. Check network connectivity
2. Verify RTSP URL format: `rtsp://IP:8554/live`
3. Test URL in VLC first
4. Check if on same network as Orange Pi
5. Disable VPN if using

#### Not Receiving Notifications

1. Check notification permissions in system settings
2. Verify FCM token in Firestore:
   
   ```
   users/{uid}/fcm_tokens/
   ```
3. Check Cloud Functions logs in Firebase Console
4. Ensure notifications enabled in app settings

---

## Architecture Reference

### Complete System Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              USER'S SMARTPHONE                               │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                          Flutter Application                          │  │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌───────────────────┐  │  │
│  │  │   Home    │  │  Camera   │  │  History  │  │     Schedule      │  │  │
│  │  │  Screen   │  │  Screen   │  │  Screen   │  │      Screen       │  │  │
│  │  │           │  │           │  │           │  │                   │  │  │
│  │  │ • Feed    │  │ • RTSP    │  │ • Logs    │  │ • Create/Edit     │  │  │
│  │  │   Now     │  │   Stream  │  │ • Filter  │  │ • Enable/Disable  │  │  │
│  │  │ • IoT     │  │ • On      │  │           │  │                   │  │  │
│  │  │   Status  │  │   Demand  │  │           │  │                   │  │  │
│  │  └─────┬─────┘  └─────┬─────┘  └─────┬─────┘  └─────────┬─────────┘  │  │
│  └────────┼──────────────┼──────────────┼───────────────────┼────────────┘  │
└───────────┼──────────────┼──────────────┼───────────────────┼───────────────┘
            │              │              │                   │
            │ Firestore    │ RTSP         │ Firestore         │ Firestore
            │ Commands     │ Port 8554    │ feeding_logs      │ schedules
            │              │              │                   │
            ▼              │              ▼                   ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                            FIREBASE CLOUD                                    │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────────┐  │
│  │    Firestore    │  │      FCM        │  │      Cloud Functions        │  │
│  │    Database     │  │   Push Notify   │  │                             │  │
│  │                 │  │                 │  │  • checkScheduledFeedings   │  │
│  │ users/          │  │ Sends to app:   │  │    (runs every 1 min)       │  │
│  │   {uid}/        │  │ • Feed complete │  │  • onCatDetected            │  │
│  │     commands/   │  │ • Cat detected  │  │    (Firestore trigger)      │  │
│  │     feeder/     │  │ • Low food      │  │  • triggerManualFeed        │  │
│  │     feeding_logs│  │ • Schedule      │  │    (callable)               │  │
│  │     schedules/  │  │                 │  │                             │  │
│  │     fcm_tokens/ │  │                 │  │                             │  │
│  └────────┬────────┘  └────────┬────────┘  └──────────────┬──────────────┘  │
└───────────┼────────────────────┼──────────────────────────┼─────────────────┘
            │                    │                          │
            │ Firestore          │                          │
            │ Realtime           │                          │
            │ Listener           │                          │
            ▼                    │                          │
┌─────────────────────────────────────────────────────────────────────────────┐
│                         ORANGE PI 3B (192.168.1.100)                         │
│                              NODE 2 - GATEWAY                                │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────────┐  │
│  │   RTSP Camera   │  │  MQTT Broker    │  │      Python Gateway         │  │
│  │     Server      │  │  (Mosquitto)    │  │                             │  │
│  │                 │  │                 │  │  • Firestore listener       │  │
│  │ • Port 8554     │  │ • Port 1883     │  │  • MQTT subscriber          │  │
│  │ • /dev/video0   │  │ • Local only    │  │  • Firebase Admin SDK       │  │
│  │ • H.264 encode  │  │                 │  │  • FCM notifications        │  │
│  │ • On-demand     │  │ Topics:         │  │                             │  │
│  │   streaming     │  │ • feeder/       │  │ Bridges:                    │  │
│  │                 │  │   control/      │  │ • Firestore → MQTT          │  │
│  │                 │  │   dispense      │  │ • MQTT → Firestore          │  │
│  │                 │  │ • feeder/       │  │                             │  │
│  │                 │  │   status/       │  │                             │  │
│  │                 │  │   fed           │  │                             │  │
│  │                 │  │ • feeder/       │  │                             │  │
│  │                 │  │   status/       │  │                             │  │
│  │                 │  │   cat_detected  │  │                             │  │
│  └─────────────────┘  └────────┬────────┘  └─────────────────────────────┘  │
└────────────────────────────────┼────────────────────────────────────────────┘
                                 │
                                 │ MQTT over WiFi (2.4GHz)
                                 │ QoS 0
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         ESP8266 NodeMCU (192.168.1.101)                      │
│                              NODE 1 - FEEDER                                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────────┐  │
│  │   LED Actuator  │  │   MQTT Client   │  │      Button Sensor          │  │
│  │                 │  │                 │  │                             │  │
│  │ • GPIO5 (D1)    │  │ • PubSubClient  │  │ • GPIO4 (D2)                │  │
│  │ • 220Ω resistor │  │   library       │  │ • Internal pull-up          │  │
│  │ • Simulates     │  │ • Subscribes to │  │ • Debounced                 │  │
│  │   servo motor   │  │   dispense      │  │ • Simulates IR/ultrasonic   │  │
│  │ • 3 sec ON      │  │ • Publishes     │  │ • Triggers cat_detected     │  │
│  │   when feeding  │  │   status        │  │   on press                  │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────────────────┘  │
│                                                                              │
│  Built-in LED (GPIO2/D4): Blinks during cat detection confirmation          │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Data Flow Sequences

#### Sequence 1: Manual Feeding

```
┌─────────┐     ┌──────────┐     ┌──────────┐     ┌─────────┐
│   App   │     │ Firebase │     │ Orange   │     │ ESP8266 │
│         │     │          │     │   Pi     │     │         │
└────┬────┘     └────┬─────┘     └────┬─────┘     └────┬────┘
     │               │                │                │
     │ 1. Write command               │                │
     │──────────────►│                │                │
     │               │                │                │
     │               │ 2. Listener    │                │
     │               │    triggered   │                │
     │               │───────────────►│                │
     │               │                │                │
     │               │                │ 3. MQTT pub    │
     │               │                │───────────────►│
     │               │                │                │
     │               │                │                │ 4. LED ON
     │               │                │                │    (3 sec)
     │               │                │                │
     │               │                │ 5. MQTT pub    │
     │               │                │◄───────────────│
     │               │                │  (fed status)  │
     │               │                │                │
     │               │ 6. Write log   │                │
     │               │◄───────────────│                │
     │               │                │                │
     │ 7. Real-time  │                │                │
     │    update     │                │                │
     │◄──────────────│                │                │
     │               │                │                │
     │ 8. FCM push   │                │                │
     │◄──────────────│                │                │
     │               │                │                │
```

#### Sequence 2: Cat Detection

```
┌─────────┐     ┌──────────┐     ┌──────────┐     ┌─────────┐
│   App   │     │ Firebase │     │ Orange   │     │ ESP8266 │
│         │     │          │     │   Pi     │     │         │
└────┬────┘     └────┬─────┘     └────┬─────┘     └────┬────┘
     │               │                │                │
     │               │                │                │ 1. Button
     │               │                │                │    pressed
     │               │                │                │
     │               │                │ 2. MQTT pub    │
     │               │                │◄───────────────│
     │               │                │ (cat_detected) │
     │               │                │                │
     │               │ 3. Write       │                │
     │               │    status      │                │
     │               │◄───────────────│                │
     │               │                │                │
     │               │ 4. Cloud Func  │                │
     │               │    triggered   │                │
     │               │                │                │
     │ 5. FCM push   │                │                │
     │◄──────────────│                │                │
     │ "Cat detected"│                │                │
     │               │                │                │
     │ 6. Real-time  │                │                │
     │    update     │                │                │
     │◄──────────────│                │                │
     │               │                │                │
```

---

## Future: USB Camera Setup

> This section covers setting up a USB webcam for live streaming once you have compatible hardware.
> USB cameras are generally more compatible than CSI camera modules.

### Recommended USB Cameras

| Camera             | Resolution | Price   | Notes                                 |
| ------------------ | ---------- | ------- | ------------------------------------- |
| Logitech C270      | 720p       | ~$25    | Widely compatible, good Linux support |
| Logitech C920      | 1080p      | ~$70    | Excellent quality, hardware H.264     |
| Generic USB Webcam | 720p       | ~$10-15 | Usually works, check UVC support      |

**Key requirement:** The camera must support **UVC (USB Video Class)** for Linux compatibility.

### USB Camera Setup Steps

#### 1. Connect and Detect USB Camera

```bash
# Connect USB camera to Orange Pi

# Check if detected
lsusb
# Look for your camera (e.g., "Logitech, Inc. Webcam C270")

# Check video devices
ls -la /dev/video*
# Should show /dev/video0 or similar

# Verify camera capabilities
v4l2-ctl --device=/dev/video0 --all
v4l2-ctl --device=/dev/video0 --list-formats-ext
```

#### 2. Test USB Camera

```bash
# Test camera capture
gst-launch-1.0 v4l2src device=/dev/video0 ! videoconvert ! autovideosink

# Test with specific resolution
gst-launch-1.0 v4l2src device=/dev/video0 ! \
    video/x-raw,width=640,height=480,framerate=30/1 ! \
    videoconvert ! autovideosink
```

#### 3. Update RTSP Server for USB Camera

Create a new RTSP server script for live USB camera:

```python
#!/usr/bin/env python3
"""
Smart Cat Feeder - RTSP USB Camera Server
Streams live USB camera on rtsp://<IP>:8554/live
"""

import gi
gi.require_version('Gst', '1.0')
gi.require_version('GstRtspServer', '1.0')
from gi.repository import Gst, GstRtspServer, GLib
import sys
import os

Gst.init(None)

# Configuration - adjust for your camera
USB_CAMERA_DEVICE = "/dev/video0"
CAMERA_WIDTH = 640
CAMERA_HEIGHT = 480
CAMERA_FPS = 30
RTSP_PORT = 8554

class USBCameraRTSPServer:
    def __init__(self):
        # Check camera exists
        if not os.path.exists(USB_CAMERA_DEVICE):
            print(f"ERROR: Camera not found at {USB_CAMERA_DEVICE}")
            print("Check: ls /dev/video*")
            sys.exit(1)

        self.server = GstRtspServer.RTSPServer()
        self.server.set_service(str(RTSP_PORT))

        factory = GstRtspServer.RTSPMediaFactory()

        # Pipeline for USB camera (UVC)
        pipeline = (
            f"( v4l2src device={USB_CAMERA_DEVICE} ! "
            f"video/x-raw,width={CAMERA_WIDTH},height={CAMERA_HEIGHT},"
            f"framerate={CAMERA_FPS}/1 ! "
            "videoconvert ! "
            "x264enc tune=zerolatency bitrate=1500 speed-preset=superfast ! "
            "rtph264pay name=pay0 pt=96 config-interval=1 )"
        )

        factory.set_launch(pipeline)
        factory.set_shared(True)

        self.server.get_mount_points().add_factory("/live", factory)
        self.server.attach(None)

        # Get IP
        import socket
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            ip = s.getsockname()[0]
            s.close()
        except:
            ip = "localhost"

        print("=" * 55)
        print("Smart Cat Feeder - USB Camera RTSP Server")
        print("=" * 55)
        print(f"Camera: {USB_CAMERA_DEVICE}")
        print(f"Resolution: {CAMERA_WIDTH}x{CAMERA_HEIGHT}@{CAMERA_FPS}fps")
        print(f"Stream: rtsp://{ip}:{RTSP_PORT}/live")
        print("=" * 55)

if __name__ == "__main__":
    server = USBCameraRTSPServer()
    print("Server running. Press Ctrl+C to stop.")
    GLib.MainLoop().run()
```

Save as `/opt/smart-cat-feeder/rtsp_usb_camera.py`

#### 4. Update Systemd Service for USB Camera

```bash
sudo nano /etc/systemd/system/smart-cat-feeder-camera.service
```

Change `ExecStart` to use the USB camera script:

```ini
[Unit]
Description=Smart Cat Feeder USB Camera RTSP Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/smart-cat-feeder
ExecStart=/usr/bin/python3 /opt/smart-cat-feeder/rtsp_usb_camera.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl restart smart-cat-feeder-camera
```

### USB Camera Troubleshooting

| Issue             | Solution                                                  |
| ----------------- | --------------------------------------------------------- |
| No /dev/video0    | Try different USB port, check `lsusb`                     |
| Permission denied | Add user to video group: `sudo usermod -a -G video $USER` |
| Camera busy       | Stop other processes: `sudo fuser -k /dev/video0`         |
| Low framerate     | Lower resolution or use MJPEG format                      |
| Black screen      | Check cable, try powered USB hub                          |

### Switching Between Demo and Live Mode

To switch between demo video and USB camera:

```bash
# For demo mode (video file)
sudo ln -sf /opt/smart-cat-feeder/rtsp_server.py /opt/smart-cat-feeder/active_rtsp.py

# For live mode (USB camera)
sudo ln -sf /opt/smart-cat-feeder/rtsp_usb_camera.py /opt/smart-cat-feeder/active_rtsp.py

# Restart service
sudo systemctl restart smart-cat-feeder-camera
```

---

## Security Hardening

### For Production Deployment

#### 1. MQTT Authentication

```bash
# Create password file
sudo mosquitto_passwd -c /etc/mosquitto/passwd gateway
# Enter password when prompted

sudo mosquitto_passwd /etc/mosquitto/passwd esp8266
# Enter password when prompted

# Update Mosquitto config
sudo nano /etc/mosquitto/conf.d/smart_cat_feeder.conf
```

Change to:

```conf
listener 1883
allow_anonymous false
password_file /etc/mosquitto/passwd
```

Update ESP8266 code:

```cpp
// In connectMQTT()
mqttClient.connect(MQTT_CLIENT_ID, "esp8266", "your_password")
```

Update gateway.py:

```python
self.mqtt_client.username_pw_set("gateway", "your_password")
```

#### 2. Firewall Configuration

```bash
# Install ufw
sudo apt install ufw

# Default deny incoming
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH
sudo ufw allow 22/tcp

# Allow MQTT (local only - from your subnet)
sudo ufw allow from 192.168.1.0/24 to any port 1883

# Allow RTSP (local only)
sudo ufw allow from 192.168.1.0/24 to any port 8554

# Enable firewall
sudo ufw enable
```

#### 3. Secure Firebase Rules

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // User data - strict ownership
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;

      match /commands/{commandId} {
        allow read, write: if request.auth != null && request.auth.uid == userId;
        // Commands expire after 5 minutes
        allow read: if resource.data.timestamp > request.time - duration.value(5, 'm');
      }

      match /feeder/{docId} {
        allow read, write: if request.auth != null && request.auth.uid == userId;
      }

      match /feeding_logs/{logId} {
        allow read: if request.auth != null && request.auth.uid == userId;
        allow create: if request.auth != null && request.auth.uid == userId;
        // Prevent modification of logs
        allow update, delete: if false;
      }

      match /schedules/{scheduleId} {
        allow read, write: if request.auth != null && request.auth.uid == userId;
      }

      match /fcm_tokens/{tokenId} {
        allow read, write: if request.auth != null && request.auth.uid == userId;
      }
    }
  }
}
```

#### 4. Rotate Firebase Service Account Key

1. Generate new key in Firebase Console
2. Upload to Orange Pi
3. Restart gateway service
4. Delete old key from Firebase Console

---

## Quick Reference Card

### Service Commands

```bash
# Camera service
sudo systemctl start|stop|restart|status smart-cat-feeder-camera

# Gateway service
sudo systemctl start|stop|restart|status smart-cat-feeder-gateway

# MQTT broker
sudo systemctl start|stop|restart|status mosquitto
```

### Log Files

```bash
# Camera logs
sudo tail -f /var/log/smart-cat-feeder-camera.log

# Gateway logs
sudo tail -f /var/log/smart-cat-feeder-gateway.log

# MQTT logs
sudo tail -f /var/log/mosquitto/mosquitto.log
```

### MQTT Debugging

```bash
# Subscribe to all topics
mosquitto_sub -h localhost -t '#' -v

# Publish test message
mosquitto_pub -h localhost -t 'feeder/control/dispense' \
  -m '{"command":"feed","amount":50}'
```

### Test URLs

```bash
# Camera stream
rtsp://192.168.1.100:8554/live

# MQTT broker
mqtt://192.168.1.100:1883
```

---

## Support and Resources

### Project Files

| Location                             | Contents                      |
| ------------------------------------ | ----------------------------- |
| `iot/esp8266/smart_cat_feeder/`      | Arduino sketch                |
| `iot/orangepi/`                      | Gateway scripts, setup script |
| `smart-cat-feeder-fns/`              | Cloud Functions               |
| `lib/providers/feeder_provider.dart` | App IoT integration           |

### External Documentation

- [Orange Pi 3B Official Page](http://www.orangepi.org/html/hardWare/computerAndMicrocontrollers/service-and-support/Orange-Pi-3B.html) - Downloads and documentation
- [Orange Pi 3B User Manual](http://www.orangepi.org/html/hardWare/computerAndMicrocontrollers/service-and-support/Orange-Pi-3B.html) - Official user guide PDF
- [ESP8266 Arduino Core](https://arduino-esp8266.readthedocs.io/)
- [PubSubClient Library](https://pubsubclient.knolleary.net/)
- [Mosquitto Documentation](https://mosquitto.org/documentation/)
- [Firebase Admin SDK](https://firebase.google.com/docs/admin/setup)
- [GStreamer Documentation](https://gstreamer.freedesktop.org/documentation/)

---

*Last updated: Phase 3 Implementation - Smart Cat Feeder IoT/WSN Project*
