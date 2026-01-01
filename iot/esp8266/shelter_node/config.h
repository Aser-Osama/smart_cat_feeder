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
#define NODE_ID 'W'  // Change to 'X', 'Y', or 'Z' for other nodes

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
//   GPIO0  (D3) - Must be HIGH for normal boot (LOW = flash mode) ❌ AVOID
//   GPIO2  (D4) - Must be HIGH for normal boot, has built-in LED  ❌ AVOID
//   GPIO15 (D8) - Must be LOW for normal boot (internal pull-down) ❌ AVOID
//   GPIO16 (D0) - Used for deep sleep wake, no PWM/interrupts      ⚠️ LIMITED
//   GPIO1  (TX) - Serial output, needed for debugging              ❌ AVOID
//   GPIO3  (RX) - Serial input, boot issues                        ❌ AVOID
//
// ✅ SAFE GPIOs for general use: 4 (D2), 5 (D1), 12 (D6), 13 (D7), 14 (D5)
//
// ============================================================================

// Ultrasonic Sensor (HC-SR04) - ACTIVE HIGH trigger pulse
#define ULTRASONIC_TRIG_PIN  14  // D5 ✅ Safe GPIO
#define ULTRASONIC_ECHO_PIN  12  // D6 ✅ Safe GPIO

// Color Sensor (TCS3200/HW-531) - SIMPLIFIED for RED detection
// -------------------------------------------------------------------------
// WIRING SIMPLIFICATION: Detect RED food (kibble) instead of brown!
// Hardwire S2 and S3 to GND = Red filter permanently selected
// This saves 2 GPIO pins and simplifies code.
//
// HARDWARE WIRING:
//   S2 -> GND (hardwired, no GPIO needed)
//   S3 -> GND (hardwired, no GPIO needed)
//   S0 -> D1 (GPIO5)  - Frequency scaling HIGH
//   S1 -> D2 (GPIO4)  - Frequency scaling LOW = 2% duty cycle
//   OUT-> D7 (GPIO13) - Frequency output
//   VCC-> 3.3V
//   GND-> GND
// -------------------------------------------------------------------------
#define COLOR_S0_PIN         5   // D1 ✅ Safe - Frequency scaling (HIGH)
#define COLOR_S1_PIN         4   // D2 ✅ Safe - Frequency scaling (LOW for 2%)
#define COLOR_OUT_PIN        13  // D7 ✅ Safe - Frequency output
// S2/S3 hardwired to GND - no GPIO pins needed!

// Status LED
#define STATUS_LED_PIN       16  // D0 - Works for OUTPUT only (no PWM, no INPUT_PULLUP)

// ============================================================================
// SENSOR THRESHOLDS
// ============================================================================
// Ultrasonic - cat presence detection
#define CAT_PRESENCE_THRESHOLD_CM   30.0   // Cat detected if < 30cm
#define ULTRASONIC_MAX_DISTANCE_CM  400.0  // Max sensor range
#define ULTRASONIC_MIN_DISTANCE_CM  2.0    // Min sensor range

// Color sensor - RED food detection (simplified from brown)
// -------------------------------------------------------------------------
// Using RED kibble/food for simpler detection:
// - Only need red channel (S2=LOW, S3=LOW hardwired)
// - Higher frequency = less red light reflected = darker/empty
// - Lower frequency = more red light reflected = red food present
// -------------------------------------------------------------------------
#define COLOR_FOOD_PRESENT_THRESHOLD  50   // Pulse count below this = RED food present
#define COLOR_PLATE_EMPTY_THRESHOLD   150  // Pulse count above this = empty/no red

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
#define RSSI_WEIGHT                0.4     // Weight for RSSI in routing score
#define BATTERY_WEIGHT             0.6     // Weight for battery in routing score
#define RSSI_CHANGE_THRESHOLD      10      // dBm change to trigger route update

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
#define ESPNOW_FIXED_CHANNEL       11      // Fixed channel when WiFi disconnected (1-13)
                                           // MUST match your WiFi AP's channel for coexistence!
#define ESPNOW_DISCOVERY_INTERVAL  5000    // Send discovery every 5 seconds
#define ESPNOW_DATA_FORWARD_TTL    3       // Max hops for forwarded messages
#define ESPNOW_PEER_TIMEOUT_MS     60000   // Peer expires after 60s no contact
#define MAX_ESPNOW_PEERS           4       // Max ESP-NOW peers (W, X, Y, Z)

// ESP-NOW Message Types
#define MSG_TYPE_DISCOVERY         1
#define MSG_TYPE_ACK               2
#define MSG_TYPE_TELEMETRY         3
#define MSG_TYPE_ALERT             4
#define MSG_TYPE_ROUTING           5

// ============================================================================
// DEBUG FLAGS
// ============================================================================
#define DEBUG_SENSORS              1
#define DEBUG_ROUTING              1
#define DEBUG_BATTERY              1
#define DEBUG_MQTT                 1
#define DEBUG_ESPNOW               1

#endif // CONFIG_H
