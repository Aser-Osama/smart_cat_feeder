# 🎓 Campus Demo Guide

## What You Need to Bring

- [ ] Laptop (with Arduino IDE + Flutter installed)
- [ ] Orange Pi 3B + power adapter
- [ ] ESP8266 NodeMCU + USB cable
- [ ] Phone (with app installed or USB cable to install)
- [ ] Mobile hotspot (phone or portable router)

---

## Pre-Demo Setup (Do at Home)

### 1. Note Your Hotspot Credentials
```
Hotspot Name: ________________
Hotspot Password: ________________
```

### 2. Pre-configure Orange Pi for Hotspot

```bash
ssh root@192.168.100.135

# Add hotspot as known network (won't connect yet, just saves it)
nmcli connection add type wifi con-name "campus-hotspot" \
  ssid "YOUR_HOTSPOT_NAME" \
  wifi-sec.key-mgmt wpa-psk \
  wifi-sec.psk "YOUR_HOTSPOT_PASSWORD"
```

### 3. Install App on Phone (See Section Below)

---

## On Campus Setup (10-15 min)

### Step 1: Start Hotspot
Turn on mobile hotspot on your phone (or portable router).

### Step 2: Connect Orange Pi

**Option A: If you have monitor/keyboard:**
```bash
# Login and connect
nmcli device wifi connect "YOUR_HOTSPOT" password "YOUR_PASSWORD"
ip addr show wlan0 | grep "inet "  # Note the IP!
```

**Option B: Blind connect (if pre-configured):**
1. Power on Orange Pi
2. Wait 1-2 minutes
3. Check hotspot's connected devices list for Orange Pi's IP

### Step 3: Verify Orange Pi Services

```bash
ssh root@ORANGE_PI_IP

# Check services are running
systemctl status mosquitto scf-gateway

# If not running:
systemctl start mosquitto scf-gateway

# Watch logs
journalctl -u scf-gateway -f
```

### Step 4: Update & Flash ESP8266

On your laptop, edit `smart_cat_feeder.ino`:

```cpp
const char* WIFI_SSID     = "YOUR_HOTSPOT";
const char* WIFI_PASSWORD = "YOUR_HOTSPOT_PASSWORD";
const char* MQTT_BROKER   = "ORANGE_PI_IP";  // From step 2
```

Upload via Arduino IDE (select correct COM port).

### Step 5: Verify Everything Works

Watch Orange Pi logs:
```bash
ssh root@ORANGE_PI_IP "journalctl -u scf-gateway -f"
```

You should see:
- `✅ MQTT connected`
- `💓 Heartbeat sent` (from ESP8266)

---

## Demo Flow Script

### 1. Show Architecture (1 min)
> "This is a Smart Cat Feeder IoT system with 3 components:
> - ESP8266 microcontroller (sensors + actuator)
> - Orange Pi gateway (MQTT broker + Firebase bridge)  
> - Flutter mobile app (user interface)"

### 2. Demo Cat Detection (1 min)
1. Open app on phone → Home screen
2. Press button on ESP8266
3. Show notification arriving on phone
4. Show "Cat Detected" status in app

### 3. Demo Manual Feeding (1 min)
1. Tap "Feed Now" in app
2. Show LED turning on (3 seconds)
3. Show feeding logged in history

### 4. Demo Scheduled Feeding (1 min)
1. Create schedule for 1 minute from now
2. Wait for it to trigger automatically
3. Show LED activates without touching app

### 5. Show Firebase Console (optional, 1 min)
1. Open Firebase Console on laptop
2. Show real-time data updates in Firestore
3. Show Cloud Functions logs

---

## Troubleshooting On-Site

| Issue | Quick Fix |
|-------|-----------|
| ESP8266 won't connect to WiFi | Check Serial Monitor, verify credentials |
| No MQTT messages | `systemctl restart mosquitto` on Orange Pi |
| App not receiving updates | Check internet on phone, Firebase console |
| Gateway not forwarding | `systemctl restart scf-gateway` |
| LED not blinking | Check USB power, try different port |

### Emergency Reset

```bash
# On Orange Pi - restart everything
systemctl restart mosquitto scf-gateway

# On ESP8266 - press RST button or replug USB
```

---

## Quick Test Checklist

- [ ] Hotspot is on
- [ ] Orange Pi connected to hotspot (check IP)
- [ ] Mosquitto running: `systemctl status mosquitto`
- [ ] Gateway running: `systemctl status scf-gateway`
- [ ] ESP8266 connected (Serial shows "MQTT connected")
- [ ] App logged in and showing home screen
- [ ] Button press → notification received
- [ ] Feed Now → LED turns on

---

## IP Quick Reference

Fill in on campus:

```
Hotspot Gateway: 192.168.___.___ (usually .43.1 for Android)
Orange Pi IP:    192.168.___.___
ESP8266 IP:      192.168.___.___  (check Serial Monitor)
```


