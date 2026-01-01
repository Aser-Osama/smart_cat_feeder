# ESP-NOW Standalone Test

This is a **minimal, independent test** to verify ESP-NOW direct communication between two ESP8266 boards works before integrating into the main project.

## What This Proves

✅ Two ESPs can communicate **directly** without WiFi/router/MQTT  
✅ Messages are delivered with low latency (~1-5ms)  
✅ Range is confirmed (test at various distances)  
✅ Data integrity (struct arrives intact)  

## Hardware Needed

- 2x ESP8266 boards (NodeMCU, Wemos D1 Mini, etc.)
- 2x USB cables
- Computer with Arduino IDE

## Quick Start

### Step 1: Flash the RECEIVER first

1. Open `receiver.ino` in Arduino IDE
2. Select correct board: **NodeMCU 1.0 (ESP-12E Module)**
3. Select correct port
4. Upload
5. Open Serial Monitor (115200 baud)
6. **Copy the MAC address** shown

### Step 2: Update and flash the SENDER

1. Open `sender.ino` in Arduino IDE
2. Find this line:
   ```cpp
   uint8_t RECEIVER_MAC[] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
   ```
3. Replace with the MAC from receiver, e.g.:
   ```cpp
   uint8_t RECEIVER_MAC[] = {0x2C, 0x3A, 0xE8, 0x12, 0x34, 0x56};
   ```
4. Upload to second ESP8266
5. Open Serial Monitor

### Step 3: Observe

**SENDER output:**
```
📦 Sending message #1
   Node: SND, Value: 45.3, Time: 3001 ms
📤 Message #1 → ✅ DELIVERED
   Stats: 1 sent, 1 delivered, 0 failed (100.0% success)
```

**RECEIVER output:**
```
═══════════════════════════════════════════════════════
📨 RECEIVED MESSAGE #1
═══════════════════════════════════════════════════════
   From MAC: 2C:3A:E8:XX:XX:XX
   Node ID:     SND
   Sensor Val:  45.3
   Sender Time: 3001 ms
   Data Size:   16 bytes
───────────────────────────────────────────────────────
📊 Stats: 1 received, 0 missed (100.0% success)
```

## How to Prove It's NOT Using WiFi

1. **No WiFi credentials** are in the code
2. **Disconnect your router** - it still works!
3. **Check WiFi.status()** - it shows disconnected
4. The sender prints "DELIVERED" only when receiver ACKs directly via ESP-NOW
5. Move the boards to a location with no WiFi - still works

## Testing Range

1. Start with both boards on your desk
2. Move them apart gradually
3. Watch success rate - ESP-NOW typically works up to **200m line-of-sight**
4. Indoor range is typically 50-100m depending on walls

## Expected Performance

| Metric | Expected Value |
|--------|---------------|
| Latency | 1-5 ms |
| Max payload | 250 bytes |
| Max peers | 20 (encrypted) / 6 (encrypted + paired) |
| Range (indoor) | 50-100m |
| Range (outdoor) | up to 200m |

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "ESP-NOW init failed" | Make sure WiFi.mode(WIFI_STA) is called first |
| No messages received | Check MAC address is correct (copy exactly) |
| "FAILED" on sender | Receiver not running, wrong MAC, or out of range |
| Intermittent failures | Move closer, check for interference |

## Next Steps

Once this test works, you can:
1. Integrate ESP-NOW into `shelter_node.ino` alongside MQTT
2. Use ESP-NOW for inter-ESP communication
3. Fall back to MQTT (via Orange Pi) when ESP-NOW fails

## Code Structure

```
espnow_test/
├── sender.ino              # Manual test - sender (requires MAC config)
├── receiver.ino            # Manual test - receiver 
├── auto_discovery_node.ino # ⭐ AUTO MODE - no MAC config needed!
└── README.md               # This file
```

---

# ⭐ AUTO-DISCOVERY MODE (Recommended for Production)

## Why Auto-Discovery?

| Manual Mode | Auto-Discovery Mode |
|-------------|---------------------|
| Must copy MAC addresses | No MAC configuration |
| Sender/receiver are different | Same code on all nodes |
| Static peer list | Dynamic peer discovery |
| Breaks if ESP replaced | New ESPs auto-join |

## How It Works

```
┌──────────┐   BROADCAST    ┌──────────┐
│  Node W  │ ─────────────► │  Node X  │
│          │ ◄───────────── │          │
└──────────┘   DISCOVERY    └──────────┘
     │              ACK           │
     │                            │
     ▼                            ▼
  Adds X to                   Adds W to
  peer table                  peer table
     │                            │
     └──────── SENSOR DATA ───────┘
              (direct unicast)
```

## Quick Start (Auto Mode)

### For ALL Nodes:

1. Open `auto_discovery_node.ino`
2. Change only ONE line per device:
   ```cpp
   #define NODE_ID 'W'  // Change to 'X', 'Y', 'Z' for other nodes
   ```
3. Flash to each ESP8266
4. Done! They find each other automatically.

## Sample Output

```
╔══════════════════════════════════════════════════════╗
║     ESP-NOW AUTO-DISCOVERY NODE                      ║
╚══════════════════════════════════════════════════════╝
📍 This is Node: W
📍 MAC Address: 2C:3A:E8:12:34:56
✅ ESP-NOW initialized

🔍 Starting peer discovery...
📢 Discovery broadcast sent (Node W)
📡 Discovery from Node X
✅ NEW PEER: Node X at 2C:3A:E8:78:9A:BC (RSSI: -45)

┌─────────────────────────────────────────────────┐
│              DISCOVERED PEERS                   │
├──────┬───────────────────┬───────┬───────┬───────┤
│ Node │ MAC Address       │ RSSI  │ Batt  │ Seen  │
├──────┼───────────────────┼───────┼───────┼───────┤
│  X   │ 2C:3A:E8:78:9A:BC │  -45  │  82%  │   2s  │
│  Y   │ 2C:3A:E8:AA:BB:CC │  -52  │  91%  │   4s  │
└──────┴───────────────────┴───────┴───────┴───────┘

📤 Sent data #1 to Node X
📤 Sent data #1 to Node Y
═══════════════════════════════════════════════════
📨 SENSOR DATA from Node X (msg #3)
   Value: 67.30
═══════════════════════════════════════════════════
```

## Proving Auto-Discovery Works

1. Power on Node W alone → no peers
2. Power on Node X → both discover each other in ~5 seconds
3. Power on Node Y → all three now connected
4. Power off Node X → W and Y still connected, X removed after 30s timeout
5. Power on Node X again → rejoins automatically
