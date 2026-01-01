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

// MQTT topics (built dynamically)
String topicTelemetry;
String topicRouting;
String topicAlert;

// User ID for Firebase integration (matches gateway)
const char* USER_ID = "EyrwFFoBJ8TlVFepJvqdeooOBwA2";

// ============================================================================
// SETUP
// ============================================================================

void setup() {
  Serial.begin(115200);
  delay(100);
  
  Serial.println("\n\n");
  Serial.println("╔══════════════════════════════════════════════════════╗");
  Serial.println("║    Shelter Cat Monitoring - ESP8266 Node             ║");
  Serial.println("╚══════════════════════════════════════════════════════╝");
  
  // Initialize node identity
  nodeIdStr[0] = NODE_ID;
  nodeIdStr[1] = '\0';
  nodeIdString = String(nodeIdStr);
  mqttClientId = String(MQTT_CLIENT_ID_PREFIX) + nodeIdString;
  
  Serial.printf("📍 Node ID: %c\n", NODE_ID);
  Serial.printf("🔗 MQTT Client: %s\n", mqttClientId.c_str());
  
  // Build MQTT topics
  topicTelemetry = String(TOPIC_TELEMETRY_PREFIX) + nodeIdString + TOPIC_TELEMETRY_SUFFIX;
  topicRouting = String(TOPIC_TELEMETRY_PREFIX) + nodeIdString + TOPIC_ROUTING_SUFFIX;
  topicAlert = String(TOPIC_TELEMETRY_PREFIX) + nodeIdString + TOPIC_ALERT_SUFFIX;
  
  Serial.println("\n📡 MQTT Topics:");
  Serial.printf("   Telemetry: %s\n", topicTelemetry.c_str());
  Serial.printf("   Routing:   %s\n", topicRouting.c_str());
  Serial.printf("   Alert:     %s\n", topicAlert.c_str());
  
  // Initialize status LED
  pinMode(STATUS_LED_PIN, OUTPUT);
  digitalWrite(STATUS_LED_PIN, LOW);
  
  // Initialize components
  Serial.println("\n🔧 Initializing components...");
  
  // Sensors
  sensors.begin();
  
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
  Serial.println("\n📡 Initializing ESP-NOW mesh...");
  espnowMesh.begin(NODE_ID);  // Auto-detects channel
  #endif
  
  // Setup MQTT
  mqttClient.setServer(MQTT_BROKER, MQTT_PORT);
  mqttClient.setCallback(mqttCallback);
  mqttClient.setBufferSize(1024);  // Larger buffer for JSON
  
  connectMQTT();
  
  // Initial sensor read
  Serial.println("\n📊 Initial sensor reading...");
  SensorData data = sensors.readAll();
  Serial.printf("   Cat present: %s\n", data.ultrasonic.catPresent ? "YES" : "NO");
  Serial.printf("   Plate status: %s\n", sensors.getPlateStatusString());
  
  // Blink LED to confirm setup
  for (int i = 0; i < 3; i++) {
    digitalWrite(STATUS_LED_PIN, HIGH);
    delay(150);
    digitalWrite(STATUS_LED_PIN, LOW);
    delay(150);
  }
  
  Serial.println("\n✅ Setup complete! Entering main loop...\n");
}

// ============================================================================
// WIFI SETUP
// ============================================================================

void setupWiFi() {
  Serial.print("📶 Connecting to WiFi: ");
  Serial.println(WIFI_SSID);
  
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 30) {
    delay(500);
    Serial.print(".");
    digitalWrite(STATUS_LED_PIN, !digitalRead(STATUS_LED_PIN));
    attempts++;
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println();
    Serial.println("✅ WiFi connected!");
    Serial.printf("   IP: %s\n", WiFi.localIP().toString().c_str());
    Serial.printf("   RSSI: %d dBm\n", WiFi.RSSI());
    digitalWrite(STATUS_LED_PIN, LOW);
  } else {
    Serial.println("\n❌ WiFi connection failed!");
    // Continue anyway - might connect later
  }
}

// ============================================================================
// MQTT CONNECTION
// ============================================================================

void connectMQTT() {
  while (!mqttClient.connected()) {
    Serial.printf("🔌 Connecting to MQTT broker %s...", MQTT_BROKER);
    
    if (mqttClient.connect(mqttClientId.c_str())) {
      Serial.println(" ✅ connected!");
      
      // Subscribe to mesh topics for routing
      mqttClient.subscribe(TOPIC_MESH_NEIGHBOR);
      mqttClient.subscribe(TOPIC_MESH_FORWARD);
      mqttClient.subscribe(TOPIC_BROADCAST_CONFIG);
      
      Serial.println("   Subscribed to mesh and config topics");
      
      // Send initial presence announcement
      sendNeighborBeacon();
      
    } else {
      Serial.printf(" ❌ failed (rc=%d), retrying in 5s\n", mqttClient.state());
      delay(5000);
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
  Serial.printf("📨 MQTT [%s]: %s\n", topic, message);
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
}

// ============================================================================
// MESSAGE HANDLERS
// ============================================================================

void handleNeighborBeacon(const char* message) {
  StaticJsonDocument<256> doc;
  DeserializationError error = deserializeJson(doc, message);
  
  if (error) {
    Serial.printf("❌ JSON parse error: %s\n", error.c_str());
    return;
  }
  
  const char* nodeId = doc["nodeId"];
  if (nodeId && strlen(nodeId) > 0) {
    int rssi = doc["rssi"] | -100;
    float batteryPercent = doc["battery"] | 0;
    
    // Update routing table with this neighbor
    routing.updateNeighbor(nodeId[0], rssi, batteryPercent, false);
  }
}

void handleForwardedMessage(const char* message) {
  // In a full implementation, this would handle message forwarding
  // For now, we log it
  Serial.printf("📬 Forwarded message received: %s\n", message);
}

void handleConfigUpdate(const char* message) {
  StaticJsonDocument<256> doc;
  DeserializationError error = deserializeJson(doc, message);
  
  if (error) return;
  
  // Handle configuration updates (e.g., threshold changes)
  if (doc.containsKey("brownThreshold")) {
    Serial.println("📝 Config update received (brown threshold)");
    // Could update thresholds dynamically here
  }
}

// ============================================================================
// TELEMETRY
// ============================================================================

void sendTelemetry(SensorData& data) {
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
  
  // Serialize
  char buffer[512];
  size_t len = serializeJson(doc, buffer);
  
  // Determine how to send based on routing decision
  char nextHop = routing.getNextHop();
  
  #if ESPNOW_ENABLED
  if (nextHop != 'S' && espnowMesh.getPeer(nextHop) != nullptr) {
    // Route via ESP-NOW to another node
    bool sent = espnowMesh.sendData(nextHop, MSG_TYPE_TELEMETRY, buffer, len);
    if (sent) {
      Serial.printf("📤 Telemetry sent via ESP-NOW to Node %c\n", nextHop);
      network["sentVia"] = String("ESP-NOW->") + String(nextHop);
    } else {
      // Fallback to direct MQTT if ESP-NOW fails
      Serial.println("⚠️ ESP-NOW send failed, falling back to MQTT");
      mqttClient.publish(topicTelemetry.c_str(), buffer);
      battery.drainForWifiTx();
    }
  } else {
    // Direct to sink via MQTT
    mqttClient.publish(topicTelemetry.c_str(), buffer);
    battery.drainForWifiTx();
    #if DEBUG_MQTT
    Serial.printf("📤 Telemetry sent via MQTT to %s\n", topicTelemetry.c_str());
    #endif
  }
  #else
  // No ESP-NOW, use MQTT only
  mqttClient.publish(topicTelemetry.c_str(), buffer);
  battery.drainForWifiTx();
  
  #if DEBUG_MQTT
  Serial.printf("📤 Telemetry sent to %s\n", topicTelemetry.c_str());
  #endif
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
  
  Serial.printf("🔀 Routing update sent: %c -> %c (score: %.2f)\n",
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
  if (nextHop != 'S' && espnowMesh.getPeer(nextHop) != nullptr) {
    // Route via ESP-NOW
    bool sent = espnowMesh.sendData(nextHop, MSG_TYPE_ALERT, buffer, len);
    if (sent) {
      Serial.printf("🚨 ALERT sent via ESP-NOW to Node %c: %s - %s\n", nextHop, alertType, message);
    } else {
      // Fallback to MQTT
      mqttClient.publish(topicAlert.c_str(), buffer);
      battery.drainForWifiTx();
      Serial.printf("🚨 ALERT sent via MQTT (ESP-NOW failed): %s - %s\n", alertType, message);
    }
  } else {
    // Direct to sink via MQTT
    mqttClient.publish(topicAlert.c_str(), buffer);
    battery.drainForWifiTx();
    Serial.printf("🚨 ALERT sent via MQTT: %s - %s\n", alertType, message);
  }
  #else
  mqttClient.publish(topicAlert.c_str(), buffer);
  battery.drainForWifiTx();
  Serial.printf("🚨 ALERT sent: %s - %s\n", alertType, message);
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
  Serial.println("📡 Neighbor beacon sent");
  #endif
}

// ============================================================================
// MAIN LOOP
// ============================================================================

void loop() {
  unsigned long now = millis();
  
  // Ensure MQTT connection
  if (!mqttClient.connected()) {
    connectMQTT();
  }
  mqttClient.loop();
  
  // Update battery for idle time
  battery.update(false, false, false);
  
  #if ESPNOW_ENABLED
  // --- ESP-NOW Operations ---
  
  // Process deferred operations (ACKs scheduled from callbacks)
  espnowMesh.processDeferredOps(battery.getPercent());
  
  // Send ESP-NOW discovery beacons
  if (now - lastEspnowDiscovery >= ESPNOW_DISCOVERY_INTERVAL) {
    espnowMesh.sendDiscovery(battery.getPercent());
    lastEspnowDiscovery = now;
  }
  
  // Update routing table with ESP-NOW peer info
  for (int i = 0; i < MAX_ESPNOW_PEERS; i++) {
    ESPNowPeer* peers = espnowMesh.getPeers();
    if (peers[i].active) {
      routing.updateNeighbor(peers[i].nodeId, peers[i].rssi, peers[i].batteryPercent, false);
      // Mark this neighbor as ESP-NOW reachable for routing bonus
      routing.setEspnowAvailable(peers[i].nodeId, true);
    }
  }
  
  // Handle forwarded messages received via ESP-NOW
  if (espnowMesh.hasDataToProcess()) {
    ESPNowDataMsg* msg = espnowMesh.getReceivedData();
    
    // This message needs to go to sink - we can forward via MQTT or another hop
    char nextHop = routing.getNextHop();
    
    if (nextHop == 'S') {
      // We're the gateway to sink - publish to MQTT
      Serial.printf("📬 [ESP-NOW->MQTT] Forwarding from Node %c to MQTT\n", msg->originNode);
      
      // Publish the payload to the appropriate topic based on message type
      String topic;
      if (msg->type == MSG_TYPE_TELEMETRY) {
        topic = String(TOPIC_TELEMETRY_PREFIX) + String(msg->originNode) + TOPIC_TELEMETRY_SUFFIX;
      } else if (msg->type == MSG_TYPE_ALERT) {
        topic = String(TOPIC_TELEMETRY_PREFIX) + String(msg->originNode) + TOPIC_ALERT_SUFFIX;
      }
      
      if (topic.length() > 0) {
        mqttClient.publish(topic.c_str(), msg->payload, msg->payloadLen);
        battery.drainForWifiTx();
      }
    } else {
      // Forward via ESP-NOW to next hop
      espnowMesh.forwardData(msg, nextHop);
    }
  }
  
  // Cleanup stale ESP-NOW peers
  espnowMesh.cleanupStalePeers();
  
  // Print ESP-NOW stats periodically
  if (now - lastEspnowStats >= 30000) {
    espnowMesh.printStats();
    lastEspnowStats = now;
  }
  #endif
  
  // --- Sensor Reading ---
  if (now - lastSensorRead >= SENSOR_READ_INTERVAL_MS) {
    lastSensorRead = now;
    
    // Read all sensors
    Serial.println("\n📊 Reading sensors...");
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
      delay(50);
      digitalWrite(STATUS_LED_PIN, LOW);
      lastBlink = now;
    }
  }
  
  // Small delay to prevent watchdog issues
  delay(10);
}
