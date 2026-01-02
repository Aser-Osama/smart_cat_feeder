/**
 * Shelter Node Configuration
 * ==========================
 * 
 * IMPORTANT: Change NODE_ID for each physical node before flashing!
 * Valid IDs: 'W', 'X', 'Y', 'Z'
 */

#ifndef CONFIG_H
#define CONFIG_H

// ============================================================================
// NODE IDENTITY - CHANGE THIS FOR EACH NODE
// ============================================================================
#define NODE_ID 'Y'  // Change to 'W', 'X', 'Y', or 'Z' for other nodes

// ============================================================================
// MULTI-HOP DEMO MODE
// ============================================================================
// Set to 1 to force this node to NEVER send directly to MQTT sink
// It will always route via ESP-NOW peers (for demonstrating multi-hop)
// Only enable on nodes that have ESP-NOW peers with sink access!
#define FORCE_MULTIHOP       0   // 0=normal routing, 1=force ESP-NOW only

// ============================================================================
// WIFI CONFIGURATION
// ============================================================================
const char* WIFI_SSID     = "Aser";
const char* WIFI_PASSWORD = "1234567899abc";

// ============================================================================
// MQTT CONFIGURATION (Orange Pi Sink)
// ============================================================================
const char* MQTT_BROKER   = "172.29.32.150";  // Orange Pi IP
const int   MQTT_PORT     = 1883;

// Generate unique client ID based on node
#define MQTT_CLIENT_ID_PREFIX "shelter-node-"

// ============================================================================
// MQTT TOPICS
// ============================================================================
// Node -> Sink
#define TOPIC_TELEMETRY_PREFIX   "shelter/node/"
#define TOPIC_TELEMETRY_SUFFIX   "/telemetry"
#define TOPIC_ROUTING_SUFFIX     "/routing"
#define TOPIC_ALERT_SUFFIX       "/alert"

// Inter-node routing
#define TOPIC_MESH_FORWARD       "shelter/mesh/forward"
#define TOPIC_MESH_NEIGHBOR      "shelter/mesh/neighbor"

// Sink -> Nodes
#define TOPIC_BROADCAST_CONFIG   "shelter/broadcast/config"

// ============================================================================
// PIN DEFINITIONS (NodeMCU ESP8266)
// ============================================================================
// 
// ESP8266 Boot Pin Requirements (ACTIVE AT POWER-ON):
//   GPIO0  (D3) - Must be HIGH for normal boot (LOW = flash mode) - AVOID
//   GPIO2  (D4) - Must be HIGH for normal boot, has built-in LED  - AVOID
//   GPIO15 (D8) - Must be LOW for normal boot (internal pull-down) - AVOID
//   GPIO16 (D0) - Used for deep sleep wake, no PWM/interrupts      - LIMITED
//   GPIO1  (TX) - Serial output, needed for debugging              - AVOID
//   GPIO3  (RX) - Serial input, boot issues                        - AVOID
//
// SAFE GPIOs for general use: 4 (D2), 5 (D1), 12 (D6), 13 (D7), 14 (D5)
//
// ============================================================================

// Ultrasonic Sensor (HC-SR04) - ACTIVE HIGH trigger pulse
#define ULTRASONIC_TRIG_PIN  14  // D5 - Safe GPIO
#define ULTRASONIC_ECHO_PIN  12  // D6 - Safe GPIO (reliable, no boot issues)

// Color Sensor (TCS3200/HW-531) - FULL RGB for BROWN detection
// -------------------------------------------------------------------------
// BROWN FOOD DETECTION: Properly detect brown cat food using RGB channels
// Brown = low-medium red, low-medium green, very low blue
// All 5 control pins needed for full RGB reading
//
// HARDWARE WIRING (BOOT-SAFE GPIO ONLY - NO GPIO15!):
//   S0 -> D1 (GPIO5)  - Frequency scaling HIGH
//   S1 -> D2 (GPIO4)  - Frequency scaling HIGH = 20% duty cycle
//   S2 -> D7 (GPIO13) - Filter select bit 0
//   S3 -> D4 (GPIO2)  - Filter select bit 1 (has pull-up, OK for OUTPUT)
//   OUT-> D3 (GPIO0)  - Frequency output (OK after boot)
//   VCC-> 3.3V
//   GND-> GND
//
// NOTE: GPIO0 (OUT) and GPIO2 (S3) are used as OUTPUT after boot - safe!
// GPIO0 must be HIGH at boot (not driven during boot, INPUT)
// GPIO2 must be HIGH at boot (has pull-up, not driven during boot)
// -------------------------------------------------------------------------
#define COLOR_S0_PIN         5   // D1 - Safe - Frequency scaling (HIGH)
#define COLOR_S1_PIN         4   // D2 - Safe - Frequency scaling (LOW for 2%)
#define COLOR_S2_PIN         13  // D7 - Safe - Filter select S2
#define COLOR_S3_PIN         2   // D4 - GPIO2 - OUTPUT after boot (has pull-up, safe)
#define COLOR_OUT_PIN        0   // D3 - GPIO0 - INPUT after boot (OK, just don't pull LOW)

// Status LED
#define STATUS_LED_PIN       16  // D0 - Works for OUTPUT only (no PWM, no INPUT_PULLUP)

// ============================================================================
// SENSOR THRESHOLDS
// ============================================================================
// Ultrasonic - cat presence detection
#define CAT_PRESENCE_THRESHOLD_CM   30.0   // Cat detected if < 30cm
#define ULTRASONIC_MAX_DISTANCE_CM  400.0  // Max sensor range
#define ULTRASONIC_MIN_DISTANCE_CM  2.0    // Min sensor range

// Color sensor - Brown food detection (full RGB mode)
// -------------------------------------------------------------------------
// Detection logic using RGB channels to detect brown cat food
// Brown characteristics (calibrated for 20% frequency with actual readings):
// - Red: 200-1200 (medium-high red component)
// - Green: 150-1000 (medium-high green component)  
// - Blue: 100-950 (medium, but MUST be <= green for brown)
// - Green/Red ratio: 0.65-1.0 (brown has slightly more red than green)
// - Blue must NOT exceed green (key brown indicator)
//
// Empty plate detection:
// - Any channel below 150 = very dark surface = empty
// - OR blue > green (glossy/blue tint) = not brown
// -------------------------------------------------------------------------
#define COLOR_BROWN_RED_MIN          200   // Min red for brown food
#define COLOR_BROWN_RED_MAX          1200  // Max red for brown food
#define COLOR_BROWN_GREEN_MIN        150   // Min green for brown food
#define COLOR_BROWN_GREEN_MAX        1000  // Max green for brown food
#define COLOR_BROWN_BLUE_MIN         100   // Min blue for brown food
#define COLOR_BROWN_BLUE_MAX         950   // Max blue for brown food (but must be < green)
#define COLOR_DARK_THRESHOLD         150   // Below this = too dark = empty
#define COLOR_GREEN_RED_RATIO_MIN    0.65  // Min green/red ratio for brown
#define COLOR_GREEN_RED_RATIO_MAX    1.0   // Max green/red ratio for brown

// ============================================================================
// TIMING CONFIGURATION
// ============================================================================
#define SENSOR_READ_INTERVAL_MS    10000   // Read sensors every 10 seconds
#define TELEMETRY_INTERVAL_MS      10000   // Send telemetry every 10 seconds
#define ROUTING_UPDATE_INTERVAL_MS 30000   // Update routing every 30 seconds
#define NEIGHBOR_BEACON_INTERVAL_MS 15000  // Send neighbor beacon every 15 seconds
#define HEARTBEAT_INTERVAL_MS      30000   // Heartbeat every 30 seconds

// ============================================================================
// ROUTING CONFIGURATION
// ============================================================================
#define MAX_HOP_COUNT              4       // Maximum hops to sink
#define RSSI_WEIGHT                0.5     // Weight for link quality in routing score (increased for path quality)
#define BATTERY_WEIGHT             0.5     // Weight for battery in routing score
#define RSSI_CHANGE_THRESHOLD      10      // dBm change to trigger route update

// Path quality algorithm tuning
#define MULTIHOP_STRONG_LINK_BONUS 0.05    // Bonus when both links > -55dBm (good dual-link)
#define MULTIHOP_HOP_PENALTY       0.03    // Penalty for extra hop (latency, reliability)
#define ESTIMATED_ESPNOW_RSSI      -55     // Estimated ESP-NOW link quality (dBm) when we can receive peer

// ============================================================================
// BATTERY SIMULATION
// ============================================================================
#define BATTERY_CAPACITY_MAH       2000.0  // 18650 cell capacity
#define INITIAL_BATTERY_PERCENT    85.0    // Starting battery (randomize in code)

// Current draw estimates (mA)
#define CURRENT_IDLE_MA            80.0
#define CURRENT_WIFI_TX_MA         170.0
#define CURRENT_WIFI_RX_MA         50.0
#define CURRENT_SENSOR_MA          15.0

// Timing for drain calculation (seconds)
#define CYCLE_DURATION_SEC         10.0
#define SENSOR_READ_DURATION_SEC   0.2
#define WIFI_TX_DURATION_SEC       0.05
#define WIFI_RX_DURATION_SEC       0.1

// ============================================================================
// ESP-NOW CONFIGURATION
// ============================================================================
#define ESPNOW_ENABLED             1       // Enable real ESP-NOW mesh
#define ESPNOW_FIXED_CHANNEL       11      // Fallback channel (match your WiFi AP!)
                                           // MUST match your WiFi AP's channel for coexistence!
#define ESPNOW_DISCOVERY_INTERVAL  5000    // Send discovery every 5 seconds
#define ESPNOW_DATA_FORWARD_TTL    3       // Max hops for forwarded messages
#define ESPNOW_PEER_TIMEOUT_MS     60000   // Peer expires after 60s no contact
#define MAX_ESPNOW_PEERS           4       // Max ESP-NOW peers (W, X, Y, Z)

// Channel scanning for WiFi-less mode
#define ESPNOW_CHANNEL_SCAN        1       // Enable channel scanning when WiFi disconnected
#define ESPNOW_SCAN_CHANNELS       {11, 6, 1}  // Scan 11 first (most common), then 6, then 1
#define ESPNOW_SCAN_CHANNELS_COUNT 3       // Number of channels to scan
#define ESPNOW_SCAN_DWELL_MS       6000    // 6s per channel (peers beacon every 5s)
#define ESPNOW_SCAN_INTERVAL_MS    30000   // Re-scan every 30s if no peers found
#define ESPNOW_SCAN_DISCOVERIES    6       // Send discovery every second during scan

// ESP-NOW Message Types
#define MSG_TYPE_DISCOVERY         1
#define MSG_TYPE_ACK               2
#define MSG_TYPE_TELEMETRY         3
#define MSG_TYPE_ALERT             4
#define MSG_TYPE_ROUTING           5

// ============================================================================
// DEBUG FLAGS
// ============================================================================
// MASTER DEBUG SWITCH - Set to 0 for production/reliability, 1 for debugging
#define DEBUG_LOGGING              1       // 0=minimal logs (reliable), 1=verbose logs

#define DEBUG_SENSORS              1
#define DEBUG_ROUTING              0
#define DEBUG_BATTERY              0
#define DEBUG_MQTT                 0
#define DEBUG_ESPNOW               0       // ESP-NOW verbose logging (expensive!)

// ============================================================================
// RELIABILITY CONFIGURATION
// ============================================================================
#define ESPNOW_DATA_RETRIES        2       // Retries for data messages (reduced for speed)
#define ESPNOW_RETRY_DELAY_MS      30      // Delay between retries (reduced)
#define ESPNOW_DATA_ACK_TIMEOUT_MS 150     // Timeout waiting for data ACK (reduced)
#define MSG_TYPE_DATA_ACK          6       // ACK for data messages
#define WATCHDOG_YIELD_INTERVAL    5       // yield() every N ms in tight loops

// ============================================================================
// LOGGING HELPER - Prefix all logs with node ID
// Conditional logging to reduce blocking Serial operations
// ============================================================================
#if DEBUG_LOGGING
  #define LOG_PREFIX()             Serial.printf("[Node %c] ", NODE_ID)
  #define LOGF(fmt, ...)           do { Serial.printf("[Node %c] " fmt, NODE_ID, ##__VA_ARGS__); } while(0)
  #define LOGLN(msg)               do { Serial.print("[Node "); Serial.print((char)NODE_ID); Serial.print("] "); Serial.println(msg); } while(0)
#else
  // Minimal logging - only critical messages
  #define LOG_PREFIX()             ((void)0)
  #define LOGF(fmt, ...)           ((void)0)
  #define LOGLN(msg)               ((void)0)
#endif

// Always-on logging for critical errors and key events (even in production)
#define LOG_CRITICAL(fmt, ...)     do { Serial.printf("[Node %c] " fmt, NODE_ID, ##__VA_ARGS__); } while(0)
#define LOG_EVENT(msg)             do { Serial.print("[Node "); Serial.print((char)NODE_ID); Serial.print("] "); Serial.println(msg); } while(0)

#endif // CONFIG_H
