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
  int8_t rssi;            // Sender's WiFi RSSI (to AP/gateway)
  uint8_t channel;        // Sender's channel (for verification)
  uint8_t hasSinkAccess;  // 1 if sender has MQTT connectivity to gateway, 0 otherwise
};

// Data ACK message - confirms receipt of data message
struct __attribute__((packed)) ESPNowDataAck {
  uint8_t type;           // MSG_TYPE_DATA_ACK
  char ackNode;           // Node sending the ACK  
  char originNode;        // Original sender of data being ACKed
  uint8_t seqNum;         // Sequence number being ACKed
  uint8_t status;         // 1 = received & will forward, 0 = received but cannot forward
};

// Data message for forwarding telemetry/alerts
// IMPORTANT: Keep payload size moderate (<=150 bytes) for ESP8266 ESP-NOW reliability
struct __attribute__((packed)) ESPNowDataMsg {
  uint8_t type;           // MSG_TYPE_TELEMETRY, MSG_TYPE_ALERT, etc.
  char originNode;        // Original sender
  char destNode;          // 'S' for sink, or node ID
  uint8_t ttl;            // Time to live (decremented each hop)
  uint8_t seqNum;         // Sequence number for dedup
  char visited[5];        // Nodes that have seen this (loop prevention)
  uint8_t visitedCount;
  uint8_t payloadLen;     // Length of payload
  char payload[150];      // JSON payload - reduced size for reliability
};

// ============================================================================
// PEER MANAGEMENT
// ============================================================================

struct ESPNowPeer {
  bool active;
  char nodeId;
  uint8_t mac[6];
  float batteryPercent;
  int8_t rssi;            // Their RSSI to WiFi AP
  int8_t peerRssi;        // Our RSSI to them (from ESP-NOW)
  bool hasSinkAccess;     // Do they have MQTT connectivity to gateway?
  uint32_t lastSeen;
};

// ============================================================================
// ESP-NOW MESH CLASS
// ============================================================================

// Message queue size - allows buffering multiple incoming messages
#define ESPNOW_MSG_QUEUE_SIZE 4

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
  uint32_t droppedCount;  // Messages dropped due to full queue
  
  // Message tracking
  uint8_t lastSeqNum;
  
  // Improved deduplication: track origin+seq pairs
  struct SeenMsg {
    char origin;
    uint8_t seq;
    uint32_t timestamp;
  };
  SeenMsg seenMsgs[16];     // Larger buffer for better dedup
  uint8_t seenMsgIdx;
  
  // Data ACK tracking
  volatile bool waitingForDataAck;
  volatile bool dataAckReceived;
  char pendingAckOrigin;
  uint8_t pendingAckSeq;
  
  // Deferred operations (can't send in callback)
  volatile bool needAck;
  uint8_t ackMac[6];
  char ackNodeId;
  
  // Deferred data ACK
  volatile bool needDataAck;
  uint8_t dataAckMac[6];
  char dataAckOrigin;
  uint8_t dataAckSeq;
  
  // Channel scanning state
  bool channelScanned;
  int foundChannel;
  unsigned long lastChannelScan;
  
  // Singleton for callbacks
  static ESPNowMesh* instance;

public:
  // Scan channels to find peers (for WiFi-less mode)
  #if ESPNOW_CHANNEL_SCAN
  int scanForPeers() {
    LOG_CRITICAL("[ESPNOW] Scanning for peers...\n");
    
    uint8_t scanChannels[] = ESPNOW_SCAN_CHANNELS;
    int bestChannel = ESPNOW_FIXED_CHANNEL;
    bool foundPeer = false;
    
    for (int i = 0; i < ESPNOW_SCAN_CHANNELS_COUNT; i++) {
      int ch = scanChannels[i];
      wifi_set_channel(ch);
      wifiChannel = ch;
      
      LOG_CRITICAL("[ESPNOW] Ch %d: ", ch);
      
      // Listen for discovery beacons from peers on this channel
      // Peers broadcast discovery every 5s, so we need to wait long enough
      unsigned long scanStart = millis();
      int discoveryCount = 0;
      
      while (millis() - scanStart < ESPNOW_SCAN_DWELL_MS) {
        // Send our own discovery every ~500ms (peers may ACK or just broadcast back)
        if (discoveryCount < ESPNOW_SCAN_DISCOVERIES && 
            (millis() - scanStart) >= (discoveryCount * 500)) {
          sendDiscovery(50.0, false);  // Dummy battery, no sink access
          Serial.print(".");
          discoveryCount++;
        }
        
        // Process deferred ACKs (in case we need to respond)
        processDeferredOps(50.0, false);
        
        // The key: onRecv() callback updates peers[] directly when we receive
        // discovery or ACK messages. We just need to yield to allow callbacks.
        yield();
        delay(10);  // Small delay to allow radio to receive
        
        // Check if we got any peer responses
        if (getPeerCount() > 0) {
          foundPeer = true;
          bestChannel = ch;
          Serial.println(" FOUND!");
          LOG_CRITICAL("[ESPNOW] Found %d peer(s) on ch %d\n", getPeerCount(), ch);
          break;
        }
      }
      
      if (foundPeer) break;
      Serial.println(" none");
    }
    
    if (!foundPeer) {
      LOG_CRITICAL("[ESPNOW] No peers found after full scan\n");
      LOG_CRITICAL("[ESPNOW] Defaulting to ch %d (must match other nodes!)\n", ESPNOW_FIXED_CHANNEL);
      bestChannel = ESPNOW_FIXED_CHANNEL;
    }
    
    // Set the found/default channel
    wifi_set_channel(bestChannel);
    wifiChannel = bestChannel;
    foundChannel = bestChannel;
    channelScanned = true;
    lastChannelScan = millis();
    
    return bestChannel;
  }
  
  bool needsChannelRescan() {
    // Rescan if no peers found and enough time passed
    if (WiFi.status() == WL_CONNECTED) return false;  // WiFi handles channel
    if (getPeerCount() > 0) return false;  // Have peers, no need
    if (!channelScanned) return true;  // Never scanned
    return (millis() - lastChannelScan) > ESPNOW_SCAN_INTERVAL_MS;
  }
  #endif

  // Get the channel that should be used for ESP-NOW
  // If WiFi connected: use WiFi's channel
  // If WiFi disconnected: use fixed channel or scan for peers
  int determineAndSetChannel() {
    if (WiFi.status() == WL_CONNECTED) {
      int ch = WiFi.channel();
      LOG_CRITICAL("[ESPNOW] WiFi connected, ch %d\n", ch);
      return ch;
    } else {
      // WiFi not connected - need to find the right channel
      #if ESPNOW_CHANNEL_SCAN
      if (needsChannelRescan()) {
        return scanForPeers();
      } else if (channelScanned && foundChannel > 0) {
        wifi_set_channel(foundChannel);
        LOG_CRITICAL("[ESPNOW] Using found ch %d\n", foundChannel);
        return foundChannel;
      }
      #endif
      
      // Fallback: use fixed channel
      int ch = ESPNOW_FIXED_CHANNEL;
      wifi_set_channel(ch);
      LOG_CRITICAL("[ESPNOW] No WiFi, using ch %d\n", ch);
      return ch;
    }
  }
  
  void begin(char nodeId, int channel = -1) {
    myNodeId = nodeId;
    instance = this;
    
    // Initialize channel scanning state
    channelScanned = false;
    foundChannel = -1;
    lastChannelScan = 0;
    
    txCount = rxCount = txOk = txFail = forwardCount = droppedCount = 0;
    lastSeqNum = 0;
    seenMsgIdx = 0;
    needAck = false;
    needDataAck = false;
    waitingForDataAck = false;
    dataAckReceived = false;
    
    // Initialize message queue
    msgQueueHead = msgQueueTail = msgQueueCount = 0;
    
    // Initialize peer slots
    for (int i = 0; i < MAX_ESPNOW_PEERS; i++) {
      peers[i].active = false;
    }
    
    // Initialize seen message buffer
    for (int i = 0; i < 16; i++) {
      seenMsgs[i].origin = 0;
      seenMsgs[i].seq = 255;
      seenMsgs[i].timestamp = 0;
    }
    
    // MUST initialize ESP-NOW BEFORE scanning (so we can send/receive)
    if (esp_now_init() != 0) {
      LOGLN("[ERROR] ESP-NOW init failed!");
      return;
    }
    
    esp_now_set_self_role(ESP_NOW_ROLE_COMBO);
    esp_now_register_send_cb(onSentStatic);
    esp_now_register_recv_cb(onRecvStatic);
    
    // Add broadcast peer (needed for discovery)
    esp_now_add_peer(broadcastMac, ESP_NOW_ROLE_COMBO, ESPNOW_FIXED_CHANNEL, NULL, 0);
    
    // NOW we can determine channel (and scan if needed)
    if (channel <= 0) {
      wifiChannel = determineAndSetChannel();
    } else {
      wifiChannel = channel;
      if (WiFi.status() != WL_CONNECTED) {
        wifi_set_channel(wifiChannel);
      }
    }
    
    LOGF("[OK] ESP-NOW initialized on channel %d\n", wifiChannel);
    Serial.printf("[Node %c]      MAC: %s\n", myNodeId, WiFi.macAddress().c_str());
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
    
    // Debug: log all received message types with node ID
    LOGF("[ESPNOW-RX] Raw msg: type=%d, len=%d\n", msgType, len);
    
    // Handle discovery messages
    if (msgType == MSG_TYPE_DISCOVERY && len >= sizeof(ESPNowDiscovery)) {
      ESPNowDiscovery* disc = (ESPNowDiscovery*)data;
      
      // Ignore our own broadcasts
      if (disc->nodeId == myNodeId) return;
      
      // Channel verification - if we received it, we're on same channel!
      uint8_t myChannel = getCurrentChannel();
      bool peerHasSink = (disc->hasSinkAccess == 1);
      
      // ALWAYS log discovery reception with channel info
      LOG_CRITICAL("[ESPNOW-RX] Discovery from %c (ch:%d, myCh:%d, sink:%s)\n",
                    disc->nodeId, disc->channel, myChannel, peerHasSink ? "Y" : "N");
      
      // Update or add peer with their sink access status
      updatePeer(mac, disc->nodeId, disc->batteryPercent, disc->rssi, peerHasSink);
      
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
      bool peerHasSink = (ack->hasSinkAccess == 1);
      #if DEBUG_ESPNOW
      LOGF("[ESPNOW-RX] ACK from Node %c (ch:%d, sink:%s) [my ch:%d]\n",
                    ack->nodeId, ack->channel, peerHasSink ? "YES" : "NO", myChannel);
      #endif
      
      updatePeer(mac, ack->nodeId, ack->batteryPercent, ack->rssi, peerHasSink);
    }
    // Handle data ACK messages
    else if (msgType == MSG_TYPE_DATA_ACK && len >= sizeof(ESPNowDataAck)) {
      ESPNowDataAck* dataAck = (ESPNowDataAck*)data;
      
      // Check if this ACK is for our pending message
      if (waitingForDataAck && 
          dataAck->originNode == pendingAckOrigin && 
          dataAck->seqNum == pendingAckSeq) {
        dataAckReceived = true;
        LOGF("[ESPNOW-RX] Data ACK from Node %c for seq %d\n", 
                      dataAck->ackNode, dataAck->seqNum);
      }
    }
    // Handle data messages (for forwarding)
    else if ((msgType == MSG_TYPE_TELEMETRY || msgType == MSG_TYPE_ALERT) && 
             len >= (sizeof(ESPNowDataMsg) - 150)) {  // Adjusted for new payload size
      ESPNowDataMsg* dataMsg = (ESPNowDataMsg*)data;
      
      // Ignore our own broadcasts
      if (dataMsg->originNode == myNodeId) {
        return;
      }
      
      // Accept messages addressed to us OR to sink (we might relay to sink)
      // Also accept if we're not in the visited list (broadcast reception)
      bool isForUs = (dataMsg->destNode == myNodeId) || 
                     (dataMsg->destNode == 'S');
      
      // Also accept if destNode is not set correctly but we can help relay
      // This handles the case where broadcast is used
      if (!isForUs) {
        // Check if we could be a valid relay (not in visited list)
        bool alreadyVisited = false;
        for (int i = 0; i < dataMsg->visitedCount && i < 5; i++) {
          if (dataMsg->visited[i] == myNodeId) {
            alreadyVisited = true;
            break;
          }
        }
        if (!alreadyVisited) {
          // We haven't seen this message via our node, might be able to help
          isForUs = true;
          LOGF("[ESPNOW-RX] Accepting broadcast data (dest=%c, not visited)\n", dataMsg->destNode);
        }
      }
      
      if (!isForUs) {
        #if DEBUG_ESPNOW
        LOGF("[ESPNOW-RX] Data msg not for us (dest=%c), ignoring\n", dataMsg->destNode);
        #endif
        return;
      }
      
      LOGF("[ESPNOW-RX] *** DATA from Node %c (type:%d, seq:%d, len:%d) ***\n",
                    dataMsg->originNode, msgType, dataMsg->seqNum, dataMsg->payloadLen);
      
      // Check if we've seen this message (dedup)
      if (hasSeenMessage(dataMsg->originNode, dataMsg->seqNum)) {
        #if DEBUG_ESPNOW
        LOGF("[ESPNOW] Dropping duplicate msg from %c seq %d\n",
                      dataMsg->originNode, dataMsg->seqNum);
        #endif
        return;
      }
      markMessageSeen(dataMsg->originNode, dataMsg->seqNum);
      
      // Schedule a data ACK back to the sender (deferred, not in callback)
      if (!needDataAck) {
        needDataAck = true;
        memcpy(dataAckMac, mac, 6);
        dataAckOrigin = dataMsg->originNode;
        dataAckSeq = dataMsg->seqNum;
      }
      
      // Store for processing in loop()
      handleDataMessage(dataMsg);
      LOGLN("[ESPNOW-RX] Data queued for forwarding");
    }
  }
  
  // ========== PEER MANAGEMENT ==========
  
  void updatePeer(uint8_t* mac, char nodeId, float battery, int8_t rssi, bool hasSinkAccess = false) {
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
      peers[slot].hasSinkAccess = hasSinkAccess;
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
  
  ESPNowPeer* getPeerByIndex(int index) {
    if (index < 0 || index >= MAX_ESPNOW_PEERS) return nullptr;
    if (peers[index].active) return &peers[index];
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
        LOGF("[ESPNOW] Peer %c expired (no contact for %ds)\n",
                      peers[i].nodeId, ESPNOW_PEER_TIMEOUT_MS / 1000);
        #endif
        peers[i].active = false;
      }
    }
  }
  
  // ========== MESSAGE DEDUPLICATION (improved) ==========
  
  bool hasSeenMessage(char origin, uint8_t seq) {
    uint32_t now = millis();
    // Check all entries for matching origin+seq within last 30 seconds
    for (int i = 0; i < 16; i++) {
      if (seenMsgs[i].origin == origin && 
          seenMsgs[i].seq == seq &&
          (now - seenMsgs[i].timestamp) < 30000) {
        return true;
      }
    }
    return false;
  }
  
  void markMessageSeen(char origin, uint8_t seq) {
    seenMsgs[seenMsgIdx].origin = origin;
    seenMsgs[seenMsgIdx].seq = seq;
    seenMsgs[seenMsgIdx].timestamp = millis();
    seenMsgIdx = (seenMsgIdx + 1) % 16;
  }
  
  // ========== SENDING ==========
  
  void sendDiscovery(float myBattery, bool hasSinkAccess = false) {
    ESPNowDiscovery disc;
    disc.type = MSG_TYPE_DISCOVERY;
    disc.nodeId = myNodeId;
    disc.batteryPercent = myBattery;
    disc.rssi = WiFi.RSSI();
    disc.channel = getCurrentChannel();
    disc.hasSinkAccess = hasSinkAccess ? 1 : 0;  // Dynamic: do I have MQTT connectivity?
    
    int result = esp_now_send(broadcastMac, (uint8_t*)&disc, sizeof(disc));
    txCount++;
    
    #if DEBUG_ESPNOW
    LOGF("[ESPNOW-TX] Discovery broadcast (batt:%.0f%%, rssi:%d, ch:%d, sink:%s) %s\n",
                  myBattery, disc.rssi, disc.channel, hasSinkAccess ? "YES" : "NO",
                  result == 0 ? "OK" : "FAIL");
    #endif
  }
  
  void sendAck(uint8_t* mac, float myBattery, bool hasSinkAccess = false) {
    ESPNowDiscovery ack;
    ack.type = MSG_TYPE_ACK;
    ack.nodeId = myNodeId;
    ack.batteryPercent = myBattery;
    ack.rssi = WiFi.RSSI();
    ack.channel = getCurrentChannel();
    ack.hasSinkAccess = hasSinkAccess ? 1 : 0;
    
    int result = esp_now_send(mac, (uint8_t*)&ack, sizeof(ack));
    txCount++;
    
    #if DEBUG_ESPNOW
    LOGF("[ESPNOW-TX] ACK sent (ch:%d, sink:%s) %s\n", 
                  ack.channel, hasSinkAccess ? "YES" : "NO", result == 0 ? "OK" : "FAIL");
    #endif
  }
  
  // Send data via ESP-NOW to specific peer with retry mechanism
  // NOTE: Use broadcast instead of unicast for reliability on ESP8266
  bool sendData(char targetNode, uint8_t msgType, const char* payload, uint8_t payloadLen) {
    ESPNowPeer* peer = getPeer(targetNode);
    if (!peer || !peer->active) {
      #if DEBUG_ESPNOW
      LOGF("[ESPNOW] Cannot send to %c - peer not found\n", targetNode);
      #endif
      return false;
    }
    
    // Truncate payload if too large for reliable transmission
    uint8_t safeLen = min((int)payloadLen, 150);
    if (payloadLen > 150) {
      LOGF("[ESPNOW] WARNING: Payload truncated from %d to 150 bytes\n", payloadLen);
    }
    
    ESPNowDataMsg msg;
    msg.type = msgType;
    msg.originNode = myNodeId;
    msg.destNode = targetNode;  // Set intended recipient
    msg.ttl = ESPNOW_DATA_FORWARD_TTL;
    msg.seqNum = ++lastSeqNum;
    msg.visitedCount = 1;
    msg.visited[0] = myNodeId;
    // Don't null-terminate - visitedCount tracks length
    msg.payloadLen = safeLen;
    memcpy(msg.payload, payload, safeLen);
    
    // Calculate actual message size (header + payload)
    size_t msgSize = sizeof(ESPNowDataMsg) - 150 + safeLen;
    
    // Retry mechanism for improved reliability
    bool success = false;
    for (int retry = 0; retry < ESPNOW_DATA_RETRIES && !success; retry++) {
      if (retry > 0) {
        // Non-blocking delay with yield to prevent watchdog reset
        unsigned long retryStart = millis();
        while (millis() - retryStart < ESPNOW_RETRY_DELAY_MS) {
          yield();  // Feed watchdog
        }
        #if DEBUG_ESPNOW
        LOGF("[ESPNOW-TX] Retry %d for Node %c\n", retry, targetNode);
        #endif
      }
      
      int result = esp_now_send(broadcastMac, (uint8_t*)&msg, msgSize);
      txCount++;
      yield();  // Give system time after TX
      
      if (result == 0) {
        success = true;
      }
    }
    
    #if DEBUG_ESPNOW
    LOGF("[ESPNOW-TX] Data to Node %c (type:%d, len:%d, seq:%d, size:%d) %s\n",
                  targetNode, msgType, safeLen, msg.seqNum, (int)msgSize, success ? "OK" : "FAIL");
    #endif
    
    return success;
  }
  
  // Forward a received message to next hop
  // Uses broadcast for reliability (like sendData)
  bool forwardData(ESPNowDataMsg* msg, char nextHop) {
    ESPNowPeer* peer = getPeer(nextHop);
    if (!peer || !peer->active) {
      LOGF("[ESPNOW-FWD] Cannot forward - peer %c not found\n", nextHop);
      return false;
    }
    
    // Decrement TTL
    if (msg->ttl <= 1) {
      #if DEBUG_ESPNOW
      LOGLN("[ESPNOW] Message TTL expired, not forwarding");
      #endif
      return false;
    }
    msg->ttl--;
    
    // Update destNode to the next hop
    msg->destNode = nextHop;
    
    // Add ourselves to visited list (array has 5 slots)
    if (msg->visitedCount < 5) {
      msg->visited[msg->visitedCount++] = myNodeId;
    }
    
    // Calculate actual message size
    size_t msgSize = sizeof(ESPNowDataMsg) - 150 + msg->payloadLen;
    
    // Retry mechanism with watchdog-safe delays
    bool success = false;
    for (int retry = 0; retry < ESPNOW_DATA_RETRIES && !success; retry++) {
      if (retry > 0) {
        // Non-blocking delay with yield to prevent watchdog reset
        unsigned long retryStart = millis();
        while (millis() - retryStart < ESPNOW_RETRY_DELAY_MS) {
          yield();  // Feed watchdog
        }
      }
      int result = esp_now_send(broadcastMac, (uint8_t*)msg, msgSize);
      txCount++;
      yield();  // Give system time after TX
      if (result == 0) success = true;
    }
    
    if (success) forwardCount++;
    
    #if DEBUG_ESPNOW
    LOGF("[ESPNOW-FWD] To Node %c (origin:%c, ttl:%d, size:%d) %s\n",
                  nextHop, msg->originNode, msg->ttl, (int)msgSize, success ? "OK" : "FAIL");
    #endif
    
    return success;
  }
  
  // ========== PROCESS DEFERRED OPERATIONS ==========
  
  void processDeferredOps(float myBattery, bool hasSinkAccess) {
    // Send discovery ACK
    if (needAck) {
      needAck = false;
      sendAck(ackMac, myBattery, hasSinkAccess);
    }
    
    // Send data ACK for received data messages
    if (needDataAck) {
      needDataAck = false;
      sendDataAck(dataAckMac, dataAckOrigin, dataAckSeq, hasSinkAccess);
    }
  }
  
  // Send acknowledgment for received data message
  void sendDataAck(uint8_t* mac, char originNode, uint8_t seqNum, bool canForward) {
    ESPNowDataAck ack;
    ack.type = MSG_TYPE_DATA_ACK;
    ack.ackNode = myNodeId;
    ack.originNode = originNode;
    ack.seqNum = seqNum;
    ack.status = canForward ? 1 : 0;
    
    int result = esp_now_send(mac, (uint8_t*)&ack, sizeof(ack));
    txCount++;
    
    #if DEBUG_ESPNOW
    LOGF("[ESPNOW-TX] Data ACK to origin %c seq %d, status:%d %s\n",
         originNode, seqNum, ack.status, result == 0 ? "OK" : "FAIL");
    #endif
  }
  
  // ========== INCOMING DATA MESSAGE HANDLING ==========
  
  // Message queue for received data (prevents loss when multiple messages arrive)
  ESPNowDataMsg msgQueue[ESPNOW_MSG_QUEUE_SIZE];
  volatile uint8_t msgQueueHead;  // Next write position
  volatile uint8_t msgQueueTail;  // Next read position
  volatile uint8_t msgQueueCount; // Number of messages in queue
  
  void handleDataMessage(ESPNowDataMsg* msg) {
    // Check if queue is full
    if (msgQueueCount >= ESPNOW_MSG_QUEUE_SIZE) {
      droppedCount++;
      LOG_CRITICAL("[ESPNOW] Queue full, dropped msg from %c\n", msg->originNode);
      return;
    }
    
    // Add to queue (copy the message)
    memcpy(&msgQueue[msgQueueHead], msg, sizeof(ESPNowDataMsg));
    msgQueueHead = (msgQueueHead + 1) % ESPNOW_MSG_QUEUE_SIZE;
    msgQueueCount++;
  }
  
  bool hasDataToProcess() {
    return msgQueueCount > 0;
  }
  
  ESPNowDataMsg* getReceivedData() {
    if (msgQueueCount == 0) return nullptr;
    
    // Get message from tail (oldest first - FIFO)
    ESPNowDataMsg* msg = &msgQueue[msgQueueTail];
    msgQueueTail = (msgQueueTail + 1) % ESPNOW_MSG_QUEUE_SIZE;
    msgQueueCount--;
    return msg;
  }
  
  // ========== STATS ==========
  
  void printStats() {
    uint8_t ch = getCurrentChannel();
    bool wifiUp = (WiFi.status() == WL_CONNECTED);
    
    // Build entire output in buffer to avoid interleaving
    char buf[650];
    int pos = 0;
    
    pos += snprintf(buf + pos, sizeof(buf) - pos, "\n[Node %c] ===== ESP-NOW Stats =====\n", myNodeId);
    pos += snprintf(buf + pos, sizeof(buf) - pos, "[Node %c] Channel: %d (%s) | WiFi: %s\n", 
                  myNodeId, ch, 
                  wifiUp ? "from WiFi" : "FIXED",
                  wifiUp ? "CONNECTED" : "DISCONNECTED");
    pos += snprintf(buf + pos, sizeof(buf) - pos, "[Node %c] TX: %u (OK:%u FAIL:%u) | RX: %u | FWD: %u | DROP: %u\n",
                  myNodeId, txCount, txOk, txFail, rxCount, forwardCount, droppedCount);
    pos += snprintf(buf + pos, sizeof(buf) - pos, "[Node %c] MsgQueue: %d/%d\n", myNodeId, msgQueueCount, ESPNOW_MSG_QUEUE_SIZE);
    pos += snprintf(buf + pos, sizeof(buf) - pos, "[Node %c] Peers (%d):\n", myNodeId, getPeerCount());
    for (int i = 0; i < MAX_ESPNOW_PEERS; i++) {
      if (peers[i].active) {
        pos += snprintf(buf + pos, sizeof(buf) - pos, "[Node %c]   [%c] %02X:%02X:%02X:%02X:%02X:%02X batt:%.0f%% rssi:%d sink:%s (%lus ago)\n",
                      myNodeId, peers[i].nodeId,
                      peers[i].mac[0], peers[i].mac[1], peers[i].mac[2],
                      peers[i].mac[3], peers[i].mac[4], peers[i].mac[5],
                      peers[i].batteryPercent, peers[i].rssi,
                      peers[i].hasSinkAccess ? "YES" : "NO",
                      (millis() - peers[i].lastSeen) / 1000);
      }
    }
    pos += snprintf(buf + pos, sizeof(buf) - pos, "[Node %c] =========================\n", myNodeId);
    
    Serial.print(buf);
  }
  
  uint32_t getTxCount() { return txCount; }
  uint32_t getRxCount() { return rxCount; }
  uint32_t getForwardCount() { return forwardCount; }
  uint32_t getDroppedCount() { return droppedCount; }
};

// Static instance pointer
ESPNowMesh* ESPNowMesh::instance = nullptr;

#endif // ESPNOW_MESH_H
