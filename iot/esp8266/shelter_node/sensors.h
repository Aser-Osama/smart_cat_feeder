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
    Serial.println("  [Ultrasonic] Initialized on TRIG=D5, ECHO=D6");
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
    Serial.printf("  [Ultrasonic] Distance: %.1f cm, Cat: %s, Valid: %s\n",
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

    Serial.println("  [Color] TCS3200 initialized (RED-only mode)");
    Serial.println("          S0=D1(GPIO5), S1=D2(GPIO4), OUT=D7(GPIO13)");
    Serial.println("          S2/S3 hardwired to GND for red filter");
  }

  ColorReading read() {
    ColorReading result;
    result.valid = true;
    result.green = 0;  // Not measured in simplified mode
    result.blue = 0;   // Not measured in simplified mode

    // Read RED channel (only channel available with S2/S3 grounded)
    lastRawReading = readRedPulseCount();
    result.red = lastRawReading;

    // Determine if RED food is present
    // Lower pulse count = stronger red reflection = food present
    result.isBrown = isRedFoodPresent(lastRawReading);

    #if DEBUG_SENSORS
    Serial.printf("  [Color] Red pulses: %d, Food present: %s\n",
                  lastRawReading,
                  result.isBrown ? "YES" : "NO");
    #endif

    return result;
  }

  // Check if red food is detected
  // Uses simple threshold - calibrate for your specific setup
  bool isRedFoodPresent(int pulseCount) {
    // Lower pulse count = more red light reflected = food present
    return (pulseCount < COLOR_FOOD_PRESENT_THRESHOLD);
  }
  
  // Check if plate is definitely empty
  bool isPlateEmpty(int pulseCount) {
    return (pulseCount > COLOR_PLATE_EMPTY_THRESHOLD);
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
    Serial.println("📡 Initializing sensors...");
    Serial.println("   Using SIMPLIFIED pin configuration:");
    Serial.println("   - Ultrasonic: TRIG=D5(GPIO14), ECHO=D6(GPIO12)");
    Serial.println("   - Color: S0=D1(GPIO5), S1=D2(GPIO4), OUT=D7(GPIO13)");
    Serial.println("   - Color S2/S3 HARDWIRED to GND (red filter only)");
    Serial.println("   - Status LED: D0(GPIO16)");
    Serial.println("   Total GPIO pins used: 6 (all safe pins!)");
    ultrasonic.begin();
    color.begin();
    lastReadTime = 0;
    Serial.println("✅ Sensors ready");
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
