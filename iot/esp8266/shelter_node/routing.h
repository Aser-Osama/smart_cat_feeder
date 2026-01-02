/**
 * Multi-Hop Routing for Shelter Node
 * ===================================
 * 
 * Implements basic multi-hop routing between ESP8266 nodes to reach the sink.
 * Routing decisions based on RSSI and simulated battery levels.
 */

#ifndef ROUTING_H
#define ROUTING_H

#include <Arduino.h>
#include <ESP8266WiFi.h>
#include "config.h"

// ============================================================================
// ROUTING DATA STRUCTURES
// ============================================================================

#define MAX_NEIGHBORS 5

struct Neighbor {
  char nodeId;
  int rssi;              // ESP-NOW RSSI to this neighbor (link quality)
  int wifiRssi;          // This neighbor's WiFi RSSI to sink (their direct path quality)
  float batteryPercent;
  bool hasSinkAccess;    // Dynamic: true if this neighbor currently has MQTT/WiFi to gateway
  unsigned long lastSeen;
  bool valid;
};

struct RouteCandidate {
  char targetId;
  int rssi;
  float batteryPercent;
  float score;
};

struct RoutingDecision {
  char previousNextHop;
  char newNextHop;
  String reason;
  RouteCandidate candidates[MAX_NEIGHBORS + 1];  // +1 for direct-to-sink
  int candidateCount;
  float selectedScore;
};

// ============================================================================
// ROUTING TABLE
// ============================================================================

class RoutingTable {
private:
  char myNodeId;
  char nextHop;
  int hopCount;
  Neighbor neighbors[MAX_NEIGHBORS];
  int neighborCount;
  unsigned long lastRouteUpdate;
  int lastSinkRssi;
  bool espnowAvailable[MAX_NEIGHBORS];  // Track which neighbors are reachable via ESP-NOW

  // Normalize RSSI to 0.0-1.0 scale (-100 dBm = 0, -30 dBm = 1)
  float normalizeRssi(int rssi) {
    return constrain((rssi + 100.0) / 70.0, 0.0, 1.0);
  }

  // Calculate path quality score for DIRECT path (this node -> WiFi -> sink)
  // Returns effective path quality considering WiFi strength
  float calculateDirectPathScore(int wifiRssi, float myBattery) {
    // wifiRssi = wifiRssi - 100;
    float wifiQuality = normalizeRssi(wifiRssi);
    float batteryNorm = myBattery / 100.0;
    
    // Direct path score: WiFi quality is the bottleneck
    // Battery matters because we're the one doing the work
    return (RSSI_WEIGHT * wifiQuality) + (BATTERY_WEIGHT * batteryNorm);
  }

  // Calculate path quality score for MULTI-HOP path (this node -> ESP-NOW -> relay -> WiFi -> sink)
  // The path quality is the MINIMUM of the two links (weakest link determines throughput)
  float calculateMultiHopPathScore(int espnowRssi, int relayWifiRssi, float relayBattery, bool relayHasSinkAccess) {
    // If relay doesn't have sink access, this path is invalid
    if (!relayHasSinkAccess) {
      return -1.0;  // Invalid path
    }
    
    float espnowQuality = normalizeRssi(espnowRssi);
    float relayWifiQuality = normalizeRssi(relayWifiRssi);
    float relayBatteryNorm = relayBattery / 100.0;
    
    // Path quality is limited by the weakest link
    float linkQuality = min(espnowQuality, relayWifiQuality);
    
    // Multi-hop path score considers:
    // 1. Weakest link quality (bottleneck)
    // 2. Relay battery (they're doing work for us)
    // 3. Small penalty for extra hop (latency, reliability)
    float pathScore = (RSSI_WEIGHT * linkQuality) + (BATTERY_WEIGHT * relayBatteryNorm);
    
    // Multi-hop gets a small bonus when both links are strong (redundancy/reliability)
    // If both links > 0.65 quality (~-55dBm), bonus for path diversity
    if (espnowQuality > 0.65 && relayWifiQuality > 0.65) {
      pathScore += MULTIHOP_STRONG_LINK_BONUS;
    }
    
    // Penalty for the extra hop (latency, potential packet loss)
    pathScore -= MULTIHOP_HOP_PENALTY;
    
    return pathScore;
  }

  // Legacy score function (for backwards compatibility with beacon scoring)
  float calculateScore(int rssi, float batteryPercent, bool hasEspnow = false) {
    float normalizedRssi = normalizeRssi(rssi);
    float normalizedBattery = batteryPercent / 100.0;
    float score = (RSSI_WEIGHT * normalizedRssi) + (BATTERY_WEIGHT * normalizedBattery);
    if (hasEspnow) {
      score += 0.15;
    }
    return score;
  }

public:
  void begin(char nodeId) {
    myNodeId = nodeId;
    nextHop = 'S';  // Default to sink (direct connection)
    hopCount = 1;
    neighborCount = 0;
    lastRouteUpdate = 0;
    lastSinkRssi = -100;

    // Initialize neighbor slots
    for (int i = 0; i < MAX_NEIGHBORS; i++) {
      neighbors[i].valid = false;
      espnowAvailable[i] = false;
    }

    LOGF("[ROUTING] Initialized for node %c, default next hop: SINK\n", myNodeId);
  }
  
  // Mark a neighbor as ESP-NOW reachable
  void setEspnowAvailable(char nodeId, bool available) {
    for (int i = 0; i < MAX_NEIGHBORS; i++) {
      if (neighbors[i].valid && neighbors[i].nodeId == nodeId) {
        espnowAvailable[i] = available;
        return;
      }
    }
  }
  
  // Check if a neighbor is ESP-NOW reachable
  bool isEspnowAvailable(char nodeId) {
    for (int i = 0; i < MAX_NEIGHBORS; i++) {
      if (neighbors[i].valid && neighbors[i].nodeId == nodeId) {
        return espnowAvailable[i];
      }
    }
    return false;
  }

  // Update neighbor information from beacon/ESP-NOW
  // hasSinkAccess = does this neighbor currently have MQTT connectivity to gateway?
  // wifiRssi = this neighbor's WiFi RSSI to sink (their direct path quality)
  void updateNeighbor(char nodeId, int rssi, float batteryPercent, bool hasSinkAccess = false, int wifiRssi = -100) {
    // Don't add self
    if (nodeId == myNodeId) return;

    // Find existing or empty slot
    int slot = -1;
    bool isNewNeighbor = true;
    int oldRssi = 0;
    float oldBattery = 0;
    
    for (int i = 0; i < MAX_NEIGHBORS; i++) {
      if (neighbors[i].valid && neighbors[i].nodeId == nodeId) {
        slot = i;
        isNewNeighbor = false;
        oldRssi = neighbors[i].rssi;
        oldBattery = neighbors[i].batteryPercent;
        break;
      }
      if (slot == -1 && !neighbors[i].valid) {
        slot = i;
      }
    }

    if (slot == -1) {
      // Table full, find oldest entry
      unsigned long oldest = millis();
      for (int i = 0; i < MAX_NEIGHBORS; i++) {
        if (neighbors[i].lastSeen < oldest) {
          oldest = neighbors[i].lastSeen;
          slot = i;
        }
      }
    }

    if (slot >= 0) {
      // Check if values changed significantly before logging
      bool significantChange = isNewNeighbor || 
                               abs(neighbors[slot].rssi - rssi) >= 5 ||
                               abs(neighbors[slot].batteryPercent - batteryPercent) >= 1.0 ||
                               neighbors[slot].hasSinkAccess != hasSinkAccess;
      
      neighbors[slot].nodeId = nodeId;
      neighbors[slot].rssi = rssi;
      neighbors[slot].wifiRssi = wifiRssi;  // Store neighbor's WiFi quality
      neighbors[slot].batteryPercent = batteryPercent;
      neighbors[slot].hasSinkAccess = hasSinkAccess;
      neighbors[slot].lastSeen = millis();
      neighbors[slot].valid = true;
      neighborCount = 0;
      for (int i = 0; i < MAX_NEIGHBORS; i++) {
        if (neighbors[i].valid) neighborCount++;
      }

      #if DEBUG_ROUTING
      // Only log if new neighbor or significant change (RSSI ±5dB or battery ±1%)
      if (significantChange) {
        LOGF("[Routing] %s neighbor %c: ESP-NOW=%ddBm, WiFi=%ddBm, Batt=%.1f%%, SinkAccess=%s\n",
                      isNewNeighbor ? "New" : "Updated",
                      nodeId, rssi, wifiRssi, batteryPercent, hasSinkAccess ? "YES" : "NO");
      }
      #endif
    }
  }

  // Update sink RSSI (from WiFi.RSSI())
  void updateSinkRssi(int rssi) {
    lastSinkRssi = rssi;
  }

  // Select best next hop based on current neighbor table
  // Uses path-quality comparison: direct WiFi vs multi-hop via relay
  RoutingDecision selectRoute(float myBatteryPercent) {
    RoutingDecision decision;
    decision.previousNextHop = nextHop;
    decision.candidateCount = 0;
    decision.selectedScore = 0;

    // Clean up stale neighbors (not seen in 60 seconds)
    unsigned long now = millis();
    for (int i = 0; i < MAX_NEIGHBORS; i++) {
      if (neighbors[i].valid && (now - neighbors[i].lastSeen) > 60000) {
        neighbors[i].valid = false;
        #if DEBUG_ROUTING
        LOGF("[Routing] Neighbor %c expired\n", neighbors[i].nodeId);
        #endif
      }
    }

    // === DIRECT PATH: this node -> WiFi -> sink ===
    float directPathScore = calculateDirectPathScore(lastSinkRssi, myBatteryPercent);
    decision.candidates[decision.candidateCount].targetId = 'S';
    decision.candidates[decision.candidateCount].rssi = lastSinkRssi;
    decision.candidates[decision.candidateCount].batteryPercent = myBatteryPercent;
    decision.candidates[decision.candidateCount].score = directPathScore;
    decision.candidateCount++;

    #if DEBUG_ROUTING
    LOGF("[Routing] Path comparison for node %c:\n", myNodeId);
    LOGF("  DIRECT: WiFi=%ddBm -> score=%.3f\n", lastSinkRssi, directPathScore);
    #endif

    // === MULTI-HOP PATHS: this node -> ESP-NOW -> relay -> WiFi -> sink ===
    for (int i = 0; i < MAX_NEIGHBORS; i++) {
      if (neighbors[i].valid && decision.candidateCount < MAX_NEIGHBORS + 1) {
        // Skip neighbors with very low battery (< 15%) unless they have good sink access
        if (neighbors[i].batteryPercent < 15 && !neighbors[i].hasSinkAccess) continue;

        // Calculate multi-hop path quality
        float multiHopScore = calculateMultiHopPathScore(
          neighbors[i].rssi,        // ESP-NOW link quality to relay
          neighbors[i].wifiRssi,    // Relay's WiFi quality to sink
          neighbors[i].batteryPercent,
          neighbors[i].hasSinkAccess
        );
        
        // Skip invalid paths (relay has no sink access)
        if (multiHopScore < 0) {
          #if DEBUG_ROUTING
          LOGF("  VIA %c: No sink access - SKIPPED\n", neighbors[i].nodeId);
          #endif
          continue;
        }
        
        #if DEBUG_ROUTING
        LOGF("  VIA %c: ESP-NOW=%ddBm, relayWiFi=%ddBm, relayBatt=%.0f%% -> score=%.3f\n",
                      neighbors[i].nodeId, neighbors[i].rssi, neighbors[i].wifiRssi,
                      neighbors[i].batteryPercent, multiHopScore);
        #endif
        
        decision.candidates[decision.candidateCount].targetId = neighbors[i].nodeId;
        decision.candidates[decision.candidateCount].rssi = neighbors[i].rssi;
        decision.candidates[decision.candidateCount].batteryPercent = neighbors[i].batteryPercent;
        decision.candidates[decision.candidateCount].score = multiHopScore;
        decision.candidateCount++;
      }
    }

    // Find best candidate (highest score wins)
    int bestIdx = 0;
    float bestScore = decision.candidates[0].score;
    
    for (int i = 1; i < decision.candidateCount; i++) {
      if (decision.candidates[i].score > bestScore) {
        bestScore = decision.candidates[i].score;
        bestIdx = i;
      }
    }

    // Update routing
    decision.newNextHop = decision.candidates[bestIdx].targetId;
    decision.selectedScore = bestScore;

    // Determine reason for change
    if (decision.previousNextHop != decision.newNextHop) {
      if (decision.candidates[bestIdx].targetId == 'S') {
        decision.reason = String("Direct path better (") + String(lastSinkRssi) + "dBm WiFi)";
      } else {
        char relayId = decision.newNextHop;
        int relayIdx = -1;
        for (int i = 0; i < MAX_NEIGHBORS; i++) {
          if (neighbors[i].valid && neighbors[i].nodeId == relayId) {
            relayIdx = i;
            break;
          }
        }
        if (relayIdx >= 0) {
          decision.reason = String("Multi-hop via ") + relayId + 
                            " (ESP-NOW=" + neighbors[relayIdx].rssi + 
                            "dBm, relayWiFi=" + neighbors[relayIdx].wifiRssi + "dBm)";
        } else {
          decision.reason = String("Multi-hop via ") + relayId;
        }
      }
    } else {
      decision.reason = "No change - current route optimal";
    }

    // Apply new route
    nextHop = decision.newNextHop;
    if (nextHop == 'S') {
      hopCount = 1;
    } else {
      hopCount = 2;
    }
    lastRouteUpdate = now;

    #if DEBUG_ROUTING
    LOGF("[Routing] SELECTED: %c -> %c (score: %.3f) | %s\n", 
                  myNodeId, nextHop, bestScore, decision.reason.c_str());
    #endif

    return decision;
  }

  // Check if route update is needed
  bool needsRouteUpdate() {
    // Update if significant RSSI change or interval elapsed
    int currentRssi = WiFi.RSSI();
    bool rssiChanged = abs(currentRssi - lastSinkRssi) > RSSI_CHANGE_THRESHOLD;
    bool intervalElapsed = (millis() - lastRouteUpdate) >= ROUTING_UPDATE_INTERVAL_MS;
    
    return rssiChanged || intervalElapsed;
  }

  // Get current next hop
  char getNextHop() {
    return nextHop;
  }

  // Get hop count
  int getHopCount() {
    return hopCount;
  }

  // Build route string (for telemetry)
  String getRouteString() {
    String route = String(myNodeId);
    if (nextHop != 'S') {
      route += " -> ";
      route += nextHop;
    }
    route += " -> SINK";
    return route;
  }

  // Get list of route nodes
  void getRouteArray(char* routeArray, int* length) {
    *length = 0;
    routeArray[(*length)++] = myNodeId;
    if (nextHop != 'S') {
      routeArray[(*length)++] = nextHop;
    }
    routeArray[(*length)++] = 'S';  // Sink
  }

  // Create neighbor beacon JSON - includes WiFi RSSI for path quality comparison
  String createNeighborBeacon(float batteryPercent) {
    int wifiRssi = WiFi.status() == WL_CONNECTED ? WiFi.RSSI() : -100;
    bool hasSinkAccess = WiFi.status() == WL_CONNECTED;
    
    String json = "{";
    json += "\"nodeId\":\"" + String(myNodeId) + "\",";
    json += "\"battery\":" + String(batteryPercent, 1) + ",";
    json += "\"wifiRssi\":" + String(wifiRssi) + ",";          // Our WiFi quality for path calculation
    json += "\"hasSinkAccess\":" + String(hasSinkAccess ? "true" : "false") + ",";
    json += "\"timestamp\":" + String(millis());
    json += "}";
    return json;
  }

  // Check if a message should be forwarded (not for us and TTL > 0)
  bool shouldForward(char destNodeId, int ttl, const char* visitedNodes) {
    // Don't forward if we're the destination
    if (destNodeId == myNodeId) return false;
    
    // Don't forward if TTL expired
    if (ttl <= 0) return false;
    
    // Don't forward if we're in the visited list (loop prevention)
    if (visitedNodes != nullptr && strchr(visitedNodes, myNodeId) != nullptr) {
      return false;
    }
    
    return true;
  }
};

#endif // ROUTING_H
