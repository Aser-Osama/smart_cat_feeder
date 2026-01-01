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
  int rssi;
  float batteryPercent;
  bool isSink;
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

  // Calculate routing score (higher is better)
  // ESP-NOW reachable peers get a bonus
  float calculateScore(int rssi, float batteryPercent, bool hasEspnow = false) {
    // Normalize RSSI: -100 dBm = 0, -50 dBm = 1
    float normalizedRssi = constrain((rssi + 100.0) / 50.0, 0.0, 1.0);
    
    // Normalize battery: 0% = 0, 100% = 1
    float normalizedBattery = batteryPercent / 100.0;

    // Weighted combination
    float score = (RSSI_WEIGHT * normalizedRssi) + (BATTERY_WEIGHT * normalizedBattery);
    
    // ESP-NOW bonus: prefer nodes we can reach directly via ESP-NOW
    // This encourages real mesh routing over WiFi-only
    if (hasEspnow) {
      score += 0.15;  // 15% bonus for ESP-NOW reachability
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

    Serial.printf("🔀 Routing initialized for node %c, default next hop: SINK\n", myNodeId);
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

  // Update neighbor information from beacon
  void updateNeighbor(char nodeId, int rssi, float batteryPercent, bool isSink = false) {
    // Don't add self
    if (nodeId == myNodeId) return;

    // Find existing or empty slot
    int slot = -1;
    for (int i = 0; i < MAX_NEIGHBORS; i++) {
      if (neighbors[i].valid && neighbors[i].nodeId == nodeId) {
        slot = i;
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
      neighbors[slot].nodeId = nodeId;
      neighbors[slot].rssi = rssi;
      neighbors[slot].batteryPercent = batteryPercent;
      neighbors[slot].isSink = isSink;
      neighbors[slot].lastSeen = millis();
      neighbors[slot].valid = true;
      neighborCount = 0;
      for (int i = 0; i < MAX_NEIGHBORS; i++) {
        if (neighbors[i].valid) neighborCount++;
      }

      #if DEBUG_ROUTING
      Serial.printf("  [Routing] Updated neighbor %c: RSSI=%d, Batt=%.1f%%, Sink=%s\n",
                    nodeId, rssi, batteryPercent, isSink ? "YES" : "NO");
      #endif
    }
  }

  // Update sink RSSI (from WiFi.RSSI())
  void updateSinkRssi(int rssi) {
    lastSinkRssi = rssi;
  }

  // Select best next hop based on current neighbor table
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
        Serial.printf("  [Routing] Neighbor %c expired\n", neighbors[i].nodeId);
        #endif
      }
    }

    // Always consider direct-to-sink as an option
    decision.candidates[decision.candidateCount].targetId = 'S';
    decision.candidates[decision.candidateCount].rssi = lastSinkRssi;
    decision.candidates[decision.candidateCount].batteryPercent = 100;  // Sink has "infinite" battery
    decision.candidates[decision.candidateCount].score = calculateScore(lastSinkRssi, 100, false);
    decision.candidateCount++;

    // Add valid neighbors as candidates
    for (int i = 0; i < MAX_NEIGHBORS; i++) {
      if (neighbors[i].valid && decision.candidateCount < MAX_NEIGHBORS + 1) {
        // Skip neighbors with very low battery (< 15%) - they shouldn't forward
        if (neighbors[i].batteryPercent < 15 && !neighbors[i].isSink) continue;

        // Check if this neighbor is reachable via ESP-NOW (bonus score)
        bool hasEspnow = espnowAvailable[i];
        float score = calculateScore(neighbors[i].rssi, neighbors[i].batteryPercent, hasEspnow);
        
        decision.candidates[decision.candidateCount].targetId = neighbors[i].nodeId;
        decision.candidates[decision.candidateCount].rssi = neighbors[i].rssi;
        decision.candidates[decision.candidateCount].batteryPercent = neighbors[i].batteryPercent;
        decision.candidates[decision.candidateCount].score = score;
        decision.candidateCount++;
      }
    }

    // Find best candidate
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
        decision.reason = "Direct to sink has best score";
      } else {
        bool viaEspnow = isEspnowAvailable(decision.newNextHop);
        decision.reason = String("Better score via ") + decision.newNextHop + 
                          (viaEspnow ? " (ESP-NOW)" : " (MQTT)");
      }
    } else {
      decision.reason = "No change - current route optimal";
    }

    // Apply new route
    nextHop = decision.newNextHop;
    if (nextHop == 'S') {
      hopCount = 1;
    } else {
      // When routing through another node, hop count increases
      hopCount = 2;  // Simplified - in reality would track actual path length
    }
    lastRouteUpdate = now;

    #if DEBUG_ROUTING
    Serial.printf("🔀 Route decision: %c -> %c (score: %.2f)\n", 
                  myNodeId, nextHop, bestScore);
    Serial.printf("   Reason: %s\n", decision.reason.c_str());
    Serial.printf("   Candidates: ");
    for (int i = 0; i < decision.candidateCount; i++) {
      Serial.printf("%c(%.2f) ", decision.candidates[i].targetId, decision.candidates[i].score);
    }
    Serial.println();
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

  // Create neighbor beacon JSON
  String createNeighborBeacon(float batteryPercent) {
    String json = "{";
    json += "\"nodeId\":\"" + String(myNodeId) + "\",";
    json += "\"battery\":" + String(batteryPercent, 1) + ",";
    json += "\"rssi\":" + String(WiFi.RSSI()) + ",";
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
