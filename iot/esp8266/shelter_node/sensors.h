/**
 * Sensor Drivers for Shelter Node
 * ================================
 * 
 * Handles:
 * - HC-SR04 Ultrasonic sensor (cat presence detection)
 * - TCS3200 Color sensor (food/plate detection)
 */

#ifndef SENSORS_H
#define SENSORS_H

#include <Arduino.h>
#include "config.h"

// ============================================================================
// SENSOR DATA STRUCTURES
// ============================================================================

struct UltrasonicReading {
  float distanceCm;
  bool catPresent;
  bool valid;
};

struct ColorReading {
  int red;
  int green;
  int blue;
  bool isBrown;
  bool valid;
};

struct SensorData {
  UltrasonicReading ultrasonic;
  ColorReading color;
  bool plateEmpty;        // Derived: !isBrown && !catPresent
  unsigned long timestamp;
};

// ============================================================================
// ULTRASONIC SENSOR (HC-SR04)
// ============================================================================

class UltrasonicSensor {
public:
  void begin() {
    pinMode(ULTRASONIC_TRIG_PIN, OUTPUT);
    pinMode(ULTRASONIC_ECHO_PIN, INPUT);
    digitalWrite(ULTRASONIC_TRIG_PIN, LOW);
    LOGLN("  [Ultrasonic] Initialized on TRIG=D5, ECHO=D6");
  }

  UltrasonicReading read() {
    UltrasonicReading result;
    result.valid = false;
    result.catPresent = false;
    result.distanceCm = ULTRASONIC_MAX_DISTANCE_CM;

    // Send trigger pulse
    digitalWrite(ULTRASONIC_TRIG_PIN, LOW);
    delayMicroseconds(2);
    digitalWrite(ULTRASONIC_TRIG_PIN, HIGH);
    delayMicroseconds(10);
    digitalWrite(ULTRASONIC_TRIG_PIN, LOW);

    // Read echo with timeout
    unsigned long duration = pulseIn(ULTRASONIC_ECHO_PIN, HIGH, 30000); // 30ms timeout

    if (duration > 0) {
      // Calculate distance: speed of sound = 343 m/s = 0.0343 cm/µs
      // Distance = (duration * 0.0343) / 2 (round trip)
      result.distanceCm = (duration * 0.0343) / 2.0;
      
      // Validate range
      if (result.distanceCm >= ULTRASONIC_MIN_DISTANCE_CM && 
          result.distanceCm <= ULTRASONIC_MAX_DISTANCE_CM) {
        result.valid = true;
        result.catPresent = (result.distanceCm < CAT_PRESENCE_THRESHOLD_CM);
      }
    }

    #if DEBUG_SENSORS
    LOGF("[Ultrasonic] Distance: %.1f cm, Cat: %s, Valid: %s\n",
                  result.distanceCm,
                  result.catPresent ? "YES" : "NO",
                  result.valid ? "YES" : "NO");
    #endif

    return result;
  }
};

// ============================================================================
// COLOR SENSOR (TCS3200 / HW-531) - SIMPLIFIED RED-ONLY DETECTION
// ============================================================================
// 
// Hardware simplification: S2 and S3 are hardwired to GND
// This permanently selects the RED photodiode filter.
// Only 3 GPIO pins needed: S0, S1, OUT
//
// Why RED instead of brown?
// - Uses fewer GPIO pins (saves 2 pins!)
// - Simpler detection logic (single threshold)
// - Many cat foods have red/orange tint
// - Use red-colored kibble or red bowl marker
//
// ============================================================================

class ColorSensor {
private:
  int lastRawReading;
  
  // Read pulse count from RED filter (S2/S3 hardwired LOW)
  // Lower count = more red light = food present
  // Higher count = less red light = empty plate
  int readRedPulseCount() {
    unsigned long pulseCount = 0;
    const unsigned long sampleTimeUs = 50000; // 50ms sample time
    unsigned long startTime = micros();

    while ((micros() - startTime) < sampleTimeUs) {
      // Wait for LOW pulse from sensor
      unsigned long pulse = pulseIn(COLOR_OUT_PIN, LOW, 2000); // 2ms timeout per pulse
      if (pulse > 0) {
        pulseCount++;
      }
    }

    return (int)pulseCount;
  }

public:
  void begin() {
    // Only need 3 pins - S2/S3 are hardwired to GND
    pinMode(COLOR_S0_PIN, OUTPUT);
    pinMode(COLOR_S1_PIN, OUTPUT);
    pinMode(COLOR_OUT_PIN, INPUT);

    // Set frequency scaling to 2% (S0=HIGH, S1=LOW)
    // Low frequency is easier for ESP8266 to count reliably
    digitalWrite(COLOR_S0_PIN, HIGH);
    digitalWrite(COLOR_S1_PIN, LOW);

    lastRawReading = 0;

    LOGLN("  [Color] TCS3200 initialized (RED-only mode)");
    LOGLN("          S0=D1(GPIO5), S1=D2(GPIO4), OUT=D7(GPIO13)");
    LOGLN("          S2/S3 hardwired to GND for red filter");
  }

  ColorReading read() {
    ColorReading result;
    result.valid = true;
    result.green = 0;  // Not measured in simplified mode
    result.blue = 0;   // Not measured in simplified mode

    // Read RED channel (only channel available with S2/S3 grounded)
    lastRawReading = readRedPulseCount();
    result.red = lastRawReading;

    // Determine if food is present (bright surface = food)
    // Note: color.isBrown now means "food detected" (keeping field name for compatibility)
    result.isBrown = isFoodPresent(lastRawReading);

    #if DEBUG_SENSORS
    const char* status = "UNKNOWN";
    const char* type = "";
    if (lastRawReading <= COLOR_EMPTY_THRESHOLD) {
      status = "EMPTY (dark)";
    } else if (isRedFood(lastRawReading)) {
      status = "FOOD DETECTED";
      type = " [RED]";
    } else {
      status = "FOOD DETECTED";
      type = " [WHITE/demo]";
    }
    LOGF("[Color] Pulses: %d = %s%s (empty<%d, red:%d-%d)\n",
                  lastRawReading, status, type,
                  COLOR_EMPTY_THRESHOLD, COLOR_RED_MIN_THRESHOLD, COLOR_RED_MAX_THRESHOLD);
    #endif

    return result;
  }

  // Check if food is detected (any bright surface = food)
  // NEW LOGIC: Dark = empty, Light = food
  bool isFoodPresent(int pulseCount) {
    // Food detected when pulse count is above the empty threshold
    // (brighter surfaces = more reflection = food present)
    return (pulseCount > COLOR_EMPTY_THRESHOLD);
  }
  
  // Check if detected food is in the RED range (for Flutter warning)
  bool isRedFood(int pulseCount) {
    return (pulseCount > COLOR_RED_MIN_THRESHOLD && 
            pulseCount < COLOR_RED_MAX_THRESHOLD);
  }
  
  // Check if detected food is WHITE/bright (demo mode, for Flutter warning)
  bool isWhiteFood(int pulseCount) {
    return (pulseCount >= COLOR_RED_MAX_THRESHOLD);
  }
  
  // Check if plate is empty (dark surface)
  bool isPlateEmpty(int pulseCount) {
    return (pulseCount <= COLOR_EMPTY_THRESHOLD);
  }
  
  // Get raw reading for calibration
  int getRawReading() {
    return lastRawReading;
  }
};

// ============================================================================
// COMBINED SENSOR MANAGER
// ============================================================================

class SensorManager {
private:
  UltrasonicSensor ultrasonic;
  ColorSensor color;
  SensorData lastReading;
  unsigned long lastReadTime;

public:
  void begin() {
    LOGLN("[SENSOR] Initializing sensors...");
    LOGLN("         Using SIMPLIFIED pin configuration:");
    LOGLN("         - Ultrasonic: TRIG=D5(GPIO14), ECHO=D6(GPIO12)");
    LOGLN("         - Color: S0=D1(GPIO5), S1=D2(GPIO4), OUT=D7(GPIO13)");
    LOGLN("         - Color S2/S3 HARDWIRED to GND (red filter only)");
    LOGLN("         - Status LED: D0(GPIO16)");
    LOGLN("         Total GPIO pins used: 6 (all safe pins!)");
    ultrasonic.begin();
    color.begin();
    lastReadTime = 0;
    LOGLN("[OK] Sensors ready");
  }

  SensorData readAll() {
    SensorData data;
    data.timestamp = millis();

    // Read ultrasonic first (cat presence)
    data.ultrasonic = ultrasonic.read();

    // Read color sensor (red food detection)
    data.color = color.read();

    // Determine plate status
    // Empty plate alert: food NOT detected AND cat NOT present
    // Note: color.isBrown now means "red food detected"
    if (!data.ultrasonic.catPresent && !data.color.isBrown) {
      data.plateEmpty = true;
    } else {
      data.plateEmpty = false;
    }

    lastReading = data;
    lastReadTime = millis();

    return data;
  }

  SensorData getLastReading() {
    return lastReading;
  }

  bool needsReading() {
    return (millis() - lastReadTime) >= SENSOR_READ_INTERVAL_MS;
  }
  
  // Get raw color reading for calibration
  int getColorRawReading() {
    return color.getRawReading();
  }

  // Get plate status string
  const char* getPlateStatusString() {
    if (lastReading.color.isBrown) {
      return "filled";
    } else if (lastReading.ultrasonic.catPresent) {
      return "eating";  // Cat present, might be eating
    } else {
      return "empty";
    }
  }
};

#endif // SENSORS_H
