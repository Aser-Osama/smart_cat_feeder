/**
 * Smart Cat Feeder - ESP8266 Feeder Node
 * =========================================
 * 
 * This is Node 1 of the Smart Cat Feeder WSN.
 * It handles:
 * - LED actuator (simulating food dispenser/servo)
 * - Button sensor (simulating cat detection via ultrasonic/IR)
 * - MQTT communication with Orange Pi gateway
 * 
 * Hardware:
 * - NodeMCU ESP8266 (or similar)
 * - LED on GPIO 2 (D4) - Built-in LED, active LOW
 * - External LED on GPIO 5 (D1) - Actuator indicator
 * - Button on GPIO 4 (D2) - Cat detection simulation
 * 
 * MQTT Topics:
 * - Subscribe: feeder/control/dispense
 * - Publish: feeder/status/fed
 * - Publish: feeder/status/cat_detected
 * - Publish: feeder/status/heartbeat
 */

#include <ESP8266WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>

// ============================================================================
// Configuration - UPDATE THESE VALUES
// ============================================================================

 // WiFi credentials
 const char* WIFI_SSID     = "Aser";
 const char* WIFI_PASSWORD = "1234567899abc";
 
 // MQTT Broker (Orange Pi IP address)
 // const char* MQTT_BROKER     = "192.168.100.135"; 
 const char* MQTT_BROKER     = "172.29.32.150 ";  // UPDATE to your Orange Pi IP

 const int   MQTT_PORT       = 1883;
 const char* MQTT_CLIENT_ID  = "esp8266-feeder";

 // Optional: User ID for multi-user support
 const char* USER_ID = "EyrwFFoBJ8TlVFepJvqdeooOBwA2";
 
// ============================================================================
// Pin Definitions
// ============================================================================

#define LED_BUILTIN_PIN   2   // D4 - Built-in LED (active LOW)
#define LED_ACTUATOR_PIN  5   // D1 - External LED for actuator feedback
#define BUTTON_PIN        4   // D2 - Button for cat detection simulation

// In a full implementation, you would also have:
// #define SERVO_PIN      14  // D5 - Servo motor for food dispenser
// #define IR_SENSOR_PIN  12  // D6 - IR proximity sensor
// #define HX711_DOUT     13  // D7 - Load cell data
// #define HX711_SCK      15  // D8 - Load cell clock

// ============================================================================
// MQTT Topics
// ============================================================================

const char* TOPIC_FEED_COMMAND = "feeder/control/dispense";
const char* TOPIC_FEED_STATUS = "feeder/status/fed";
const char* TOPIC_CAT_DETECTED = "feeder/status/cat_detected";
const char* TOPIC_HEARTBEAT = "feeder/status/heartbeat";

// ============================================================================
// Global Variables
// ============================================================================

WiFiClient wifiClient;
PubSubClient mqttClient(wifiClient);

// State variables
bool isFeeding = false;
bool lastButtonState = HIGH;  // Pull-up, so HIGH when not pressed
unsigned long lastDebounceTime = 0;
unsigned long debounceDelay = 50;
unsigned long lastHeartbeat = 0;
unsigned long heartbeatInterval = 30000;  // 30 seconds
unsigned long feedStartTime = 0;
unsigned long feedDuration = 3000;  // 3 seconds feeding simulation

// Current feeding command context (for response)
String currentCommandId = "";
String currentFeedSource = "manual";
String currentScheduleName = "";
String currentScheduleId = "";
int currentFeedAmount = 50;

// ============================================================================
// Setup
// ============================================================================

void setup() {
  Serial.begin(115200);
  Serial.println();
  Serial.println();
  Serial.println("=======================================");
  Serial.println("Smart Cat Feeder - ESP8266 Node");
  Serial.println("=======================================");
  
  // Initialize pins
  pinMode(LED_BUILTIN_PIN, OUTPUT);
  pinMode(LED_ACTUATOR_PIN, OUTPUT);
  pinMode(BUTTON_PIN, INPUT_PULLUP);
  
  digitalWrite(LED_BUILTIN_PIN, HIGH);  // Turn off (active LOW)
  digitalWrite(LED_ACTUATOR_PIN, LOW);  // Turn off
  
  // Connect to WiFi
  setupWiFi();
  
  // Setup MQTT
  mqttClient.setServer(MQTT_BROKER, MQTT_PORT);
  mqttClient.setCallback(mqttCallback);
  mqttClient.setBufferSize(512);  // Increase buffer for JSON messages
  
  // Connect to MQTT
  connectMQTT();
  
  Serial.println("[OK] Setup complete!");
  Serial.println("Press the button to simulate cat detection");
  Serial.println();
  
  // Blink LED 5 times to confirm setup is complete (visual test)
  Serial.println("[INFO] Blinking LED 5 times to confirm...");
  for (int i = 0; i < 5; i++) {
    digitalWrite(LED_BUILTIN_PIN, LOW);   // ON (active LOW)
    digitalWrite(LED_ACTUATOR_PIN, HIGH); // ON
    delay(200);
    digitalWrite(LED_BUILTIN_PIN, HIGH);  // OFF
    digitalWrite(LED_ACTUATOR_PIN, LOW);  // OFF
    delay(200);
  }
  Serial.println("[INFO] LED test complete. If you didn't see blinking, check your LED/pin.");
}

// ============================================================================
// WiFi Setup
// ============================================================================

void setupWiFi() {
  Serial.print("[WIFI] Connecting to: ");
  Serial.println(WIFI_SSID);
  
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 30) {
    delay(500);
    Serial.print(".");
    digitalWrite(LED_BUILTIN_PIN, !digitalRead(LED_BUILTIN_PIN));  // Blink while connecting
    attempts++;
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println();
    Serial.println("[OK] WiFi connected!");
    Serial.print("     IP address: ");
    Serial.println(WiFi.localIP());
    digitalWrite(LED_BUILTIN_PIN, HIGH);  // Turn off LED
  } else {
    Serial.println();
    Serial.println("[ERROR] WiFi connection failed!");
    // In production, you might want to enter a config portal here
  }
}

// ============================================================================
// MQTT Connection
// ============================================================================

void connectMQTT() {
  while (!mqttClient.connected()) {
    Serial.print("[MQTT] Connecting to broker: ");
    Serial.print(MQTT_BROKER);
    Serial.print("...");
    
    if (mqttClient.connect(MQTT_CLIENT_ID)) {
      Serial.println(" OK!");
      
      // Subscribe to control topics
      mqttClient.subscribe(TOPIC_FEED_COMMAND);
      Serial.print("       Subscribed to: ");
      Serial.println(TOPIC_FEED_COMMAND);
      
      // Send initial heartbeat
      sendHeartbeat();
      
    } else {
      Serial.print(" FAILED, rc=");
      Serial.print(mqttClient.state());
      Serial.println(" - retrying in 5 seconds");
      delay(5000);
    }
  }
}

// ============================================================================
// MQTT Callback - Handle incoming messages
// ============================================================================

void mqttCallback(char* topic, byte* payload, unsigned int length) {
  // Convert payload to string
  char message[length + 1];
  memcpy(message, payload, length);
  message[length] = '\0';
  
  Serial.println();
  Serial.print("[MQTT-RX] [");
  Serial.print(topic);
  Serial.print("]: ");
  Serial.println(message);
  
  // Parse JSON
  StaticJsonDocument<256> doc;
  DeserializationError error = deserializeJson(doc, message);
  
  if (error) {
    Serial.print("[ERROR] JSON parse error: ");
    Serial.println(error.c_str());
    return;
  }
  
  // Handle feed command
  if (strcmp(topic, TOPIC_FEED_COMMAND) == 0) {
    // Check for "command" or "type" field (gateway sends "type")
    const char* command = doc["command"] | doc["type"];
    if (command && strcmp(command, "feed") == 0) {
      int amount = doc["amount"] | 50;
      const char* reqUserId = doc["userId"];
      
      // Store command context for response (unified schema support)
      currentCommandId = doc["commandId"] | "";
      currentFeedSource = doc["source"] | "manual";
      currentScheduleName = doc["scheduleName"] | "";
      currentScheduleId = doc["scheduleId"] | "";
      currentFeedAmount = amount;
      
      Serial.print("[FEED] Feed command received! Amount: ");
      Serial.print(amount);
      Serial.print("g, commandId: ");
      Serial.println(currentCommandId);
      
      triggerFeeding(amount, reqUserId);
    }
  }
}

// ============================================================================
// Feeding Logic
// ============================================================================

void triggerFeeding(int amount, const char* reqUserId) {
  if (isFeeding) {
    Serial.println("[WARN] Already feeding, ignoring command");
    return;
  }
  
  isFeeding = true;
  feedStartTime = millis();
  
  // Turn on actuator LED (simulating servo/motor)
  digitalWrite(LED_ACTUATOR_PIN, HIGH);
  digitalWrite(LED_BUILTIN_PIN, LOW);  // Turn on built-in LED too
  
  Serial.println("[FEED] Dispensing food...");
  
  // In a real implementation, you would:
  // 1. Activate servo to open food gate
  // 2. Monitor load cell for portion size
  // 3. Close gate when amount is reached
  
  // For demo, we just wait for feedDuration
  // The actual completion is handled in loop()
  
  // Store the user ID for the completion message
  // (In production, use proper state management)
}

void completeFeedingCycle(const char* userId) {
  isFeeding = false;
  
  // Turn off actuator LED
  digitalWrite(LED_ACTUATOR_PIN, LOW);
  digitalWrite(LED_BUILTIN_PIN, HIGH);
  
  Serial.println("[OK] Feeding complete!");
  
  // Send completion status to gateway (unified schema)
  StaticJsonDocument<512> doc;
  doc["userId"] = userId ? userId : USER_ID;
  doc["success"] = true;
  doc["amount"] = currentFeedAmount;  // In production, read from load cell
  doc["timestamp"] = millis();
  
  // Include command tracking info for gateway to update Firestore
  if (currentCommandId.length() > 0) {
    doc["commandId"] = currentCommandId;
  }
  doc["type"] = currentFeedSource;  // 'manual' or 'scheduled'
  if (currentScheduleName.length() > 0) {
    doc["scheduleName"] = currentScheduleName;
  }
  if (currentScheduleId.length() > 0) {
    doc["scheduleId"] = currentScheduleId;
  }
  
  char buffer[512];
  serializeJson(doc, buffer);
  
  mqttClient.publish(TOPIC_FEED_STATUS, buffer);
  Serial.print("[TX] Published to ");
  Serial.print(TOPIC_FEED_STATUS);
  Serial.print(": ");
  Serial.println(buffer);
  
  // Reset command context
  currentCommandId = "";
  currentFeedSource = "manual";
  currentScheduleName = "";
  currentScheduleId = "";
  currentFeedAmount = 50;
}

// ============================================================================
// Cat Detection
// ============================================================================

void handleButtonPress() {
  // Send cat detected message
  Serial.println("[CAT] Cat detected! (button pressed)");
  
  StaticJsonDocument<128> doc;
  doc["userId"] = USER_ID;
  doc["detected"] = true;
  doc["timestamp"] = millis();
  
  char buffer[128];
  serializeJson(doc, buffer);
  
  mqttClient.publish(TOPIC_CAT_DETECTED, buffer);
  Serial.print("[TX] Published to ");
  Serial.print(TOPIC_CAT_DETECTED);
  Serial.print(": ");
  Serial.println(buffer);
  
  // Blink LED to confirm
  for (int i = 0; i < 3; i++) {
    digitalWrite(LED_BUILTIN_PIN, LOW);
    delay(100);
    digitalWrite(LED_BUILTIN_PIN, HIGH);
    delay(100);
  }
}

// ============================================================================
// Heartbeat
// ============================================================================

void sendHeartbeat() {
  StaticJsonDocument<128> doc;
  doc["deviceId"] = MQTT_CLIENT_ID;
  doc["uptime"] = millis() / 1000;  // Uptime in seconds
  doc["wifi_rssi"] = WiFi.RSSI();
  doc["free_heap"] = ESP.getFreeHeap();
  
  char buffer[128];
  serializeJson(doc, buffer);
  
  mqttClient.publish(TOPIC_HEARTBEAT, buffer);
  Serial.println("[HEARTBEAT] Sent");
}

// ============================================================================
// Main Loop
// ============================================================================

void loop() {
  // Ensure MQTT connection
  if (!mqttClient.connected()) {
    connectMQTT();
  }
  mqttClient.loop();
  
  // Handle feeding completion (non-blocking)
  if (isFeeding && (millis() - feedStartTime >= feedDuration)) {
    completeFeedingCycle(USER_ID);
  }
  
  // --- Debounced button handling (active LOW with INPUT_PULLUP) ---
  static int lastReading = HIGH;        // raw last read
  static int stableState = HIGH;        // debounced stable state
  static unsigned long lastChangeMs = 0;

  int reading = digitalRead(BUTTON_PIN);

  if (reading != lastReading) {
    lastChangeMs = millis();            // reset debounce timer
    lastReading = reading;
  }

  if ((millis() - lastChangeMs) > debounceDelay) {
    if (reading != stableState) {
      stableState = reading;

      // Detect press (HIGH -> LOW)
      if (stableState == LOW) {
        handleButtonPress();
      }
    }
  }

  
  // Small delay to prevent watchdog issues
  delay(10);
}

// ============================================================================
// Utility Functions (for future expansion)
// ============================================================================

/**
 * In a full implementation, you would add:
 * 
 * void readLoadCell() {
 *   // Read weight from HX711 + load cell
 *   // hx711.read() -> grams
 * }
 * 
 * void readIRSensor() {
 *   // Read IR proximity sensor for cat detection
 *   // digitalRead(IR_SENSOR_PIN)
 * }
 * 
 * void readUltrasonic() {
 *   // Read ultrasonic sensor for cat detection
 *   // Calculate distance from echo time
 * }
 * 
 * void controlServo(int angle) {
 *   // Control servo for food gate
 *   // servo.write(angle)
 * }
 */

