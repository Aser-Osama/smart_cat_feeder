# ESP-NOW Fixed Channel Test

Tests ESP-NOW communication with **fixed channel** approach - works with or without WiFi!

## Purpose

Verify that:
1. Two ESP8266s can communicate via ESP-NOW using a fixed channel
2. Channel is correctly set even when WiFi is disconnected
3. Messages include channel info for verification

## Configuration

Edit `fixed_channel_test.ino`:

```cpp
#define NODE_ID 'W'              // 'W' for node 1, 'X' for node 2
#define WIFI_MODE true           // true = try WiFi, false = ESP-NOW only
#define FIXED_CHANNEL 11         // MUST MATCH ON ALL NODES!
```

## Test Scenarios

### Test 1: Both nodes with WiFi
1. Set `WIFI_MODE = true` on both nodes
2. Flash node W and node X
3. Both should connect to WiFi and use WiFi's channel
4. Verify they discover each other and exchange data

### Test 2: Both nodes WITHOUT WiFi (pure ESP-NOW)
1. Set `WIFI_MODE = false` on both nodes
2. Ensure `FIXED_CHANNEL` is the same (e.g., 11)
3. Flash both nodes
4. They should communicate via fixed channel only

### Test 3: Mixed mode (one with WiFi, one without)
1. Node W: `WIFI_MODE = true`
2. Node X: `WIFI_MODE = false`
3. **IMPORTANT**: `FIXED_CHANNEL` must match your WiFi router's channel!
4. Flash both nodes
5. They should still communicate

## Expected Output

When receiving a message:
```
╔══════════════════════════════════════════════════════╗
║ 📡 RECEIVED from Node X                              ║
║   Their channel: 11                                  ║
║   My channel:    11                                  ║
║   ✅ CHANNELS MATCH - ESP-NOW WORKING!               ║
╚══════════════════════════════════════════════════════╝
```

Status output:
```
╔══════════════════════════════════════════════════════╗
║              FIXED CHANNEL TEST STATUS               ║
╠══════════════════════════════════════════════════════╣
║ Node: W | Channel: 11 (FIXED)                        ║
║ WiFi: DISABLED                                       ║
║ TX:   15 (OK:  14 FAIL:   1) | RX:   12              ║
╠══════════════════════════════════════════════════════╣
║ Peers:                                               ║
║   [X] ch:11 48:55:19:15:48:FD (2s ago)               ║
╚══════════════════════════════════════════════════════╝
```

## How to Find Your WiFi Channel

If using mixed mode, you need to set `FIXED_CHANNEL` to your router's channel:

**Linux:**
```bash
iwlist wlan0 channel | grep Current
# or
nmcli -f SSID,CHAN dev wifi
```

**From ESP8266 (when connected to WiFi):**
The serial output shows: `[WIFI] Channel: 11`

## Key Code Points

1. **Setting channel without WiFi:**
   ```cpp
   wifi_set_channel(FIXED_CHANNEL);  // ESP8266 SDK function
   ```

2. **Reading current channel:**
   ```cpp
   uint8_t ch = wifi_get_channel();  // Works even without WiFi
   ```

3. **Channel in messages:**
   ```cpp
   msg.channel = getActualChannel();  // Include for verification
   ```

## Troubleshooting

**No communication:**
- Check both nodes have same `FIXED_CHANNEL`
- Verify with serial output that actual channel matches

**Channel mismatch warning:**
- If using WiFi on one node, ensure `FIXED_CHANNEL` matches router's channel
- Change router channel or update `FIXED_CHANNEL`
