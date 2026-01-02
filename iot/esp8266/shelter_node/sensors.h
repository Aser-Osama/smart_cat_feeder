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
    LOGLN("  [Ultrasonic] Initialized on TRIG=D5(GPIO14), ECHO=D6(GPIO12)");
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
// COLOR SENSOR (TCS3200 / HW-531) - FULL RGB BROWN DETECTION
// ============================================================================
// 
// Hardware: Full RGB mode using all control pins
// S2 and S3 control which photodiode filter is active
// All 5 control pins needed: S0, S1, S2, S3, OUT
//
// Brown detection:
// - Reads all three RGB channels sequentially
// - Brown = low-medium red, low-medium green, very low blue
// - Validates color ratios to distinguish brown from other colors
//
// ============================================================================

class ColorSensor {
private:
  int lastRed, lastGreen, lastBlue;
  
  // Runtime calibration thresholds
  int redMin, redMax;
  int greenMin, greenMax;
  int blueMin, blueMax;
  int darkThreshold;
  float greenRedRatioMin, greenRedRatioMax;
  
  // Read pulse count for a specific color filter
  // filterS2, filterS3: control which photodiode (R, G, B, Clear)
  // Red:   S2=LOW,  S3=LOW
  // Green: S2=HIGH, S3=HIGH  
  // Blue:  S2=LOW,  S3=HIGH
  // Clear: S2=HIGH, S3=LOW
  int readColorPulseCount(bool filterS2, bool filterS3) {
    // Set filter selection
    digitalWrite(COLOR_S2_PIN, filterS2 ? HIGH : LOW);
    digitalWrite(COLOR_S3_PIN, filterS3 ? HIGH : LOW);
    
    // Small delay for filter to stabilize
    delayMicroseconds(100);
    
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
    // Initialize all 5 control pins for full RGB
    pinMode(COLOR_S0_PIN, OUTPUT);
    pinMode(COLOR_S1_PIN, OUTPUT);
    pinMode(COLOR_S2_PIN, OUTPUT);
    pinMode(COLOR_S3_PIN, OUTPUT);
    pinMode(COLOR_OUT_PIN, INPUT);

    // Set frequency scaling to 20% (S0=HIGH, S1=HIGH)
    // 2% was too low - need higher frequency for readable pulse counts
    digitalWrite(COLOR_S0_PIN, HIGH);
    digitalWrite(COLOR_S1_PIN, HIGH);
    
    // Initialize filter to red (S2=LOW, S3=LOW)
    digitalWrite(COLOR_S2_PIN, LOW);
    digitalWrite(COLOR_S3_PIN, LOW);

    lastRed = lastGreen = lastBlue = 0;
    
    // Initialize with default thresholds from config.h
    redMin = COLOR_BROWN_RED_MIN;
    redMax = COLOR_BROWN_RED_MAX;
    greenMin = COLOR_BROWN_GREEN_MIN;
    greenMax = COLOR_BROWN_GREEN_MAX;
    blueMin = COLOR_BROWN_BLUE_MIN;
    blueMax = COLOR_BROWN_BLUE_MAX;
    darkThreshold = COLOR_DARK_THRESHOLD;
    greenRedRatioMin = COLOR_GREEN_RED_RATIO_MIN;
    greenRedRatioMax = COLOR_GREEN_RED_RATIO_MAX;

    LOGLN("  [Color] TCS3200 initialized (Full RGB mode)");
    LOGLN("          S0=D1(GPIO5), S1=D2(GPIO4), S2=D7(GPIO13), S3=D4(GPIO2), OUT=D3(GPIO0)");
    LOGLN("          BROWN detection via RGB analysis");
    LOGLN("          GPIO0/GPIO2 safe after boot as OUTPUT/INPUT");
  }

  ColorReading read() {
    ColorReading result;
    result.valid = true;

    // Read all three RGB channels
    // Red:   S2=LOW,  S3=LOW
    // Green: S2=HIGH, S3=HIGH
    // Blue:  S2=LOW,  S3=HIGH
    lastRed = readColorPulseCount(false, false);   // Red
    lastGreen = readColorPulseCount(true, true);   // Green
    lastBlue = readColorPulseCount(false, true);   // Blue
    
    result.red = lastRed;
    result.green = lastGreen;
    result.blue = lastBlue;

    // Determine if brown food is present
    result.isBrown = isBrownFood(lastRed, lastGreen, lastBlue);

    #if DEBUG_SENSORS
    const char* status = result.isBrown ? "BROWN FOOD" : "NOT BROWN";
    LOGF("[Color] R:%d G:%d B:%d = %s\n",
                  lastRed, lastGreen, lastBlue, status);
    if (result.isBrown) {
      float grRatio = lastRed > 0 ? (float)lastGreen / (float)lastRed : 0;
      LOGF("        G/R ratio: %.2f (target: %.1f-%.1f)\n",
                    grRatio, COLOR_GREEN_RED_RATIO_MIN, COLOR_GREEN_RED_RATIO_MAX);
    }
    #endif

    return result;
  }

  // Check if the RGB values match calibrated food color characteristics
  bool isBrownFood(int red, int green, int blue) {
    // Check if any channel is too dark (empty plate)
    if (red < darkThreshold || green < darkThreshold) {
      return false;
    }
    
    // Check if values are in calibrated color range
    if (red < redMin || red > redMax) {
      return false;
    }
    if (green < greenMin || green > greenMax) {
      return false;
    }
    if (blue < blueMin || blue > blueMax) {
      return false;
    }
    
    // Check green/red ratio (validates color consistency)
    if (red > 0) {
      float greenRedRatio = (float)green / (float)red;
      if (greenRedRatio < greenRedRatioMin || 
          greenRedRatio > greenRedRatioMax) {
        return false;
      }
    }
    
    return true;  // All checks passed - it's brown!
  }
  
  // Update calibration thresholds at runtime
  void updateCalibration(int rMin, int rMax, int gMin, int gMax, int bMin, int bMax, 
                         int darkT, float grMin, float grMax) {
    redMin = rMin;
    redMax = rMax;
    greenMin = gMin;
    greenMax = gMax;
    blueMin = bMin;
    blueMax = bMax;
    darkThreshold = darkT;
    greenRedRatioMin = grMin;
    greenRedRatioMax = grMax;
  }
  
  // Get raw readings for calibration
  int getRedReading() { return lastRed; }
  int getGreenReading() { return lastGreen; }
  int getBlueReading() { return lastBlue; }
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
    LOGLN("         Using FULL RGB pin configuration:");
    LOGLN("         - Ultrasonic: TRIG=D5(GPIO14), ECHO=D6(GPIO12)");
    LOGLN("         - Color: S0=D1(GPIO5), S1=D2(GPIO4), S2=D7(GPIO13), S3=D4(GPIO2), OUT=D3(GPIO0)");
    LOGLN("         - Status LED: D0(GPIO16)");
    LOGLN("         - GPIO0/GPIO2 safe after boot (not driven during boot)");
    LOGLN("         Total GPIO pins used: 7 (BOOT-SAFE configuration!)");
    LOGLN("         Detecting BROWN food via RGB analysis");
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

    // Read color sensor (brown food detection)
    data.color = color.read();

    // Determine plate status
    // Empty plate alert: brown food NOT detected AND cat NOT present
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
  
  // Get raw color readings for calibration
  int getColorRedReading() { return color.getRedReading(); }
  int getColorGreenReading() { return color.getGreenReading(); }
  int getColorBlueReading() { return color.getBlueReading(); }

  // Update calibration thresholds
  void updateCalibration(int rMin, int rMax, int gMin, int gMax, int bMin, int bMax,
                         int darkT, float grMin, float grMax) {
    color.updateCalibration(rMin, rMax, gMin, gMax, bMin, bMax, darkT, grMin, grMax);
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
