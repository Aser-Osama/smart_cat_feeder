/**
 * ESP-NOW Test - RECEIVER
 * ========================
 * 
 * Flash this to ESP8266 #2 FIRST
 * Receives messages from sender and prints them
 * 
 * Hardware: Any ESP8266 (NodeMCU, Wemos D1, etc.)
 * 
 * STEPS:
 * 1. Flash this sketch to ESP #2
 * 2. Open Serial Monitor (115200 baud)
 * 3. Copy the MAC address printed on boot
 * 4. Paste it in sender.ino's RECEIVER_MAC
 * 5. Flash sender.ino to ESP #1
 * 6. Watch messages arrive here!
 */

#include <ESP8266WiFi.h>
#include <espnow.h>

// ============================================================================
// DATA STRUCTURE (must match sender)
// ============================================================================
typedef struct {
  uint32_t messageId;
  char senderNode[4];
  float sensorValue;
  uint32_t timestamp;
} ESPNowMessage;

ESPNowMessage incomingMessage;

// Stats
uint32_t receivedCount = 0;
uint32_t lastMessageId = 0;
uint32_t missedMessages = 0;

// ============================================================================
// CALLBACK - Called when data is received
// ============================================================================
void onDataReceived(uint8_t *mac, uint8_t *data, uint8_t len) {
  // Copy received data
  memcpy(&incomingMessage, data, sizeof(incomingMessage));
  receivedCount++;
  
  // Check for missed messages
  if (lastMessageId > 0 && incomingMessage.messageId > lastMessageId + 1) {
    missedMessages += (incomingMessage.messageId - lastMessageId - 1);
  }
  lastMessageId = incomingMessage.messageId;
  
  // Print received message (start with newline for async safety)
  Serial.println();
  Serial.println("=========================================================");
  Serial.printf("[RX] RECEIVED MESSAGE #%u\n", incomingMessage.messageId);
  Serial.println("=========================================================");
  
  // Sender MAC
  Serial.printf("     From MAC: %02X:%02X:%02X:%02X:%02X:%02X\n",
                mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  
  // Message contents
  Serial.printf("     Node ID:     %s\n", incomingMessage.senderNode);
  Serial.printf("     Sensor Val:  %.1f\n", incomingMessage.sensorValue);
  Serial.printf("     Sender Time: %u ms\n", incomingMessage.timestamp);
  Serial.printf("     Data Size:   %u bytes\n", len);
  
  // Stats
  Serial.println("---------------------------------------------------------");
  Serial.printf("[STATS] %u received, %u missed (%.1f%% success)\n",
                receivedCount, missedMessages,
                (receivedCount + missedMessages) > 0 
                  ? (100.0 * receivedCount / (receivedCount + missedMessages)) 
                  : 100.0);
  
  // Visual confirmation - blink built-in LED
  digitalWrite(LED_BUILTIN, LOW);   // ON (active low)
  delay(100);
  digitalWrite(LED_BUILTIN, HIGH);  // OFF
}

// ============================================================================
// SETUP
// ============================================================================
void setup() {
  Serial.begin(115200);
  delay(1000);
  
  pinMode(LED_BUILTIN, OUTPUT);
  digitalWrite(LED_BUILTIN, HIGH);  // OFF
  
  Serial.println();
  Serial.println();
  Serial.println("========================================================");
  Serial.println("          ESP-NOW TEST - RECEIVER");
  Serial.println("========================================================");
  
  // Print this device's MAC address - COPY THIS TO SENDER!
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  
  Serial.println();
  Serial.println("+----------------------------------------------------+");
  Serial.println("|  COPY THIS MAC ADDRESS TO SENDER SKETCH:           |");
  Serial.println("+----------------------------------------------------+");
  Serial.print("|    ");
  Serial.print(WiFi.macAddress());
  Serial.println("                        |");
  Serial.println("|                                                    |");
  Serial.println("|  In sender.ino, update RECEIVER_MAC like:          |");
  
  // Print in C array format
  uint8_t mac[6];
  WiFi.macAddress(mac);
  Serial.printf("|  uint8_t RECEIVER_MAC[] = {0x%02X, 0x%02X, 0x%02X, |\n", 
                mac[0], mac[1], mac[2]);
  Serial.printf("|                            0x%02X, 0x%02X, 0x%02X}; |\n",
                mac[3], mac[4], mac[5]);
  Serial.println("+----------------------------------------------------+");
  Serial.println();
  
  // Initialize ESP-NOW
  if (esp_now_init() != 0) {
    Serial.println("[ERROR] ESP-NOW init failed!");
    return;
  }
  Serial.println("[OK] ESP-NOW initialized");
  
  // Set role and callback
  esp_now_set_self_role(ESP_NOW_ROLE_SLAVE);
  esp_now_register_recv_cb(onDataReceived);
  
  Serial.println();
  Serial.println("[INFO] Listening for ESP-NOW messages...");
  Serial.println("       LED will blink on each received message.");
  Serial.println();
}

// ============================================================================
// LOOP - Just wait for callbacks
// ============================================================================
void loop() {
  // Nothing to do - everything happens in callback
  delay(100);
}
