# 🔄 Quick Network Switch Guide

## Current Saved Configs

| Network | WiFi SSID | WiFi Password | Orange Pi IP |
|---------|-----------|---------------|--------------|
| **Home** | `OB_2.4GHz` | `Barawy_110624` | `192.168.100.135` |
| **Hotspot** | `__________` | `__________` | `__________` |

> Fill in hotspot row after first setup!

---

## Switching to Hotspot

### Step 1: Get Orange Pi's New IP

```bash
# SSH while still on home WiFi
ssh root@192.168.100.135

# Connect to hotspot
nmcli device wifi connect "YOUR_HOTSPOT_NAME" password "YOUR_PASSWORD"

# Get new IP (write it down!)
ip addr show wlan0 | grep "inet "
```

### Step 2: Update ESP8266

Open `smart_cat_feeder/iot/esp8266/smart_cat_feeder/smart_cat_feeder.ino`

Change these lines (~line 33-37):

```cpp
const char* WIFI_SSID     = "YOUR_HOTSPOT_NAME";
const char* WIFI_PASSWORD = "YOUR_HOTSPOT_PASSWORD";
const char* MQTT_BROKER   = "192.168.43.XXX";  // Orange Pi's hotspot IP
```

**Upload to ESP8266** via Arduino IDE.

### Step 3: Verify

```bash
# SSH to Orange Pi using new IP
ssh root@NEW_IP

# Watch for ESP8266 connection
journalctl -u scf-gateway -f
```

---

## Switching Back to Home WiFi

### Step 1: Reconnect Orange Pi

```bash
ssh root@HOTSPOT_IP
nmcli device wifi connect "OB_2.4GHz" password "Barawy_110624"
```

### Step 2: Update ESP8266

```cpp
const char* WIFI_SSID     = "OB_2.4GHz";
const char* WIFI_PASSWORD = "Barawy_110624";
const char* MQTT_BROKER   = "192.168.100.135";
```

**Upload to ESP8266.**

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Can't SSH to Orange Pi | Connect monitor+keyboard, run `ip addr` |
| ESP8266 won't connect | Check Serial Monitor (115200 baud) |
| MQTT not working | `ssh root@IP "systemctl status mosquitto"` |
| Gateway not running | `ssh root@IP "systemctl restart scf-gateway"` |

---

## Quick Commands Cheatsheet

```bash
# Check Orange Pi IP
ip addr show wlan0 | grep "inet "

# List available WiFi networks
nmcli device wifi list

# Connect to network
nmcli device wifi connect "SSID" password "PASS"

# Check services
systemctl status mosquitto scf-gateway

# Restart gateway after changes
systemctl restart scf-gateway

# Watch gateway logs
journalctl -u scf-gateway -f
```

