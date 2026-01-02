/**
 * Shelter Cat Monitoring - ESP8266 Node Firmware
 * ===============================================
 * 
 * This firmware runs on each of the 4 ESP8266 nodes (W, X, Y, Z) in the
 * shelter monitoring WSN. Each node monitors a food bowl using:
 * - Ultrasonic sensor (HC-SR04) for cat presence detection
 * - Color sensor (TCS3200) for food/empty plate detection
 * - Simulated battery for routing decisions
 * 
 * Features:
 * - Multi-hop routing based on RSSI and battery
 * - Empty plate alerts (when no cat present and plate is empty)
 * - Cat presence detection and reporting
 * - Battery simulation with realistic drain model
 * 
 * IMPORTANT: Change NODE_ID in config.h before flashing each node!
 * 
 * Communication:
 * - MQTT to Orange Pi sink (via WiFi, possibly multi-hop)
 * - Topics: shelter/node/{W,X,Y,Z}/telemetry, /routing, /alert
 * 
 * Author: Shelter Cat Monitoring System
 * Date: January 2026
 */

#include <ESP8266WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <EEPROM.h>

#include "config.h"
#include "sensors.h"
#include "battery.h"
#include "routing.h"

#if ESPNOW_ENABLED
#include "espnow_mesh.h"
#endif

// ============================================================================
// GLOBAL OBJECTS
// ============================================================================

WiFiClient wifiClient;
PubSubClient mqttClient(wifiClient);

SensorManager sensors;
BatterySimulator battery;
RoutingTable routing;

#if ESPNOW_ENABLED
ESPNowMesh espnowMesh;
unsigned long lastEspnowDiscovery = 0;
unsigned long lastEspnowStats = 0;
#endif

// Node identity
char nodeIdStr[2];
String nodeIdString;
String mqttClientId;

// Timing
unsigned long lastTelemetry = 0;
unsigned long lastSensorRead = 0;
unsigned long lastRouteUpdate = 0;
unsigned long lastNeighborBeacon = 0;
unsigned long lastHeartbeat = 0;

// State tracking
bool lastCatPresent = false;
bool lastPlateEmpty = false;
bool emptyPlateAlertSent = false;

// Runtime calibration (can be updated via MQTT)
String foodColorName = "brown";  // User-defined color name
int calibratedRedMin = COLOR_BROWN_RED_MIN;
int calibratedRedMax = COLOR_BROWN_RED_MAX;
int calibratedGreenMin = COLOR_BROWN_GREEN_MIN;
int calibratedGreenMax = COLOR_BROWN_GREEN_MAX;
int calibratedBlueMin = COLOR_BROWN_BLUE_MIN;
int calibratedBlueMax = COLOR_BROWN_BLUE_MAX;
int calibratedDarkThreshold = COLOR_DARK_THRESHOLD;
float calibratedGreenRedRatioMin = COLOR_GREEN_RED_RATIO_MIN;
float calibratedGreenRedRatioMax = COLOR_GREEN_RED_RATIO_MAX;

// MQTT topics (built dynamically)
String topicTelemetry;
String topicRouting;
String topicAlert;
String topicCalibration;

// User ID for Firebase integration (matches gateway)
const char* USER_ID = "EyrwFFoBJ8TlVFepJvqdeooOBwA2";

// EEPROM addresses for calibration persistence
#define EEPROM_SIZE 512
#define EEPROM_CALIBRATION_ADDR 0
#define EEPROM_MAGIC 0xCAFE  // Magic number to detect valid calibration

struct CalibrationData {
  uint16_t magic;  // Magic number for validation
  char colorName[32];
  int redMin;
  int redMax;
  int greenMin;
  int greenMax;
  int blueMin;
  int blueMax;
  int darkThreshold;
  float greenRedRatioMin;
  float greenRedRatioMax;
};

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

void saveCalibrationToEEPROM() {
  CalibrationData data;
  data.magic = EEPROM_MAGIC;
  strncpy(data.colorName, foodColorName.c_str(), 31);
  data.colorName[31] = '\0';
  data.redMin = calibratedRedMin;
  data.redMax = calibratedRedMax;
  data.greenMin = calibratedGreenMin;
  data.greenMax = calibratedGreenMax;
  data.blueMin = calibratedBlueMin;
  data.blueMax = calibratedBlueMax;
  data.darkThreshold = calibratedDarkThreshold;
  data.greenRedRatioMin = calibratedGreenRedRatioMin;
  data.greenRedRatioMax = calibratedGreenRedRatioMax;
  
  EEPROM.put(EEPROM_CALIBRATION_ADDR, data);
  EEPROM.commit();
  Serial.println("💾 Calibration saved to EEPROM");
}

void loadCalibrationFromEEPROM() {
  CalibrationData data;
  EEPROM.get(EEPROM_CALIBRATION_ADDR, data);
  
  if (data.magic == EEPROM_MAGIC) {
    foodColorName = String(data.colorName);
    calibratedRedMin = data.redMin;
    calibratedRedMax = data.redMax;
    calibratedGreenMin = data.greenMin;
    calibratedGreenMax = data.greenMax;
    calibratedBlueMin = data.blueMin;
    calibratedBlueMax = data.blueMax;
    calibratedDarkThreshold = data.darkThreshold;
    calibratedGreenRedRatioMin = data.greenRedRatioMin;
    calibratedGreenRedRatioMax = data.greenRedRatioMax;
    
    // Apply to sensor
    sensors.updateCalibration(
      calibratedRedMin, calibratedRedMax,
      calibratedGreenMin, calibratedGreenMax,
      calibratedBlueMin, calibratedBlueMax,
      calibratedDarkThreshold,
      calibratedGreenRedRatioMin, calibratedGreenRedRatioMax
    );
    
    Serial.print("✅ Loaded calibration from EEPROM: ");
    Serial.println(foodColorName);
  } else {
    Serial.println("ℹ️  No saved calibration found, using defaults");
  }
}

#if ESPNOW_ENABLED && FORCE_MULTIHOP
// Check if any ESP-NOW peer has sink access (for forced multi-hop mode)
bool hasOtherPeerWithSinkAccess() {
  for (int i = 0; i < MAX_ESPNOW_PEERS; i++) {
    ESPNowPeer* peers = espnowMesh.getPeers();
    if (peers[i].active && peers[i].hasSinkAccess) {
      return true;
    }
  }
  return false;
}

// Get a peer with sink access to route through
char getPeerWithSinkAccess() {
  for (int i = 0; i < MAX_ESPNOW_PEERS; i++) {
    ESPNowPeer* peers = espnowMesh.getPeers();
    if (peers[i].active && peers[i].hasSinkAccess) {
      return peers[i].nodeId;
    }
  }
  return 'S';  // Fallback to sink if no peers
}
#endif

// ============================================================================
// SETUP
// ============================================================================

void setup() {
  Serial.begin(115200);
  delay(100);
  
  Serial.println();
  Serial.println();
  Serial.println("========================================================");
  Serial.printf("    Shelter Cat Monitoring - ESP8266 Node %c\n", NODE_ID);
  Serial.println("========================================================");
  
  // Initialize node identity
  nodeIdStr[0] = NODE_ID;
  nodeIdStr[1] = '\0';
  nodeIdString = String(nodeIdStr);
  mqttClientId = String(MQTT_CLIENT_ID_PREFIX) + nodeIdString;
  
  LOGF("[INFO] Node ID: %c\n", NODE_ID);
  LOGF("[INFO] MQTT Client: %s\n", mqttClientId.c_str());
  
  // Build MQTT topics
  topicTelemetry = String(TOPIC_TELEMETRY_PREFIX) + nodeIdString + TOPIC_TELEMETRY_SUFFIX;
  topicRouting = String(TOPIC_TELEMETRY_PREFIX) + nodeIdString + TOPIC_ROUTING_SUFFIX;
  topicAlert = String(TOPIC_TELEMETRY_PREFIX) + nodeIdString + TOPIC_ALERT_SUFFIX;
  topicCalibration = String(TOPIC_TELEMETRY_PREFIX) + nodeIdString + "/config/calibration";
  
  Serial.println();
  LOGLN("[INFO] MQTT Topics:");
  LOGF("   Telemetry: %s\n", topicTelemetry.c_str());
  LOGF("   Routing:   %s\n", topicRouting.c_str());
  LOGF("   Alert:     %s\n", topicAlert.c_str());
  LOGF("   Calibration: %s\n", topicCalibration.c_str());
  
  // Initialize status LED
  pinMode(STATUS_LED_PIN, OUTPUT);
  digitalWrite(STATUS_LED_PIN, LOW);
  
  // Initialize EEPROM for calibration persistence
  EEPROM.begin(EEPROM_SIZE);
  
  // Initialize components
  Serial.println();
  LOGLN("[INFO] Initializing components...");
  
  // Sensors
  sensors.begin();
  
  // Load calibration from EEPROM (if available)
  loadCalibrationFromEEPROM();
  
  // Battery simulator with randomized initial percentage
  float initialBattery = INITIAL_BATTERY_PERCENT + random(-20, 15);
  battery.begin(initialBattery);
  
  // Routing table
  routing.begin(NODE_ID);
  
  // Connect WiFi
  setupWiFi();
  
  #if ESPNOW_ENABLED
  // Initialize ESP-NOW
  // If WiFi connected: uses WiFi's channel automatically
  // If WiFi disconnected: uses ESPNOW_FIXED_CHANNEL from config.h
  Serial.println();
  LOGLN("[INFO] Initializing ESP-NOW mesh...");
  espnowMesh.begin(NODE_ID);  // Auto-detects channel
  #endif
  
  // Setup MQTT
  mqttClient.setServer(MQTT_BROKER, MQTT_PORT);
  mqttClient.setCallback(mqttCallback);
  mqttClient.setBufferSize(1024);  // Larger buffer for JSON
  
  connectMQTT();
  
  // Initial sensor read
  Serial.println();
  LOGLN("[INFO] Initial sensor reading...");
  SensorData data = sensors.readAll();
  LOGF("   Cat present: %s\n", data.ultrasonic.catPresent ? "YES" : "NO");
  LOGF("   Plate status: %s\n", sensors.getPlateStatusString());
  
  // Blink LED to confirm setup
  for (int i = 0; i < 3; i++) {
    digitalWrite(STATUS_LED_PIN, HIGH);
    delay(150);
    digitalWrite(STATUS_LED_PIN, LOW);
    delay(150);
  }
  
  Serial.println();
  LOGLN("[OK] Setup complete! Entering main loop...");
  Serial.println();
}

// ============================================================================
// WIFI SETUP
// ============================================================================

void setupWiFi() {
  LOG_CRITICAL("[WIFI] Connecting to: %s\n", WIFI_SSID);
  
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 30) {
    // Non-blocking delay with yield
    unsigned long waitStart = millis();
    while (millis() - waitStart < 500) {
      yield();
    }
    Serial.print(".");
    digitalWrite(STATUS_LED_PIN, !digitalRead(STATUS_LED_PIN));
    attempts++;
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println();
    LOG_CRITICAL("[OK] WiFi: %s RSSI:%d\n", WiFi.localIP().toString().c_str(), WiFi.RSSI());
    digitalWrite(STATUS_LED_PIN, LOW);
  } else {
    Serial.println();
    LOG_EVENT("WiFi failed - continuing");
    // Continue anyway - might connect later
  }
}

// ============================================================================
// MQTT CONNECTION
// ============================================================================

void connectMQTT() {
  // Don't attempt MQTT if WiFi is not connected
  if (WiFi.status() != WL_CONNECTED) {
    return;
  }
  
  int attempts = 0;
  while (!mqttClient.connected() && attempts < 3) {  // Limit retry attempts
    LOG_EVENT("[MQTT] Connecting to broker...");
    
    if (mqttClient.connect(mqttClientId.c_str())) {
      LOG_EVENT("[MQTT] Connected");
      
      // Subscribe to mesh topics for routing
      mqttClient.subscribe(TOPIC_MESH_NEIGHBOR);
      mqttClient.subscribe(TOPIC_MESH_FORWARD);
      mqttClient.subscribe(TOPIC_BROADCAST_CONFIG);
      
      // Subscribe to own calibration topic
      mqttClient.subscribe(topicCalibration.c_str());
      
      // Subscribe to all node calibration topics (for ESP-NOW forwarding)
      mqttClient.subscribe("shelter/node/+/config/calibration");
      
      LOGLN("   Subscribed to mesh, config, and all calibration topics");
      
      // Send initial presence announcement
      sendNeighborBeacon();
      
    } else {
      LOGF(" FAILED (rc=%d)\n", mqttClient.state());
      attempts++;
      // Non-blocking delay with yield
      unsigned long waitStart = millis();
      while (millis() - waitStart < 2000) {  // Reduced from 5s to 2s
        yield();
      }
    }
  }
}

// ============================================================================
// MQTT CALLBACK
// ============================================================================

void mqttCallback(char* topic, byte* payload, unsigned int length) {
  // Parse payload
  char message[length + 1];
  memcpy(message, payload, length);
  message[length] = '\0';
  
  #if DEBUG_MQTT
  LOGF("[MQTT-RX] %s: %s\n", topic, message);
  #endif
  
  // Update battery for reception
  battery.drainForWifiRx();
  
  // Handle neighbor beacons (for routing)
  if (strcmp(topic, TOPIC_MESH_NEIGHBOR) == 0) {
    handleNeighborBeacon(message);
  }
  // Handle forwarded messages
  else if (strcmp(topic, TOPIC_MESH_FORWARD) == 0) {
    handleForwardedMessage(message);
  }
  // Handle config broadcasts
  else if (strcmp(topic, TOPIC_BROADCAST_CONFIG) == 0) {
    handleConfigUpdate(message);
  }
  // Handle calibration updates
  else if (strcmp(topic, topicCalibration.c_str()) == 0) {
    handleCalibrationUpdate(message);
  }
  // Handle calibration for OTHER nodes (gateway forwarding to ESP-NOW nodes)
  else if (strncmp(topic, TOPIC_TELEMETRY_PREFIX, strlen(TOPIC_TELEMETRY_PREFIX)) == 0 &&
           strstr(topic, "/config/calibration") != nullptr) {
    // Extract target node ID from topic: shelter/node/X/config/calibration
    char targetNode = topic[strlen(TOPIC_TELEMETRY_PREFIX)];
    if (targetNode != nodeId && (targetNode == 'W' || targetNode == 'X' || targetNode == 'Y' || targetNode == 'Z')) {
      LOGF("[MQTT-RX] Calibration for Node %c - forwarding via ESP-NOW\n", targetNode);
      sendConfigViaESPNow(targetNode, message);
    }
  }
}

// ============================================================================
// MESSAGE HANDLERS
// ============================================================================

void handleNeighborBeacon(const char* message) {
  StaticJsonDocument<256> doc;
  DeserializationError error = deserializeJson(doc, message);
  
  if (error) {
    LOGF("[ERROR] JSON parse error: %s\n", error.c_str());
    return;
  }
  
  const char* nodeId = doc["nodeId"];
  if (nodeId && strlen(nodeId) > 0) {
    // MQTT beacons come from other nodes via the broker
    // We can't measure actual ESP-NOW link quality here, so use a conservative estimate
    // The ESP-NOW discovery callback will override this with better values
    int espnowRssi = ESTIMATED_ESPNOW_RSSI;  // Conservative estimate from config
    
    // Parse battery - ensure it's read as float
    float batteryPercent = 0.0;
    if (doc.containsKey("battery")) {
      batteryPercent = doc["battery"].as<float>();
    }
    
    // Parse neighbor's WiFi quality (for path scoring)
    int wifiRssi = -100;
    if (doc.containsKey("wifiRssi")) {
      wifiRssi = doc["wifiRssi"].as<int>();
    }
    
    // Parse sink access status
    bool hasSinkAccess = doc["hasSinkAccess"] | false;
    
    // Update routing table with full path quality info
    routing.updateNeighbor(nodeId[0], espnowRssi, batteryPercent, hasSinkAccess, wifiRssi);
  }
}

void handleForwardedMessage(const char* message) {
  // In a full implementation, this would handle message forwarding
  // For now, we log it
  LOGF("[FWD-RX] Forwarded message: %s\n", message);
}

void handleConfigUpdate(const char* message) {
  StaticJsonDocument<256> doc;
  DeserializationError error = deserializeJson(doc, message);
  
  if (error) return;
  
  // Handle configuration updates (e.g., threshold changes)
  if (doc.containsKey("brownThreshold")) {
    LOGLN("[CONFIG] Config update received (brown threshold)");
    // Could update thresholds dynamically here
  }
}

void handleCalibrationUpdate(const char* message) {
  StaticJsonDocument<512> doc;
  DeserializationError error = deserializeJson(doc, message);
  
  if (error) {
    LOGF("[ERROR] Calibration JSON parse error: %s\n", error.c_str());
    return;
  }
  
  // Update color name
  if (doc.containsKey("colorName")) {
    foodColorName = doc["colorName"].as<String>();
  }
  
  // Update thresholds
  if (doc.containsKey("redMin")) calibratedRedMin = doc["redMin"];
  if (doc.containsKey("redMax")) calibratedRedMax = doc["redMax"];
  if (doc.containsKey("greenMin")) calibratedGreenMin = doc["greenMin"];
  if (doc.containsKey("greenMax")) calibratedGreenMax = doc["greenMax"];
  if (doc.containsKey("blueMin")) calibratedBlueMin = doc["blueMin"];
  if (doc.containsKey("blueMax")) calibratedBlueMax = doc["blueMax"];
  if (doc.containsKey("darkThreshold")) calibratedDarkThreshold = doc["darkThreshold"];
  if (doc.containsKey("greenRedRatioMin")) calibratedGreenRedRatioMin = doc["greenRedRatioMin"];
  if (doc.containsKey("greenRedRatioMax")) calibratedGreenRedRatioMax = doc["greenRedRatioMax"];
  
  LOG_CRITICAL("[CALIBRATION] Updated color detection:\n");
  LOGF("  Color: %s\n", foodColorName.c_str());
  LOGF("  Red: %d-%d\n", calibratedRedMin, calibratedRedMax);
  LOGF("  Green: %d-%d\n", calibratedGreenMin, calibratedGreenMax);
  LOGF("  Blue: %d-%d\n", calibratedBlueMin, calibratedBlueMax);
  LOGF("  Dark threshold: %d\n", calibratedDarkThreshold);
  
  // Update sensor manager thresholds
  sensors.updateCalibration(
    calibratedRedMin, calibratedRedMax,
    calibratedGreenMin, calibratedGreenMax,
    calibratedBlueMin, calibratedBlueMax,
    calibratedDarkThreshold,
    calibratedGreenRedRatioMin, calibratedGreenRedRatioMax
  );
  
  // Save to EEPROM for persistence across reboots
  saveCalibrationToEEPROM();
}

// Send calibration config to another node via ESP-NOW
void sendConfigViaESPNow(char targetNode, const char* configJson) {
  #if ENABLE_ESPNOW
  int jsonLen = strlen(configJson);
  if (jsonLen > 149) {  // Leave room for null terminator
    LOGLN("[ERROR] Config JSON too large for ESP-NOW");
    return;
  }
  
  // Find the MAC address of the target node
  uint8_t targetMac[6];
  bool found = espnowMesh.getPeerMac(targetNode, targetMac);
  
  if (!found) {
    LOGF("[CONFIG] Target node %c not found in ESP-NOW peers\n", targetNode);
    return;
  }
  
  // Send config message via ESP-NOW
  bool sent = espnowMesh.sendData(targetMac, MSG_TYPE_CONFIG, configJson, jsonLen);
  
  if (sent) {
    LOGF("[CONFIG] Sent calibration to Node %c via ESP-NOW\n", targetNode);
  } else {
    LOGF("[CONFIG] Failed to send to Node %c\n", targetNode);
  }
  #endif
}

// ============================================================================
// TELEMETRY
// ============================================================================

void sendTelemetry(SensorData& data) {
  // Full telemetry JSON for MQTT (512 bytes max)
  StaticJsonDocument<512> doc;
  
  doc["nodeId"] = nodeIdString;
  doc["timestamp"] = millis();
  doc["userId"] = USER_ID;
  
  // Sensor data
  JsonObject sensorsObj = doc.createNestedObject("sensors");
  
  JsonObject ultrasonic = sensorsObj.createNestedObject("ultrasonic");
  ultrasonic["distanceCm"] = data.ultrasonic.distanceCm;
  ultrasonic["catPresent"] = data.ultrasonic.catPresent;
  
  JsonObject color = sensorsObj.createNestedObject("color");
  color["red"] = data.color.red;
  color["green"] = data.color.green;
  color["blue"] = data.color.blue;
  color["isBrown"] = data.color.isBrown;
  color["plateStatus"] = data.plateEmpty ? "empty" : (data.color.isBrown ? "filled" : "unknown");
  
  // Battery data
  JsonObject batt = doc.createNestedObject("battery");
  batt["percentage"] = battery.getPercent();
  batt["voltage"] = battery.getVoltage();
  batt["capacityMah"] = battery.getCapacityMah();
  batt["drainedMah"] = battery.getDrainedMah();
  
  // Network/routing data
  JsonObject network = doc.createNestedObject("network");
  network["rssi"] = WiFi.RSSI();
  network["hopCount"] = routing.getHopCount();
  network["nextHop"] = String(routing.getNextHop());
  
  #if ESPNOW_ENABLED
  // Add ESP-NOW stats
  network["espnowPeers"] = espnowMesh.getPeerCount();
  network["espnowTx"] = espnowMesh.getTxCount();
  network["espnowRx"] = espnowMesh.getRxCount();
  network["espnowFwd"] = espnowMesh.getForwardCount();
  #endif
  
  // Add route array
  char routeArr[5];
  int routeLen;
  routing.getRouteArray(routeArr, &routeLen);
  JsonArray route = network.createNestedArray("route");
  for (int i = 0; i < routeLen; i++) {
    if (routeArr[i] == 'S') {
      route.add("SINK");
    } else {
      route.add(String(routeArr[i]));
    }
  }
  
  // Serialize full telemetry for MQTT
  char buffer[512];
  size_t len = serializeJson(doc, buffer);
  
  // Create COMPACT telemetry for ESP-NOW (MUST fit in 150 bytes)
  // Uses short keys and minimal data - gateway will expand it
  StaticJsonDocument<160> compactDoc;
  compactDoc["n"] = nodeIdString;                              // nodeId
  compactDoc["u"] = USER_ID;                                   // userId
  compactDoc["d"] = (int)data.ultrasonic.distanceCm;          // distance
  compactDoc["c"] = data.ultrasonic.catPresent ? 1 : 0;       // catPresent
  compactDoc["r"] = data.color.red;                           // red color
  compactDoc["p"] = data.plateEmpty ? "e" : (data.color.isBrown ? "f" : "u");  // plateStatus: e/f/u
  compactDoc["b"] = (int)battery.getPercent();                // battery %
  compactDoc["s"] = WiFi.RSSI();                              // rssi
  compactDoc["h"] = routing.getHopCount() + 1;                // hopCount (+1 for relay)
  
  // Add route tracking - start with origin node
  JsonArray compactRoute = compactDoc.createNestedArray("rt");
  compactRoute.add(nodeIdString);
  
  char compactBuffer[150];
  size_t compactLen = serializeJson(compactDoc, compactBuffer);
  
  // Verify compact JSON fits in ESP-NOW payload limit
  if (compactLen >= 150) {
    LOG_CRITICAL("[WARN] Compact JSON too large: %d bytes (limit 150)\n", compactLen);
    compactLen = 149;  // Truncate to fit
    compactBuffer[149] = '\0';
  }
  
  // Determine how to send based on routing decision
  char nextHop = routing.getNextHop();
  
  #if ESPNOW_ENABLED
  
  #if FORCE_MULTIHOP
  // FORCED MULTI-HOP MODE: Always try to route via ESP-NOW peers
  // This is for demonstrating multi-hop routing
  if (hasOtherPeerWithSinkAccess()) {
    char targetPeer = getPeerWithSinkAccess();
    // Use COMPACT payload for ESP-NOW (fits in 150 byte limit)
    bool sent = espnowMesh.sendData(targetPeer, MSG_TYPE_TELEMETRY, compactBuffer, compactLen);
    if (sent) {
      LOG_CRITICAL("[TX] Telemetry via ESP-NOW -> Node %c (%d bytes)\n", targetPeer, compactLen);
    } else {
      LOG_CRITICAL("[TX] ESP-NOW failed, fallback MQTT\n");
      mqttClient.publish(topicTelemetry.c_str(), buffer);
      battery.drainForWifiTx();
    }
  } else {
    // No peers available - must use direct MQTT
    LOG_CRITICAL("[TX] No peers, direct MQTT\n");
    mqttClient.publish(topicTelemetry.c_str(), buffer);
    battery.drainForWifiTx();
  }
  #else
  // NORMAL MODE: Use best route, but handle WiFi-less fallback
  bool wifiAvailable = (WiFi.status() == WL_CONNECTED) && mqttClient.connected();
  
  if (!wifiAvailable && espnowMesh.getPeerCount() > 0) {
    // WiFi is DOWN but we have ESP-NOW peers - use them as relay!
    char targetPeer = 0;
    
    // Find a peer with sink access (can relay to MQTT)
    for (int i = 0; i < MAX_ESPNOW_PEERS; i++) {
      ESPNowPeer* peer = espnowMesh.getPeerByIndex(i);
      if (peer && peer->nodeId != 0 && peer->hasSinkAccess) {
        targetPeer = peer->nodeId;
        break;
      }
    }
    
    // If no peer with sink access, try any peer
    if (targetPeer == 0) {
      ESPNowPeer* peer = espnowMesh.getPeerByIndex(0);
      if (peer && peer->nodeId != 0) {
        targetPeer = peer->nodeId;
      }
    }
    
    if (targetPeer != 0) {
      bool sent = espnowMesh.sendData(targetPeer, MSG_TYPE_TELEMETRY, compactBuffer, compactLen);
      if (sent) {
        LOG_CRITICAL("[TX] WiFi down! Using ESP-NOW relay -> Node %c (%d bytes)\n", targetPeer, compactLen);
      } else {
        LOG_CRITICAL("[TX] ESP-NOW relay failed, no fallback available\n");
      }
    } else {
      LOG_CRITICAL("[TX] WiFi down, no ESP-NOW peers available!\n");
    }
  }
  else if (nextHop != 'S' && espnowMesh.getPeer(nextHop) != nullptr) {
    // Route via ESP-NOW to another node - use COMPACT payload
    bool sent = espnowMesh.sendData(nextHop, MSG_TYPE_TELEMETRY, compactBuffer, compactLen);
    if (sent) {
      LOG_CRITICAL("[TX] Telemetry via ESP-NOW -> Node %c (%d bytes)\n", nextHop, compactLen);
      network["sentVia"] = String("ESP-NOW->") + String(nextHop);
    } else {
      // Fallback to direct MQTT if ESP-NOW fails
      LOG_CRITICAL("[TX] ESP-NOW fail, fallback MQTT\n");
      if (wifiAvailable) {
        mqttClient.publish(topicTelemetry.c_str(), buffer);
        battery.drainForWifiTx();
      }
    }
  } else if (wifiAvailable) {
    // Direct to sink via MQTT - use full JSON
    mqttClient.publish(topicTelemetry.c_str(), buffer);
    battery.drainForWifiTx();
    LOG_CRITICAL("[TX] Telemetry via MQTT\n");
  } else {
    LOG_CRITICAL("[TX] No route available (WiFi down, no peers)\n");
  }
  #endif  // FORCE_MULTIHOP
  #else
  // No ESP-NOW, use MQTT only
  mqttClient.publish(topicTelemetry.c_str(), buffer);
  battery.drainForWifiTx();
  LOG_CRITICAL("[TX] Telemetry via MQTT\n");
  #endif
}

// ============================================================================
// ROUTING UPDATE
// ============================================================================

void sendRoutingUpdate(RoutingDecision& decision) {
  StaticJsonDocument<512> doc;
  
  doc["nodeId"] = nodeIdString;
  doc["timestamp"] = millis();
  
  JsonObject rd = doc.createNestedObject("routingDecision");
  rd["previousNextHop"] = String(decision.previousNextHop);
  rd["newNextHop"] = String(decision.newNextHop);
  rd["reason"] = decision.reason;
  rd["selectedScore"] = decision.selectedScore;
  
  JsonArray candidates = rd.createNestedArray("candidates");
  for (int i = 0; i < decision.candidateCount; i++) {
    JsonObject c = candidates.createNestedObject();
    c["target"] = String(decision.candidates[i].targetId);
    c["rssi"] = decision.candidates[i].rssi;
    c["battery"] = decision.candidates[i].batteryPercent;
    c["score"] = decision.candidates[i].score;
  }
  
  char buffer[512];
  serializeJson(doc, buffer);
  
  mqttClient.publish(topicRouting.c_str(), buffer);
  battery.drainForWifiTx();
  
  LOGF("[ROUTE] Routing update sent: %c -> %c (score: %.2f)\n",
                decision.previousNextHop, decision.newNextHop, decision.selectedScore);
}

// ============================================================================
// ALERTS
// ============================================================================

void sendAlert(const char* alertType, const char* message, SensorData& data) {
  StaticJsonDocument<384> doc;
  
  String alertId = "alert_" + nodeIdString + "_" + String(millis());
  
  doc["alertId"] = alertId;
  doc["nodeId"] = nodeIdString;
  doc["type"] = alertType;
  doc["timestamp"] = millis();
  doc["userId"] = USER_ID;
  
  JsonObject details = doc.createNestedObject("details");
  details["plateStatus"] = sensors.getPlateStatusString();
  details["catPresent"] = data.ultrasonic.catPresent;
  details["batteryPercent"] = battery.getPercent();
  
  if (data.color.valid) {
    JsonObject colorReading = details.createNestedObject("colorReading");
    colorReading["red"] = data.color.red;
    colorReading["green"] = data.color.green;
    colorReading["blue"] = data.color.blue;
  }
  
  doc["severity"] = "warning";
  doc["message"] = message;
  
  char buffer[384];
  size_t len = serializeJson(doc, buffer);
  
  // Route alert based on routing decision
  char nextHop = routing.getNextHop();
  
  #if ESPNOW_ENABLED
  
  #if FORCE_MULTIHOP
  // FORCED MULTI-HOP MODE: Always try to route alerts via ESP-NOW peers
  if (hasOtherPeerWithSinkAccess()) {
    char targetPeer = getPeerWithSinkAccess();
    bool sent = espnowMesh.sendData(targetPeer, MSG_TYPE_ALERT, buffer, len);
    if (sent) {
      LOGF("[ALERT] Sent via ESP-NOW to Node %c (FORCED MULTIHOP): %s - %s\n", targetPeer, alertType, message);
    } else {
      mqttClient.publish(topicAlert.c_str(), buffer);
      battery.drainForWifiTx();
      LOGF("[ALERT] Sent via MQTT (fallback): %s - %s\n", alertType, message);
    }
  } else {
    mqttClient.publish(topicAlert.c_str(), buffer);
    battery.drainForWifiTx();
    LOGF("[ALERT] Sent via MQTT (no peers): %s - %s\n", alertType, message);
  }
  #else
  // NORMAL MODE
  if (nextHop != 'S' && espnowMesh.getPeer(nextHop) != nullptr) {
    // Route via ESP-NOW
    bool sent = espnowMesh.sendData(nextHop, MSG_TYPE_ALERT, buffer, len);
    if (sent) {
      LOGF("[ALERT] Sent via ESP-NOW to Node %c: %s - %s\n", nextHop, alertType, message);
    } else {
      // Fallback to MQTT
      mqttClient.publish(topicAlert.c_str(), buffer);
      battery.drainForWifiTx();
      LOGF("[ALERT] Sent via MQTT (ESP-NOW failed): %s - %s\n", alertType, message);
    }
  } else {
    // Direct to sink via MQTT
    mqttClient.publish(topicAlert.c_str(), buffer);
    battery.drainForWifiTx();
    LOGF("[ALERT] Sent via MQTT: %s - %s\n", alertType, message);
  }
  #endif  // FORCE_MULTIHOP
  
  #else
  mqttClient.publish(topicAlert.c_str(), buffer);
  battery.drainForWifiTx();
  LOGF("[ALERT] Sent: %s - %s\n", alertType, message);
  #endif
}

void checkAndSendAlerts(SensorData& data) {
  // Empty plate alert: no cat present AND plate not brown (empty)
  if (!data.ultrasonic.catPresent && !data.color.isBrown) {
    if (!emptyPlateAlertSent) {
      String msg = "Empty plate at Bowl " + nodeIdString + " - needs refill";
      sendAlert("empty_plate", msg.c_str(), data);
      emptyPlateAlertSent = true;
    }
  } else {
    // Reset alert flag when condition clears
    emptyPlateAlertSent = false;
  }
  
  // Cat presence change notification
  if (data.ultrasonic.catPresent != lastCatPresent) {
    if (data.ultrasonic.catPresent) {
      String msg = "Cat detected at Bowl " + nodeIdString;
      sendAlert("cat_present", msg.c_str(), data);
    }
    lastCatPresent = data.ultrasonic.catPresent;
  }
  
  // Low battery alert
  if (battery.isLow() && !battery.isCritical()) {
    static unsigned long lastLowBatteryAlert = 0;
    if (millis() - lastLowBatteryAlert > 300000) {  // Every 5 minutes
      String msg = "Low battery on Node " + nodeIdString + " (" + 
                   String(battery.getPercent(), 0) + "%)";
      sendAlert("low_battery", msg.c_str(), data);
      lastLowBatteryAlert = millis();
    }
  }
}

// ============================================================================
// NEIGHBOR BEACON
// ============================================================================

void sendNeighborBeacon() {
  String beacon = routing.createNeighborBeacon(battery.getPercent());
  mqttClient.publish(TOPIC_MESH_NEIGHBOR, beacon.c_str());
  battery.drainForWifiTx();
  
  #if DEBUG_ROUTING
  LOGLN("[BEACON] Neighbor beacon sent");
  #endif
}

// ============================================================================
// MAIN LOOP
// ============================================================================

void loop() {
  unsigned long now = millis();
  
  // Try MQTT connection only if WiFi is connected
  if (WiFi.status() == WL_CONNECTED) {
    if (!mqttClient.connected()) {
      connectMQTT();
    }
    mqttClient.loop();
  }
  
  // Update battery for idle time
  battery.update(false, false, false);
  
  #if ESPNOW_ENABLED
  // --- ESP-NOW Operations ---
  
  // If WiFi is down, periodically rescan channels to find peers
  #if ESPNOW_CHANNEL_SCAN
  if (WiFi.status() != WL_CONNECTED && espnowMesh.needsChannelRescan()) {
    LOG_CRITICAL("[LOOP] WiFi down, rescanning for ESP-NOW peers...\n");
    espnowMesh.scanForPeers();
  }
  #endif
  
  // Determine if this node has direct sink access (MQTT connected)
  bool hasSinkAccess = mqttClient.connected();
  
  // Process deferred operations (ACKs scheduled from callbacks)
  espnowMesh.processDeferredOps(battery.getPercent(), hasSinkAccess);
  
  // Send ESP-NOW discovery beacons
  if (now - lastEspnowDiscovery >= ESPNOW_DISCOVERY_INTERVAL) {
    espnowMesh.sendDiscovery(battery.getPercent(), hasSinkAccess);
    lastEspnowDiscovery = now;
  }
  
  // Update routing table with ESP-NOW peer info
  for (int i = 0; i < MAX_ESPNOW_PEERS; i++) {
    ESPNowPeer* peers = espnowMesh.getPeers();
    if (peers[i].active) {
      // peers[i].rssi is their WiFi RSSI (path to sink)
      // We estimate ESP-NOW link quality - if we received their discovery, it's decent
      int espnowLinkRssi = ESTIMATED_ESPNOW_RSSI;  // From config.h
      
      // Pass both the ESP-NOW link quality and their WiFi quality for path comparison
      routing.updateNeighbor(peers[i].nodeId, espnowLinkRssi, peers[i].batteryPercent, 
                            peers[i].hasSinkAccess, peers[i].rssi);
      // Mark this neighbor as ESP-NOW reachable for routing bonus
      routing.setEspnowAvailable(peers[i].nodeId, true);
    }
  }
  
  // Handle ALL queued messages received via ESP-NOW (process entire queue)
  while (espnowMesh.hasDataToProcess()) {
    ESPNowDataMsg* msg = espnowMesh.getReceivedData();
    if (msg == nullptr) break;  // Safety check
    
    LOG_CRITICAL("[FWD] Data from Node %c (type:%d)\n", msg->originNode, msg->type);
    
    // If this message is addressed to us (not for forwarding), process it locally
    if (msg->destNode == nodeId) {
      if (msg->type == MSG_TYPE_CONFIG) {
        // Config message for this node - extract and apply calibration
        char payloadBuf[160];
        int copyLen = min((int)msg->payloadLen, 159);
        memcpy(payloadBuf, msg->payload, copyLen);
        payloadBuf[copyLen] = '\0';
        
        LOGF("[CONFIG] Received via ESP-NOW from %c\n", msg->originNode);
        handleCalibrationUpdate(payloadBuf);
        
        // Don't forward config messages that reached their destination
        yield();
        continue;
      }
    }
    
    // FIX: Always forward to MQTT if we have connectivity, regardless of own routing preference
    // This prevents the bug where we'd try to forward back to the sender
    bool canForwardToMqtt = mqttClient.connected();
    
    #if FORCE_MULTIHOP
    // In forced multi-hop mode, only forward to MQTT if we're the designated gateway
    // (i.e., no other peers with sink access)
    canForwardToMqtt = canForwardToMqtt && !hasOtherPeerWithSinkAccess();
    #endif
    
    LOGF("[FWD] MQTT connected: %s, canForward: %s\n",
                  mqttClient.connected() ? "YES" : "NO",
                  canForwardToMqtt ? "YES" : "NO");
    
    if (canForwardToMqtt) {
      // We have MQTT connectivity - forward to sink directly
      
      // Publish the payload to the appropriate topic based on message type
      String topic;
      if (msg->type == MSG_TYPE_TELEMETRY) {
        topic = String(TOPIC_TELEMETRY_PREFIX) + String(msg->originNode) + TOPIC_TELEMETRY_SUFFIX;
      } else if (msg->type == MSG_TYPE_ALERT) {
        topic = String(TOPIC_TELEMETRY_PREFIX) + String(msg->originNode) + TOPIC_ALERT_SUFFIX;
      }
      
      if (topic.length() > 0) {
        // Ensure null-terminated payload for MQTT publish
        char payloadBuf[160];  // Match ESP-NOW payload size
        int copyLen = min((int)msg->payloadLen, 159);
        memcpy(payloadBuf, msg->payload, copyLen);
        payloadBuf[copyLen] = '\0';
        
        // If compact format, append relay node to route
        StaticJsonDocument<160> relayDoc;
        DeserializationError err = deserializeJson(relayDoc, payloadBuf);
        if (!err && relayDoc.containsKey("rt")) {
          // Append relay node ID to route
          JsonArray rt = relayDoc["rt"];
          rt.add(nodeIdString);
          serializeJson(relayDoc, payloadBuf, sizeof(payloadBuf));
        }
        
        bool published = mqttClient.publish(topic.c_str(), payloadBuf);
        battery.drainForWifiTx();
        LOG_CRITICAL("[FWD] %c->MQTT %s\n", msg->originNode, published ? "OK" : "FAIL");
      }
    } else {
      // No MQTT access or forced multi-hop - forward via ESP-NOW to next hop
      char nextHop = routing.getNextHop();
      if (nextHop != 'S' && nextHop != msg->originNode) {
        // Don't forward back to origin!
        bool fwdOk = espnowMesh.forwardData(msg, nextHop);
        LOG_CRITICAL("[FWD] %c->ESP-NOW->%c %s\n", msg->originNode, nextHop, fwdOk ? "OK" : "FAIL");
      } else {
        LOG_CRITICAL("[FWD] %c no valid hop\n", msg->originNode);
      }
    }
    
    yield();  // Prevent watchdog reset when processing multiple messages
  }
  
  // Cleanup stale ESP-NOW peers
  espnowMesh.cleanupStalePeers();
  
  // Print ESP-NOW stats periodically (less frequently in production mode)
  #if DEBUG_LOGGING
  if (now - lastEspnowStats >= 30000) {
    espnowMesh.printStats();
    lastEspnowStats = now;
  }
  #endif
  #endif
  
  // --- Sensor Reading ---
  if (now - lastSensorRead >= SENSOR_READ_INTERVAL_MS) {
    lastSensorRead = now;
    
    // Read all sensors
    LOGLN("[SENSOR] Reading sensors...");
    SensorData data = sensors.readAll();
    battery.drainForSensorCycle();
    
    // Check for alert conditions
    checkAndSendAlerts(data);
    
    // Send telemetry (via best route)
    sendTelemetry(data);
    lastTelemetry = now;
  }
  
  // --- Routing Update ---
  if (routing.needsRouteUpdate()) {
    // Update sink RSSI
    routing.updateSinkRssi(WiFi.RSSI());
    
    // Select best route
    RoutingDecision decision = routing.selectRoute(battery.getPercent());
    
    // Only send update if route changed
    if (decision.previousNextHop != decision.newNextHop) {
      sendRoutingUpdate(decision);
    }
    
    lastRouteUpdate = now;
  }
  
  // --- Neighbor Beacon (MQTT-based, keep for compatibility) ---
  if (now - lastNeighborBeacon >= NEIGHBOR_BEACON_INTERVAL_MS) {
    sendNeighborBeacon();
    lastNeighborBeacon = now;
  }
  
  // --- Status LED ---
  // Blink pattern indicates status
  static unsigned long lastBlink = 0;
  if (now - lastBlink >= 1000) {
    // Quick blink = OK, slow blink = issue
    if (battery.isCritical()) {
      // Fast blink for critical battery
      digitalWrite(STATUS_LED_PIN, !digitalRead(STATUS_LED_PIN));
      lastBlink = now - 800;  // Faster
    } else if (!mqttClient.connected()) {
      // Slow blink for connection issue
      digitalWrite(STATUS_LED_PIN, !digitalRead(STATUS_LED_PIN));
      lastBlink = now;
    } else {
      // Brief flash for normal operation
      digitalWrite(STATUS_LED_PIN, HIGH);
      delay(30);  // Reduced from 50ms
      digitalWrite(STATUS_LED_PIN, LOW);
      lastBlink = now;
    }
  }
  
  // Yield to prevent watchdog reset - more reliable than delay()
  yield();
}
