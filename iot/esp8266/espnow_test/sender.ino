/**
 * ESP-NOW Test - SENDER
 * ======================
 * 
 * Flash this to ESP8266 #1
 * Sends a counter message every 2 seconds via ESP-NOW
 * 
 * Hardware: Any ESP8266 (NodeMCU, Wemos D1, etc.)
 * 
 * IMPORTANT: 
 * 1. Flash receiver.ino to ESP #2 FIRST
 * 2. Copy the MAC address printed by receiver
 * 3. Paste it in RECEIVER_MAC below
 * 4. Flash this sketch to ESP #1
 */

#include <ESP8266WiFi.h>
#include <espnow.h>

// ============================================================================
// CONFIGURATION - UPDATE THIS!
// ============================================================================
// Replace with your RECEIVER's MAC address (printed by receiver on boot)
uint8_t RECEIVER_MAC[] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};  // Broadcast (for initial test)
// Example: {0x2C, 0x3A, 0xE8, 0x12, 0x34, 0x56}

// ============================================================================
// DATA STRUCTURE (must match receiver)
// ============================================================================
typedef struct {
  uint32_t messageId;
  char senderNode[4];
  float sensorValue;
  uint32_t timestamp;
} ESPNowMessage;

ESPNowMessage outgoingMessage;

// Stats
uint32_t messageCounter = 0;
uint32_t successCount = 0;
uint32_t failCount = 0;

// ============================================================================
// CALLBACK - Called when data is sent
// ============================================================================
void onDataSent(uint8_t *mac_addr, uint8_t sendStatus) {
  if (sendStatus == 0) {
    Serial.printf("\n[TX] Message #%u -> DELIVERED\n", outgoingMessage.messageId);
    successCount++;
  } else {
    Serial.printf("\n[TX] Message #%u -> FAILED\n", outgoingMessage.messageId);
    failCount++;
  }
  
  Serial.printf("     Stats: %u sent, %u delivered, %u failed (%.1f%% success)\n",
                messageCounter, successCount, failCount,
                messageCounter > 0 ? (100.0 * successCount / messageCounter) : 0);
}

// ============================================================================
// SETUP
// ============================================================================
void setup() {
  Serial.begin(115200);
  delay(1000);
  
  Serial.println();
  Serial.println();
  Serial.println("========================================================");
  Serial.println("          ESP-NOW TEST - SENDER");
  Serial.println("========================================================");
  
  // Print this device's MAC address
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  Serial.print("[INFO] This SENDER's MAC: ");
  Serial.println(WiFi.macAddress());
  
  // Initialize ESP-NOW
  if (esp_now_init() != 0) {
    Serial.println("[ERROR] ESP-NOW init failed!");
    return;
  }
  Serial.println("[OK] ESP-NOW initialized");
  
  // Set role and callback
  esp_now_set_self_role(ESP_NOW_ROLE_CONTROLLER);
  esp_now_register_send_cb(onDataSent);
  
  // Add peer (receiver)
  esp_now_add_peer(RECEIVER_MAC, ESP_NOW_ROLE_SLAVE, 1, NULL, 0);
  
  Serial.println();
  Serial.println("[INFO] Starting transmission in 3 seconds...");
  Serial.println("       Watch the RECEIVER's serial monitor for incoming messages!");
  Serial.println();
  delay(3000);
}

// ============================================================================
// LOOP - Send message every 2 seconds
// ============================================================================
void loop() {
  // Prepare message
  messageCounter++;
  outgoingMessage.messageId = messageCounter;
  strcpy(outgoingMessage.senderNode, "SND");
  outgoingMessage.sensorValue = random(0, 1000) / 10.0;  // Fake sensor: 0.0 - 100.0
  outgoingMessage.timestamp = millis();
  
  Serial.println("-------------------------------------------------");
  Serial.printf("[TX] Sending message #%u\n", messageCounter);
  Serial.printf("     Node: %s, Value: %.1f, Time: %u ms\n",
                outgoingMessage.senderNode,
                outgoingMessage.sensorValue,
                outgoingMessage.timestamp);
  
  // Send via ESP-NOW
  esp_now_send(RECEIVER_MAC, (uint8_t *)&outgoingMessage, sizeof(outgoingMessage));
  
  delay(2000);  // Send every 2 seconds
}
