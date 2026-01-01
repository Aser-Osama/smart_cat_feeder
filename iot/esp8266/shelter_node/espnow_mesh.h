/**
 * ESP-NOW Mesh Communication for Shelter Node
 * ============================================
 * 
 * Real ESP-NOW implementation for node-to-node communication.
 * Works alongside WiFi on the same channel.
 * 
 * Based on proven auto_discovery_node pattern.
 */

#ifndef ESPNOW_MESH_H
#define ESPNOW_MESH_H

#include <Arduino.h>
#include <ESP8266WiFi.h>
#include <espnow.h>
#include "config.h"

// ============================================================================
// MESSAGE STRUCTURES (packed to avoid alignment issues)
// ============================================================================

// Discovery/ACK message - includes channel for verification
struct __attribute__((packed)) ESPNowDiscovery {
  uint8_t type;           // MSG_TYPE_DISCOVERY or MSG_TYPE_ACK
  char nodeId;            // 'W', 'X', 'Y', 'Z'
  float batteryPercent;   // For routing decisions
  int8_t rssi;            // Sender's WiFi RSSI to sink
  uint8_t channel;        // Sender's channel (for verification)
};

// Data message for forwarding telemetry/alerts
struct __attribute__((packed)) ESPNowDataMsg {
  uint8_t type;           // MSG_TYPE_TELEMETRY, MSG_TYPE_ALERT, etc.
  char originNode;        // Original sender
  char destNode;          // 'S' for sink, or node ID
  uint8_t ttl;            // Time to live (decremented each hop)
  uint8_t seqNum;         // Sequence number for dedup
  char visited[5];        // Nodes that have seen this (loop prevention)
  uint8_t visitedCount;
  uint8_t payloadLen;     // Length of payload
  char payload[200];      // JSON payload (telemetry, alert, etc.)
};

// ============================================================================
// PEER MANAGEMENT
// ============================================================================

struct ESPNowPeer {
  bool active;
  char nodeId;
  uint8_t mac[6];
  float batteryPercent;
  int8_t rssi;            // Their RSSI to sink
  int8_t peerRssi;        // Our RSSI to them (from ESP-NOW)
  uint32_t lastSeen;
};

// ============================================================================
// ESP-NOW MESH CLASS
// ============================================================================

class ESPNowMesh {
private:
  char myNodeId;
  int wifiChannel;
  ESPNowPeer peers[MAX_ESPNOW_PEERS];
  
  // Broadcast MAC
  uint8_t broadcastMac[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
  
  // Stats
  uint32_t txCount;
  uint32_t rxCount;
  uint32_t txOk;
  uint32_t txFail;
  uint32_t forwardCount;
  
  // Message tracking
  uint8_t lastSeqNum;
  uint8_t seenSeqNums[10];  // Ring buffer for dedup
  uint8_t seenSeqIdx;
  
  // Deferred operations (can't send in callback)
  volatile bool needAck;
  uint8_t ackMac[6];
  char ackNodeId;
  
  // Singleton for callbacks
  static ESPNowMesh* instance;

public:
  // Get the channel that should be used for ESP-NOW
  // If WiFi connected: use WiFi's channel
  // If WiFi disconnected: use fixed channel and SET it explicitly
  int determineAndSetChannel() {
    if (WiFi.status() == WL_CONNECTED) {
      int ch = WiFi.channel();
      Serial.printf("   WiFi connected, using WiFi channel: %d\n", ch);
      return ch;
    } else {
      // WiFi not connected - we MUST set channel explicitly
      int ch = ESPNOW_FIXED_CHANNEL;
      wifi_set_channel(ch);  // ESP8266 SDK function
      Serial.printf("   WiFi disconnected, forcing channel: %d\n", ch);
      return ch;
    }
  }
  
  void begin(char nodeId, int channel = -1) {
    myNodeId = nodeId;
    instance = this;
    
    // Determine channel: if -1 passed, auto-detect
    if (channel <= 0) {
      wifiChannel = determineAndSetChannel();
    } else {
      wifiChannel = channel;
      // If explicit channel passed but WiFi not connected, set it
      if (WiFi.status() != WL_CONNECTED) {
        wifi_set_channel(wifiChannel);
      }
    }
    
    txCount = rxCount = txOk = txFail = forwardCount = 0;
    lastSeqNum = 0;
    seenSeqIdx = 0;
    needAck = false;
    
    // Initialize peer slots
    for (int i = 0; i < MAX_ESPNOW_PEERS; i++) {
      peers[i].active = false;
    }
    
    // Initialize seen sequence numbers
    for (int i = 0; i < 10; i++) {
      seenSeqNums[i] = 255;
    }
    
    // Initialize ESP-NOW
    if (esp_now_init() != 0) {
      Serial.println("❌ ESP-NOW init failed!");
      return;
    }
    
    esp_now_set_self_role(ESP_NOW_ROLE_COMBO);
    esp_now_register_send_cb(onSentStatic);
    esp_now_register_recv_cb(onRecvStatic);
    
    // Add broadcast peer
    if (esp_now_add_peer(broadcastMac, ESP_NOW_ROLE_COMBO, wifiChannel, NULL, 0) != 0) {
      Serial.println("❌ Failed to add broadcast peer");
    }
    
    Serial.printf("✅ ESP-NOW initialized on channel %d\n", wifiChannel);
    Serial.print("   MAC: ");
    Serial.println(WiFi.macAddress());
  }
  
  // ========== CALLBACKS (static wrappers) ==========
  
  static void onSentStatic(uint8_t *mac, uint8_t status) {
    if (instance) instance->onSent(mac, status);
  }
  
  static void onRecvStatic(uint8_t *mac, uint8_t *data, uint8_t len) {
    if (instance) instance->onRecv(mac, data, len);
  }
  
  void onSent(uint8_t *mac, uint8_t status) {
    if (status == 0) txOk++;
    else txFail++;
  }
  
  // Get current channel (works even without WiFi)
  uint8_t getCurrentChannel() {
    return wifi_get_channel();  // ESP8266 SDK function
  }
  
  void onRecv(uint8_t *mac, uint8_t *data, uint8_t len) {
    if (len < 1) return;
    
    uint8_t msgType = data[0];
    rxCount++;
    
    // Handle discovery messages
    if (msgType == MSG_TYPE_DISCOVERY && len >= sizeof(ESPNowDiscovery)) {
      ESPNowDiscovery* disc = (ESPNowDiscovery*)data;
      
      // Ignore our own broadcasts
      if (disc->nodeId == myNodeId) return;
      
      // Channel verification - if we received it, we're on same channel!
      uint8_t myChannel = getCurrentChannel();
      #if DEBUG_ESPNOW
      Serial.printf("📡 [ESP-NOW RX] Discovery from Node %c (batt:%.0f%%, rssi:%d, ch:%d) [my ch:%d] ✅ SAME CHANNEL\n",
                    disc->nodeId, disc->batteryPercent, disc->rssi, disc->channel, myChannel);
      #endif
      
      // Update or add peer
      updatePeer(mac, disc->nodeId, disc->batteryPercent, disc->rssi);
      
      // Schedule ACK (don't send in callback!)
      if (!needAck) {
        needAck = true;
        memcpy(ackMac, mac, 6);
        ackNodeId = disc->nodeId;
      }
    }
    // Handle ACK messages
    else if (msgType == MSG_TYPE_ACK && len >= sizeof(ESPNowDiscovery)) {
      ESPNowDiscovery* ack = (ESPNowDiscovery*)data;
      
      if (ack->nodeId == myNodeId) return;
      
      uint8_t myChannel = getCurrentChannel();
      #if DEBUG_ESPNOW
      Serial.printf("📡 [ESP-NOW RX] ACK from Node %c (ch:%d) [my ch:%d] ✅\n", 
                    ack->nodeId, ack->channel, myChannel);
      #endif
      
      updatePeer(mac, ack->nodeId, ack->batteryPercent, ack->rssi);
    }
    // Handle data messages (for forwarding)
    else if ((msgType == MSG_TYPE_TELEMETRY || msgType == MSG_TYPE_ALERT) && 
             len >= sizeof(ESPNowDataMsg) - 200) {
      ESPNowDataMsg* dataMsg = (ESPNowDataMsg*)data;
      
      // Check if we've seen this message (dedup)
      if (hasSeenMessage(dataMsg->originNode, dataMsg->seqNum)) {
        #if DEBUG_ESPNOW
        Serial.printf("📡 [ESP-NOW] Dropping duplicate msg from %c seq %d\n",
                      dataMsg->originNode, dataMsg->seqNum);
        #endif
        return;
      }
      markMessageSeen(dataMsg->originNode, dataMsg->seqNum);
      
      // Store for processing in loop()
      handleDataMessage(dataMsg);
    }
  }
  
  // ========== PEER MANAGEMENT ==========
  
  void updatePeer(uint8_t* mac, char nodeId, float battery, int8_t rssi) {
    // Find existing or empty slot
    int slot = -1;
    for (int i = 0; i < MAX_ESPNOW_PEERS; i++) {
      if (peers[i].active && peers[i].nodeId == nodeId) {
        slot = i;
        break;
      }
      if (slot == -1 && !peers[i].active) {
        slot = i;
      }
    }
    
    if (slot >= 0) {
      peers[slot].active = true;
      peers[slot].nodeId = nodeId;
      memcpy(peers[slot].mac, mac, 6);
      peers[slot].batteryPercent = battery;
      peers[slot].rssi = rssi;
      peers[slot].lastSeen = millis();
      
      // Register as ESP-NOW peer for sending
      esp_now_add_peer(mac, ESP_NOW_ROLE_COMBO, wifiChannel, NULL, 0);
    }
  }
  
  ESPNowPeer* getPeer(char nodeId) {
    for (int i = 0; i < MAX_ESPNOW_PEERS; i++) {
      if (peers[i].active && peers[i].nodeId == nodeId) {
        return &peers[i];
      }
    }
    return nullptr;
  }
  
  ESPNowPeer* getPeers() {
    return peers;
  }
  
  int getPeerCount() {
    int count = 0;
    for (int i = 0; i < MAX_ESPNOW_PEERS; i++) {
      if (peers[i].active) count++;
    }
    return count;
  }
  
  void cleanupStalePeers() {
    uint32_t now = millis();
    for (int i = 0; i < MAX_ESPNOW_PEERS; i++) {
      if (peers[i].active && (now - peers[i].lastSeen) > ESPNOW_PEER_TIMEOUT_MS) {
        #if DEBUG_ESPNOW
        Serial.printf("📡 [ESP-NOW] Peer %c expired (no contact for %ds)\n",
                      peers[i].nodeId, ESPNOW_PEER_TIMEOUT_MS / 1000);
        #endif
        peers[i].active = false;
      }
    }
  }
  
  // ========== MESSAGE DEDUPLICATION ==========
  
  bool hasSeenMessage(char origin, uint8_t seq) {
    uint8_t key = ((uint8_t)origin << 4) | (seq & 0x0F);
    for (int i = 0; i < 10; i++) {
      if (seenSeqNums[i] == key) return true;
    }
    return false;
  }
  
  void markMessageSeen(char origin, uint8_t seq) {
    uint8_t key = ((uint8_t)origin << 4) | (seq & 0x0F);
    seenSeqNums[seenSeqIdx] = key;
    seenSeqIdx = (seenSeqIdx + 1) % 10;
  }
  
  // ========== SENDING ==========
  
  void sendDiscovery(float myBattery) {
    ESPNowDiscovery disc;
    disc.type = MSG_TYPE_DISCOVERY;
    disc.nodeId = myNodeId;
    disc.batteryPercent = myBattery;
    disc.rssi = WiFi.RSSI();
    disc.channel = getCurrentChannel();  // Include our channel
    
    int result = esp_now_send(broadcastMac, (uint8_t*)&disc, sizeof(disc));
    txCount++;
    
    #if DEBUG_ESPNOW
    Serial.printf("📡 [ESP-NOW TX] Discovery broadcast (batt:%.0f%%, rssi:%d, ch:%d) %s\n",
                  myBattery, disc.rssi, disc.channel, result == 0 ? "OK" : "FAIL");
    #endif
  }
  
  void sendAck(uint8_t* mac, float myBattery) {
    ESPNowDiscovery ack;
    ack.type = MSG_TYPE_ACK;
    ack.nodeId = myNodeId;
    ack.batteryPercent = myBattery;
    ack.rssi = WiFi.RSSI();
    ack.channel = getCurrentChannel();  // Include our channel
    
    int result = esp_now_send(mac, (uint8_t*)&ack, sizeof(ack));
    txCount++;
    
    #if DEBUG_ESPNOW
    Serial.printf("📡 [ESP-NOW TX] ACK sent (ch:%d) %s\n", ack.channel, result == 0 ? "OK" : "FAIL");
    #endif
  }
  
  // Send data via ESP-NOW to specific peer
  bool sendData(char targetNode, uint8_t msgType, const char* payload, uint8_t payloadLen) {
    ESPNowPeer* peer = getPeer(targetNode);
    if (!peer || !peer->active) {
      #if DEBUG_ESPNOW
      Serial.printf("📡 [ESP-NOW] Cannot send to %c - peer not found\n", targetNode);
      #endif
      return false;
    }
    
    ESPNowDataMsg msg;
    msg.type = msgType;
    msg.originNode = myNodeId;
    msg.destNode = 'S';  // Ultimately going to sink
    msg.ttl = ESPNOW_DATA_FORWARD_TTL;
    msg.seqNum = ++lastSeqNum;
    msg.visitedCount = 1;
    msg.visited[0] = myNodeId;
    msg.visited[1] = '\0';
    msg.payloadLen = min((int)payloadLen, 200);
    memcpy(msg.payload, payload, msg.payloadLen);
    
    int result = esp_now_send(peer->mac, (uint8_t*)&msg, sizeof(msg) - 200 + msg.payloadLen);
    txCount++;
    
    #if DEBUG_ESPNOW
    Serial.printf("📡 [ESP-NOW TX] Data to Node %c (type:%d, len:%d) %s\n",
                  targetNode, msgType, payloadLen, result == 0 ? "OK" : "FAIL");
    #endif
    
    return (result == 0);
  }
  
  // Forward a received message to next hop
  bool forwardData(ESPNowDataMsg* msg, char nextHop) {
    ESPNowPeer* peer = getPeer(nextHop);
    if (!peer || !peer->active) {
      return false;
    }
    
    // Decrement TTL
    if (msg->ttl <= 1) {
      #if DEBUG_ESPNOW
      Serial.println("📡 [ESP-NOW] Message TTL expired, not forwarding");
      #endif
      return false;
    }
    msg->ttl--;
    
    // Add ourselves to visited list
    if (msg->visitedCount < 4) {
      msg->visited[msg->visitedCount++] = myNodeId;
    }
    
    int result = esp_now_send(peer->mac, (uint8_t*)msg, sizeof(*msg) - 200 + msg->payloadLen);
    txCount++;
    forwardCount++;
    
    #if DEBUG_ESPNOW
    Serial.printf("📡 [ESP-NOW TX] Forwarded to Node %c (origin:%c, ttl:%d) %s\n",
                  nextHop, msg->originNode, msg->ttl, result == 0 ? "OK" : "FAIL");
    #endif
    
    return (result == 0);
  }
  
  // ========== PROCESS DEFERRED OPERATIONS ==========
  
  void processDeferredOps(float myBattery) {
    if (needAck) {
      needAck = false;
      sendAck(ackMac, myBattery);
    }
  }
  
  // ========== INCOMING DATA MESSAGE HANDLING ==========
  
  // Store last received data message for processing in main loop
  ESPNowDataMsg lastReceivedData;
  volatile bool hasReceivedData;
  
  void handleDataMessage(ESPNowDataMsg* msg) {
    memcpy(&lastReceivedData, msg, sizeof(ESPNowDataMsg));
    hasReceivedData = true;
  }
  
  bool hasDataToProcess() {
    return hasReceivedData;
  }
  
  ESPNowDataMsg* getReceivedData() {
    hasReceivedData = false;
    return &lastReceivedData;
  }
  
  // ========== STATS ==========
  
  void printStats() {
    uint8_t ch = getCurrentChannel();
    bool wifiUp = (WiFi.status() == WL_CONNECTED);
    
    Serial.println("\n===== ESP-NOW Stats =====");
    Serial.printf("Channel: %d (%s) | WiFi: %s\n", 
                  ch, 
                  wifiUp ? "from WiFi" : "FIXED",
                  wifiUp ? "CONNECTED" : "DISCONNECTED");
    Serial.printf("TX: %u (OK:%u FAIL:%u) | RX: %u | FWD: %u\n",
                  txCount, txOk, txFail, rxCount, forwardCount);
    Serial.printf("Peers (%d):\n", getPeerCount());
    for (int i = 0; i < MAX_ESPNOW_PEERS; i++) {
      if (peers[i].active) {
        Serial.printf("  [%c] ", peers[i].nodeId);
        Serial.printf("%02X:%02X:%02X:%02X:%02X:%02X",
                      peers[i].mac[0], peers[i].mac[1], peers[i].mac[2],
                      peers[i].mac[3], peers[i].mac[4], peers[i].mac[5]);
        Serial.printf(" batt:%.0f%% rssi:%d (seen %lus ago)\n",
                      peers[i].batteryPercent, peers[i].rssi,
                      (millis() - peers[i].lastSeen) / 1000);
      }
    }
    Serial.println("=========================\n");
  }
  
  uint32_t getTxCount() { return txCount; }
  uint32_t getRxCount() { return rxCount; }
  uint32_t getForwardCount() { return forwardCount; }
};

// Static instance pointer
ESPNowMesh* ESPNowMesh::instance = nullptr;

#endif // ESPNOW_MESH_H
