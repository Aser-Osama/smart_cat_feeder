/**
 * ESP-NOW Fixed Channel Test
 * ===========================
 * 
 * Tests ESP-NOW with FIXED CHANNEL - works with or without WiFi!
 * 
 * TEST MODES:
 * 1. WIFI_MODE = true  -> Connect WiFi, verify channel matches
 * 2. WIFI_MODE = false -> No WiFi, use fixed channel only
 * 
 * Both nodes MUST use same FIXED_CHANNEL to communicate!
 * 
 * Flash to two ESP8266s with different NODE_IDs.
 */

#include <ESP8266WiFi.h>
#include <espnow.h>

// ============================================================================
// CONFIGURATION - CHANGE THESE!
// ============================================================================
#define NODE_ID 'W'              // Change to 'X' for second node

#define WIFI_MODE false           // true = try WiFi, false = ESP-NOW only
#define FIXED_CHANNEL 11         // MUST MATCH ON ALL NODES!

// WiFi credentials (only used if WIFI_MODE = true)
const char* WIFI_SSID = "Aser";
const char* WIFI_PASS = "1234567899abc";

// ============================================================================
// MESSAGE STRUCTURE - includes channel for verification
// ============================================================================
struct __attribute__((packed)) Message {
  uint8_t type;        // 1 = discovery, 2 = ack, 3 = data
  char nodeId;         // 'W', 'X', 'Y', 'Z'
  uint8_t channel;     // Sender's channel (for verification!)
  uint32_t counter;    // Message counter
  float value;         // Test value
};

// ============================================================================
// GLOBALS
// ============================================================================
#define MAX_PEERS 4
struct Peer {
  bool active;
  char nodeId;
  uint8_t mac[6];
  uint8_t channel;     // Their reported channel
  uint32_t lastSeen;
};
Peer peers[MAX_PEERS];

uint8_t BROADCAST[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};

volatile uint32_t txCount = 0;
volatile uint32_t rxCount = 0;
volatile uint32_t txOk = 0;
volatile uint32_t txFail = 0;

volatile bool needAck = false;
uint8_t ackMac[6];
uint8_t ackChannel = 0;

uint32_t lastDiscovery = 0;
uint32_t lastData = 0;
uint32_t lastStatus = 0;
uint32_t msgCounter = 0;

bool wifiConnected = false;
uint8_t currentChannel = FIXED_CHANNEL;

// ============================================================================
// HELPERS
// ============================================================================
void printMac(uint8_t *mac) {
  Serial.printf("%02X:%02X:%02X:%02X:%02X:%02X", 
    mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
}

uint8_t getActualChannel() {
  return wifi_get_channel();
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

bool addOrUpdatePeer(uint8_t *mac, char nodeId, uint8_t channel) {
  int idx = findPeer(mac);
  if (idx >= 0) {
    peers[idx].lastSeen = millis();
    peers[idx].channel = channel;
    return false;  // Updated, not new
  }
  
  for (int i = 0; i < MAX_PEERS; i++) {
    if (!peers[i].active) {
      peers[i].active = true;
      peers[i].nodeId = nodeId;
      memcpy(peers[i].mac, mac, 6);
      peers[i].channel = channel;
      peers[i].lastSeen = millis();
      return true;  // New peer
    }
  }
  return false;
}

// ============================================================================
// ESP-NOW CALLBACKS
// ============================================================================
void onSent(uint8_t *mac, uint8_t status) {
  if (status == 0) txOk++;
  else txFail++;
}

void onRecv(uint8_t *mac, uint8_t *data, uint8_t len) {
  if (len < sizeof(Message)) return;
  
  Message *msg = (Message*)data;
  if (msg->nodeId == NODE_ID) return;  // Ignore own
  
  rxCount++;
  
  uint8_t myChannel = getActualChannel();
  
  // *** CHANNEL VERIFICATION - THIS IS THE KEY TEST! ***
  Serial.println("\n╔══════════════════════════════════════════════════════╗");
  Serial.printf("║ 📡 RECEIVED from Node %c                              ║\n", msg->nodeId);
  Serial.printf("║   Their channel: %2d                                  ║\n", msg->channel);
  Serial.printf("║   My channel:    %2d                                  ║\n", myChannel);
  if (msg->channel == myChannel) {
    Serial.println("║   ✅ CHANNELS MATCH - ESP-NOW WORKING!               ║");
  } else {
    Serial.println("║   ⚠️  CHANNEL MISMATCH (but msg received?!)          ║");
  }
  Serial.println("╚══════════════════════════════════════════════════════╝");
  
  addOrUpdatePeer(mac, msg->nodeId, msg->channel);
  
  if (msg->type == 1) {  // Discovery - schedule ACK
    if (!needAck) {
      needAck = true;
      memcpy(ackMac, mac, 6);
      ackChannel = msg->channel;
    }
  }
  
  if (msg->type == 3) {  // Data
    Serial.printf("   Data value: %.2f, counter: %u\n", msg->value, msg->counter);
  }
}

// ============================================================================
// SEND FUNCTIONS
// ============================================================================
void sendDiscovery() {
  Message msg;
  msg.type = 1;
  msg.nodeId = NODE_ID;
  msg.channel = getActualChannel();
  msg.counter = ++msgCounter;
  msg.value = 0;
  
  int result = esp_now_send(BROADCAST, (uint8_t*)&msg, sizeof(msg));
  txCount++;
  
  Serial.printf("[TX] Discovery #%u (ch:%d) %s\n", 
    msgCounter, msg.channel, result == 0 ? "OK" : "FAIL");
}

void sendAck(uint8_t *mac) {
  esp_now_add_peer(mac, ESP_NOW_ROLE_COMBO, currentChannel, NULL, 0);
  
  Message msg;
  msg.type = 2;
  msg.nodeId = NODE_ID;
  msg.channel = getActualChannel();
  msg.counter = ++msgCounter;
  msg.value = 0;
  
  int result = esp_now_send(mac, (uint8_t*)&msg, sizeof(msg));
  txCount++;
  
  Serial.print("[TX] ACK to ");
  printMac(mac);
  Serial.printf(" (ch:%d) %s\n", msg.channel, result == 0 ? "OK" : "FAIL");
}

void sendData() {
  for (int i = 0; i < MAX_PEERS; i++) {
    if (peers[i].active) {
      esp_now_add_peer(peers[i].mac, ESP_NOW_ROLE_COMBO, currentChannel, NULL, 0);
      
      Message msg;
      msg.type = 3;
      msg.nodeId = NODE_ID;
      msg.channel = getActualChannel();
      msg.counter = ++msgCounter;
      msg.value = random(0, 1000) / 10.0;
      
      esp_now_send(peers[i].mac, (uint8_t*)&msg, sizeof(msg));
      txCount++;
      
      Serial.printf("[TX] Data #%u (%.1f) to Node %c (ch:%d)\n", 
        msg.counter, msg.value, peers[i].nodeId, msg.channel);
      yield();
    }
  }
}

// ============================================================================
// STATUS
// ============================================================================
void printStatus() {
  uint8_t ch = getActualChannel();
  
  Serial.println("\n╔══════════════════════════════════════════════════════╗");
  Serial.println("║              FIXED CHANNEL TEST STATUS               ║");
  Serial.println("╠══════════════════════════════════════════════════════╣");
  Serial.printf("║ Node: %c | Channel: %2d (%s)               ║\n", 
    NODE_ID, ch, wifiConnected ? "WiFi" : "FIXED");
  Serial.printf("║ WiFi: %-12s                                ║\n",
    wifiConnected ? "CONNECTED" : "DISABLED");
  Serial.printf("║ TX: %4u (OK:%4u FAIL:%4u) | RX: %4u              ║\n", 
    txCount, txOk, txFail, rxCount);
  Serial.println("╠══════════════════════════════════════════════════════╣");
  
  int peerCount = 0;
  for (int i = 0; i < MAX_PEERS; i++) {
    if (peers[i].active) peerCount++;
  }
  
  if (peerCount == 0) {
    Serial.println("║ Peers: (none discovered yet)                         ║");
  } else {
    Serial.println("║ Peers:                                               ║");
    for (int i = 0; i < MAX_PEERS; i++) {
      if (peers[i].active) {
        Serial.printf("║   [%c] ch:%2d ", peers[i].nodeId, peers[i].channel);
        printMac(peers[i].mac);
        Serial.printf(" (%lus ago)    ║\n", (millis() - peers[i].lastSeen) / 1000);
      }
    }
  }
  Serial.println("╚══════════════════════════════════════════════════════╝\n");
}

// ============================================================================
// SETUP
// ============================================================================
void setup() {
  Serial.begin(115200);
  delay(500);
  
  Serial.println("\n\n");
  Serial.println("╔══════════════════════════════════════════════════════╗");
  Serial.println("║        ESP-NOW FIXED CHANNEL TEST                    ║");
  Serial.println("╚══════════════════════════════════════════════════════╝");
  Serial.printf("Node ID: %c\n", NODE_ID);
  Serial.printf("Fixed Channel: %d\n", FIXED_CHANNEL);
  Serial.printf("WiFi Mode: %s\n", WIFI_MODE ? "ENABLED" : "DISABLED");
  
  // Init peer table
  for (int i = 0; i < MAX_PEERS; i++) {
    peers[i].active = false;
  }
  
  // WiFi setup - MUST be STA mode
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  delay(100);
  
  Serial.print("MAC: ");
  Serial.println(WiFi.macAddress());
  
  // *** KEY PART: Channel Setup ***
  if (WIFI_MODE) {
    // Try to connect to WiFi
    Serial.printf("\n[WIFI] Connecting to %s", WIFI_SSID);
    WiFi.begin(WIFI_SSID, WIFI_PASS);
    
    int attempts = 0;
    while (WiFi.status() != WL_CONNECTED && attempts < 30) {  // Increased to 30 attempts (15 sec)
      delay(500);
      Serial.print(".");
      attempts++;
      
      // Print status every 5 attempts
      if (attempts % 5 == 0) {
        Serial.printf(" [status:%d]", WiFi.status());
        // Status codes: 0=IDLE, 1=NO_SSID_AVAIL, 2=SCAN_COMPLETED, 3=CONNECTED, 4=CONNECT_FAILED, 5=CONNECTION_LOST, 6=DISCONNECTED
      }
    }
    
    if (WiFi.status() == WL_CONNECTED) {
      wifiConnected = true;
      currentChannel = WiFi.channel();
      Serial.println(" OK!");
      Serial.printf("[WIFI] IP: %s\n", WiFi.localIP().toString().c_str());
      Serial.printf("[WIFI] Channel: %d (will use this for ESP-NOW)\n", currentChannel);
      Serial.printf("[WIFI] RSSI: %d dBm\n", WiFi.RSSI());
      
      // Verify channel matches expected
      if (currentChannel != FIXED_CHANNEL) {
        Serial.println("\n⚠️  WARNING: WiFi channel differs from FIXED_CHANNEL!");
        Serial.printf("   WiFi is on channel %d, FIXED_CHANNEL is %d\n", currentChannel, FIXED_CHANNEL);
        Serial.println("   Nodes without WiFi won't be able to communicate!");
        Serial.println("   Consider changing your router's channel or FIXED_CHANNEL.\n");
      }
    } else {
      wifiConnected = false;
      Serial.printf(" FAILED! (status: %d)\n", WiFi.status());
      Serial.println("   0=IDLE, 1=NO_SSID, 4=CONNECT_FAILED, 6=DISCONNECTED");
      Serial.println("[WIFI] Will use FIXED_CHANNEL instead");
      currentChannel = FIXED_CHANNEL;
      wifi_set_channel(currentChannel);
      Serial.printf("[CHANNEL] Forced to: %d\n", currentChannel);
    }
  } else {
    // No WiFi - use fixed channel
    Serial.println("\n[WIFI] Disabled by config");
    wifiConnected = false;
    currentChannel = FIXED_CHANNEL;
    wifi_set_channel(currentChannel);
    Serial.printf("[CHANNEL] Set to FIXED: %d\n", currentChannel);
  }
  
  // Verify actual channel
  uint8_t actualCh = getActualChannel();
  Serial.printf("[VERIFY] Actual channel from SDK: %d\n", actualCh);
  
  // ESP-NOW setup
  if (esp_now_init() != 0) {
    Serial.println("ESP-NOW init FAILED!");
    delay(1000);
    ESP.restart();
  }
  
  esp_now_set_self_role(ESP_NOW_ROLE_COMBO);
  esp_now_register_send_cb(onSent);
  esp_now_register_recv_cb(onRecv);
  
  // Add broadcast peer
  if (esp_now_add_peer(BROADCAST, ESP_NOW_ROLE_COMBO, currentChannel, NULL, 0) != 0) {
    Serial.println("Failed to add broadcast peer!");
  }
  
  Serial.println("\n✅ ESP-NOW initialized!");
  Serial.println("Waiting for peers...\n");
  
  pinMode(LED_BUILTIN, OUTPUT);
  digitalWrite(LED_BUILTIN, HIGH);
  
  delay(500);
  lastDiscovery = millis();
  lastData = millis();
  lastStatus = millis();
}

// ============================================================================
// LOOP
// ============================================================================
void loop() {
  uint32_t now = millis();
  
  // Handle deferred ACK
  if (needAck) {
    needAck = false;
    sendAck(ackMac);
  }
  
  // Discovery every 5 seconds
  if (now - lastDiscovery >= 5000) {
    sendDiscovery();
    lastDiscovery = now;
  }
  
  // Data every 4 seconds (if we have peers)
  if (now - lastData >= 4000) {
    sendData();
    lastData = now;
  }
  
  // Status every 6 seconds
  if (now - lastStatus >= 6000) {
    printStatus();
    lastStatus = now;
  }
  
  // LED blink
  static uint32_t lastBlink = 0;
  if (now - lastBlink >= (wifiConnected ? 1000 : 500)) {
    digitalWrite(LED_BUILTIN, LOW);
    delay(20);
    digitalWrite(LED_BUILTIN, HIGH);
    lastBlink = now;
  }
  
  // Cleanup stale peers
  for (int i = 0; i < MAX_PEERS; i++) {
    if (peers[i].active && (now - peers[i].lastSeen) > 60000) {
      Serial.printf("[PEER] Node %c timed out\n", peers[i].nodeId);
      peers[i].active = false;
    }
  }
  
  yield();
  delay(10);
}
