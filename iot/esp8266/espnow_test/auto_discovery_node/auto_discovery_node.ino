/**
 * ESP-NOW Auto-Discovery Node - WITH WIFI
 * =========================================
 * 
 * Proves ESP-NOW and WiFi can work simultaneously!
 * 
 * IMPORTANT: ESP-NOW and WiFi MUST use the same channel.
 * When connected to WiFi, the channel is set by the AP.
 * 
 * Flash this to all ESP8266 nodes - just change NODE_ID.
 */

#include <ESP8266WiFi.h>
#include <espnow.h>

// ============================================================================
// CONFIGURATION - Change these!
// ============================================================================
#define NODE_ID 'W'  // Change to 'X', 'Y', 'Z' for other nodes

// WiFi credentials (to prove both work together)
const char* WIFI_SSID = "Aser";           // Your WiFi SSID
const char* WIFI_PASS = "1234567899abc";  // Your WiFi password

// ============================================================================
// SIMPLE MESSAGE STRUCTURE (packed to avoid alignment issues)
// ============================================================================
struct __attribute__((packed)) Message {
  uint8_t type;        // 1 = discovery, 2 = ack, 3 = data
  char nodeId;         // 'W', 'X', 'Y', 'Z'
  uint32_t counter;    // Message counter
  float value;         // Sensor value (for data messages)
};

// ============================================================================
// PEER STORAGE
// ============================================================================
#define MAX_PEERS 4
struct Peer {
  bool active;
  char nodeId;
  uint8_t mac[6];
  uint32_t lastSeen;
};
Peer peers[MAX_PEERS];

// Broadcast MAC
uint8_t BROADCAST[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};

// Stats
volatile uint32_t txCount = 0;
volatile uint32_t rxCount = 0;
volatile uint32_t txOk = 0;
volatile uint32_t txFail = 0;

// Deferred ACK
volatile bool needAck = false;
uint8_t ackMac[6];

// Timers
uint32_t lastDiscovery = 0;
uint32_t lastData = 0;
uint32_t lastWifiCheck = 0;
uint32_t msgCounter = 0;

// WiFi status
bool wifiConnected = false;
int wifiChannel = 1;

// ============================================================================
// MAC ADDRESS HELPERS
// ============================================================================
void printMac(uint8_t *mac) {
  Serial.printf("%02X:%02X:%02X:%02X:%02X:%02X", 
    mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
}

// ============================================================================
// PEER MANAGEMENT
// ============================================================================
int findPeer(uint8_t *mac) {
  for (int i = 0; i < MAX_PEERS; i++) {
    if (peers[i].active && memcmp(peers[i].mac, mac, 6) == 0) {
      return i;
    }
  }
  return -1;
}

bool addPeer(uint8_t *mac, char nodeId) {
  // Already exists?
  int idx = findPeer(mac);
  if (idx >= 0) {
    peers[idx].lastSeen = millis();
    return false;  // Not new
  }
  
  // Find empty slot
  for (int i = 0; i < MAX_PEERS; i++) {
    if (!peers[i].active) {
      peers[i].active = true;
      peers[i].nodeId = nodeId;
      memcpy(peers[i].mac, mac, 6);
      peers[i].lastSeen = millis();
      return true;  // New peer
    }
  }
  return false;
}

void registerPeerForSend(uint8_t *mac) {
  // Try to add - if already exists, that's OK
  // Use current WiFi channel for ESP-NOW peers
  esp_now_add_peer(mac, ESP_NOW_ROLE_COMBO, wifiChannel, NULL, 0);
}

// ============================================================================
// WIFI FUNCTIONS
// ============================================================================
void connectWiFi() {
  Serial.printf("\n[WIFI] Connecting to %s", WIFI_SSID);
  
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 20) {
    delay(500);
    Serial.print(".");
    attempts++;
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    wifiConnected = true;
    wifiChannel = WiFi.channel();
    Serial.println(" OK!");
    Serial.printf("[WIFI] IP: %s\n", WiFi.localIP().toString().c_str());
    Serial.printf("[WIFI] Channel: %d (ESP-NOW will use this too)\n", wifiChannel);
    Serial.printf("[WIFI] RSSI: %d dBm\n", WiFi.RSSI());
  } else {
    wifiConnected = false;
    Serial.println(" FAILED!");
    Serial.println("[WIFI] Continuing with ESP-NOW only");
  }
}

void checkWiFiStatus() {
  bool currentStatus = (WiFi.status() == WL_CONNECTED);
  
  if (currentStatus != wifiConnected) {
    if (currentStatus) {
      wifiConnected = true;
      wifiChannel = WiFi.channel();
      Serial.printf("[WIFI] Reconnected! IP: %s, Channel: %d\n", 
        WiFi.localIP().toString().c_str(), wifiChannel);
    } else {
      wifiConnected = false;
      Serial.println("[WIFI] Connection lost!");
    }
  }
}

// ============================================================================
// CALLBACKS - Keep these MINIMAL!
// ============================================================================
void onSent(uint8_t *mac, uint8_t status) {
  if (status == 0) txOk++;
  else txFail++;
}

void onRecv(uint8_t *mac, uint8_t *data, uint8_t len) {
  if (len < sizeof(Message)) return;
  
  Message *msg = (Message*)data;
  
  // Ignore our own messages
  if (msg->nodeId == NODE_ID) return;
  
  rxCount++;
  
  // ALWAYS update lastSeen for existing peer, or add new peer
  int idx = findPeer(mac);
  if (idx >= 0) {
    // Existing peer - just update timestamp
    peers[idx].lastSeen = millis();
  } else {
    // New peer - add it
    addPeer(mac, msg->nodeId);
  }
  
  if (msg->type == 1) {  // Discovery
    // Schedule ACK (don't send here!)
    if (!needAck) {
      needAck = true;
      memcpy(ackMac, mac, 6);
    }
  }
}

// ============================================================================
// SEND FUNCTIONS (called from loop only!)
// ============================================================================
void sendDiscovery() {
  Message msg;
  msg.type = 1;  // Discovery
  msg.nodeId = NODE_ID;
  msg.counter = ++msgCounter;
  msg.value = 0;
  
  int result = esp_now_send(BROADCAST, (uint8_t*)&msg, sizeof(msg));
  txCount++;
  
  if (result == 0) {
    Serial.printf("[TX] Discovery broadcast #%u\n", msgCounter);
  } else {
    Serial.printf("[TX] Discovery FAILED (err=%d)\n", result);
  }
}

void sendAck(uint8_t *mac) {
  registerPeerForSend(mac);
  
  Message msg;
  msg.type = 2;  // ACK
  msg.nodeId = NODE_ID;
  msg.counter = ++msgCounter;
  msg.value = 0;
  
  int result = esp_now_send(mac, (uint8_t*)&msg, sizeof(msg));
  txCount++;
  
  Serial.print("[TX] ACK to ");
  printMac(mac);
  Serial.println(result == 0 ? " OK" : " FAIL");
}

void sendData() {
  int sent = 0;
  for (int i = 0; i < MAX_PEERS; i++) {
    if (peers[i].active) {
      registerPeerForSend(peers[i].mac);
      
      Message msg;
      msg.type = 3;  // Data
      msg.nodeId = NODE_ID;
      msg.counter = ++msgCounter;
      msg.value = random(0, 1000) / 10.0;
      
      esp_now_send(peers[i].mac, (uint8_t*)&msg, sizeof(msg));
      txCount++;
      sent++;
      
      Serial.printf("[TX] Data #%u (%.1f) to Node %c\n", 
        msg.counter, msg.value, peers[i].nodeId);
      
      yield();
    }
  }
  
  if (sent == 0) {
    Serial.println("[TX] No peers yet");
  }
}

// ============================================================================
// PRINT STATUS
// ============================================================================
void printStatus() {
  Serial.println("\n========== STATUS ==========");
  Serial.printf("Node: %c | TX: %u (OK:%u FAIL:%u) | RX: %u\n", 
    NODE_ID, txCount, txOk, txFail, rxCount);
  
  // WiFi status
  if (wifiConnected) {
    Serial.printf("WiFi: CONNECTED to %s (Ch:%d, RSSI:%d)\n", 
      WIFI_SSID, wifiChannel, WiFi.RSSI());
    Serial.printf("  IP: %s\n", WiFi.localIP().toString().c_str());
  } else {
    Serial.println("WiFi: DISCONNECTED");
  }
  
  Serial.println("ESP-NOW Peers:");
  int count = 0;
  for (int i = 0; i < MAX_PEERS; i++) {
    if (peers[i].active) {
      Serial.printf("  [%c] ", peers[i].nodeId);
      printMac(peers[i].mac);
      Serial.printf(" (seen %us ago)\n", (millis() - peers[i].lastSeen) / 1000);
      count++;
    }
  }
  if (count == 0) Serial.println("  (none)");
  Serial.println("============================\n");
}

// ============================================================================
// SETUP
// ============================================================================
void setup() {
  Serial.begin(115200);
  delay(500);
  
  Serial.println("\n\n=====================================");
  Serial.println("ESP-NOW + WiFi Coexistence Test");
  Serial.println("=====================================");
  Serial.printf("Node ID: %c\n", NODE_ID);
  
  // Init peer table
  for (int i = 0; i < MAX_PEERS; i++) {
    peers[i].active = false;
  }
  
  // WiFi setup - MUST be STA mode for ESP-NOW + WiFi to coexist
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  delay(100);
  
  Serial.print("MAC: ");
  Serial.println(WiFi.macAddress());
  
  // Connect to WiFi FIRST (this sets the channel)
  connectWiFi();
  
  // ESP-NOW setup AFTER WiFi connection
  // This ensures ESP-NOW uses the same channel as WiFi
  if (esp_now_init() != 0) {
    Serial.println("ESP-NOW init FAILED!");
    delay(1000);
    ESP.restart();
  }
  
  esp_now_set_self_role(ESP_NOW_ROLE_COMBO);
  esp_now_register_send_cb(onSent);
  esp_now_register_recv_cb(onRecv);
  
  // Add broadcast peer with the WiFi channel
  if (esp_now_add_peer(BROADCAST, ESP_NOW_ROLE_COMBO, wifiChannel, NULL, 0) != 0) {
    Serial.println("Failed to add broadcast peer!");
  }
  
  Serial.println("\nBoth ESP-NOW and WiFi are now active!");
  Serial.println("ESP-NOW messages will work alongside WiFi.\n");
  
  pinMode(LED_BUILTIN, OUTPUT);
  digitalWrite(LED_BUILTIN, HIGH);
  
  // Wait a bit before first send
  delay(500);
  lastDiscovery = millis();
  lastData = millis();
  lastWifiCheck = millis();
}

// ============================================================================
// LOOP
// ============================================================================
void loop() {
  uint32_t now = millis();
  
  // Handle deferred ACK
  if (needAck) {
    needAck = false;
    Serial.print("[RX] Discovery from peer, sending ACK to ");
    printMac(ackMac);
    Serial.println();
    sendAck(ackMac);
  }
  
  // Check WiFi status every 10 seconds
  if (now - lastWifiCheck >= 10000) {
    checkWiFiStatus();
    lastWifiCheck = now;
    
    // If WiFi disconnected, try to reconnect
    if (!wifiConnected) {
      Serial.println("[WIFI] Attempting reconnect...");
      connectWiFi();
    }
  }
  
  // Discovery every 5 seconds
  if (now - lastDiscovery >= 5000) {
    sendDiscovery();
    lastDiscovery = now;
    yield();
  }
  
  // Data every 3 seconds
  if (now - lastData >= 3000) {
    sendData();
    printStatus();
    lastData = now;
  }
  
  // LED blink - fast if WiFi connected, slow if not
  static uint32_t lastBlink = 0;
  int blinkInterval = wifiConnected ? 1000 : 2000;
  if (now - lastBlink >= blinkInterval) {
    digitalWrite(LED_BUILTIN, LOW);
    delay(wifiConnected ? 20 : 100);  // Short blink if connected
    digitalWrite(LED_BUILTIN, HIGH);
    lastBlink = now;
  }
  
  // Cleanup old peers (5 minute timeout - very generous)
  for (int i = 0; i < MAX_PEERS; i++) {
    if (peers[i].active && (now - peers[i].lastSeen) > 300000) {
      Serial.printf("[PEER] Node %c timed out (no msg for 5min)\n", peers[i].nodeId);
      peers[i].active = false;
    }
  }
  
  yield();
  delay(10);
}
