/**
 * Battery Simulation for Shelter Node
 * ====================================
 * 
 * Simulates realistic battery drain based on ESP8266 current draw.
 * Battery percentage affects routing decisions.
 */

#ifndef BATTERY_H
#define BATTERY_H

#include <Arduino.h>
#include "config.h"

// ============================================================================
// BATTERY SIMULATION CLASS
// ============================================================================

class BatterySimulator {
private:
  float capacityMah;        // Total capacity in mAh
  float remainingMah;       // Remaining capacity in mAh
  float drainedMah;         // Total drained in mAh
  unsigned long lastUpdateTime;

  // Calculate voltage from percentage (linear approximation for Li-ion)
  float calculateVoltage(float percent) {
    // Li-ion voltage curve: ~4.2V full, ~3.0V empty
    // Using linear approximation for simplicity
    return 3.0 + (percent / 100.0) * 1.2;
  }

public:
  void begin(float initialPercent = -1) {
    capacityMah = BATTERY_CAPACITY_MAH;
    
    // If no initial percent specified, randomize between 60-100%
    if (initialPercent < 0) {
      initialPercent = 60.0 + (random(0, 40));
    }
    
    remainingMah = (initialPercent / 100.0) * capacityMah;
    drainedMah = capacityMah - remainingMah;
    lastUpdateTime = millis();

    LOGF("[BATTERY] Simulator initialized: %.1f%% (%.0f/%.0f mAh)\n",
                  initialPercent, remainingMah, capacityMah);
  }

  // Drain battery based on time elapsed and activity
  void update(bool sensorActive, bool wifiTx, bool wifiRx) {
    unsigned long now = millis();
    float elapsedSec = (now - lastUpdateTime) / 1000.0;
    lastUpdateTime = now;

    if (elapsedSec <= 0 || elapsedSec > 60) {
      // Skip invalid time intervals
      return;
    }

    // Calculate current draw based on activity
    float currentMa = CURRENT_IDLE_MA;

    if (sensorActive) {
      currentMa += CURRENT_SENSOR_MA;
    }
    if (wifiTx) {
      currentMa += CURRENT_WIFI_TX_MA;
    }
    if (wifiRx) {
      currentMa += CURRENT_WIFI_RX_MA;
    }

    // Calculate drain: mAh = mA * hours
    float drainMah = currentMa * (elapsedSec / 3600.0);
    
    // Apply drain
    remainingMah = max(0.0f, remainingMah - drainMah);
    drainedMah += drainMah;

    #if DEBUG_BATTERY
    static unsigned long lastDebugPrint = 0;
    if (now - lastDebugPrint > 30000) {  // Print every 30s
      LOGF("[BATTERY] %.1f%% (%.1f mAh remaining, drain rate: %.2f mA)\n",
                    getPercent(), remainingMah, currentMa);
      lastDebugPrint = now;
    }
    #endif
  }

  // Manual drain for specific activities (alternative to continuous update)
  void drainForActivity(float durationSec, float currentMa) {
    float drainMah = currentMa * (durationSec / 3600.0);
    remainingMah = max(0.0f, remainingMah - drainMah);
    drainedMah += drainMah;
  }

  // Drain for a typical sensor cycle
  void drainForSensorCycle() {
    drainForActivity(SENSOR_READ_DURATION_SEC, CURRENT_SENSOR_MA);
  }

  // Drain for WiFi transmission
  void drainForWifiTx() {
    drainForActivity(WIFI_TX_DURATION_SEC, CURRENT_WIFI_TX_MA);
  }

  // Drain for WiFi reception
  void drainForWifiRx() {
    drainForActivity(WIFI_RX_DURATION_SEC, CURRENT_WIFI_RX_MA);
  }

  // Drain for idle period
  void drainForIdle(float seconds) {
    drainForActivity(seconds, CURRENT_IDLE_MA);
  }

  // Get current percentage
  float getPercent() {
    return (remainingMah / capacityMah) * 100.0;
  }

  // Get voltage estimate
  float getVoltage() {
    return calculateVoltage(getPercent());
  }

  // Get remaining capacity
  float getRemainingMah() {
    return remainingMah;
  }

  // Get drained capacity
  float getDrainedMah() {
    return drainedMah;
  }

  // Get capacity
  float getCapacityMah() {
    return capacityMah;
  }

  // Check if battery is critical (< 10%)
  bool isCritical() {
    return getPercent() < 10.0;
  }

  // Check if battery is low (< 30%)
  bool isLow() {
    return getPercent() < 30.0;
  }

  // Simulate battery replacement (reset to 100%)
  void replaceBattery() {
    remainingMah = capacityMah;
    drainedMah = 0;
    LOGLN("[BATTERY] Battery replaced - 100%");
  }

  // Set specific percentage (for testing)
  void setPercent(float percent) {
    percent = constrain(percent, 0, 100);
    remainingMah = (percent / 100.0) * capacityMah;
    drainedMah = capacityMah - remainingMah;
    LOGF("[BATTERY] Battery set to %.1f%%\n", percent);
  }
};

#endif // BATTERY_H
