#!/usr/bin/env python3
"""
Smart Cat Feeder - Firebase ↔ MQTT Gateway
============================================
This gateway runs on the Orange Pi 3B and bridges:
- Firebase Firestore commands → MQTT messages to ESP8266
- MQTT status messages from ESP8266 → Firebase Firestore/FCM

Architecture:
    Flutter App ↔ Firebase Cloud ↔ [This Gateway] ↔ MQTT ↔ ESP8266
"""

import os
import sys
import json
import time
import signal
import logging
from datetime import datetime
from threading import Thread, Event

import paho.mqtt.client as mqtt
import firebase_admin
from firebase_admin import credentials, firestore, messaging

# ============================================================================
# Configuration
# ============================================================================

# MQTT Broker settings (local Mosquitto)
MQTT_BROKER = os.getenv("MQTT_BROKER", "localhost")
MQTT_PORT = int(os.getenv("MQTT_PORT", "1883"))
MQTT_CLIENT_ID = "orangepi-gateway"

# MQTT Topics
TOPIC_FEED_COMMAND = "feeder/control/dispense"      # Gateway → ESP: trigger feeding
TOPIC_FEED_STATUS = "feeder/status/fed"             # ESP → Gateway: feeding complete
TOPIC_CAT_DETECTED = "feeder/status/cat_detected"   # ESP → Gateway: cat presence
TOPIC_HEARTBEAT = "feeder/status/heartbeat"         # ESP → Gateway: alive check

# Firebase collection paths (will be prefixed with user ID)
# Structure: users/{userId}/commands/pending
#           users/{userId}/feeder/status

# Logging setup
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler('/var/log/smart-cat-feeder-gateway.log')
    ]
)
logger = logging.getLogger(__name__)

# ============================================================================
# Gateway Class
# ============================================================================

class SmartCatFeederGateway:
    def __init__(self):
        self.mqtt_client = None
        self.db = None
        self.stop_event = Event()
        self.connected_users = set()  # Track which users have active commands
        self.command_listeners = {}   # Firestore listeners per user
        
        # Initialize Firebase
        self._init_firebase()
        
        # Initialize MQTT
        self._init_mqtt()
    
    def _init_firebase(self):
        """Initialize Firebase Admin SDK"""
        try:
            # Check for credentials file
            cred_path = os.getenv(
                "GOOGLE_APPLICATION_CREDENTIALS",
                "/opt/smart-cat-feeder/firebase-credentials.json"
            )
            
            if not os.path.exists(cred_path):
                logger.error(f"Firebase credentials not found at: {cred_path}")
                logger.error("Please download from Firebase Console → Project Settings → Service Accounts")
                sys.exit(1)
            
            cred = credentials.Certificate(cred_path)
            firebase_admin.initialize_app(cred)
            self.db = firestore.client()
            logger.info("✅ Firebase initialized successfully")
            
        except Exception as e:
            logger.error(f"❌ Firebase initialization failed: {e}")
            sys.exit(1)
    
    def _init_mqtt(self):
        """Initialize MQTT client"""
        try:
            self.mqtt_client = mqtt.Client(client_id=MQTT_CLIENT_ID)
            self.mqtt_client.on_connect = self._on_mqtt_connect
            self.mqtt_client.on_disconnect = self._on_mqtt_disconnect
            self.mqtt_client.on_message = self._on_mqtt_message
            
            # Connect to broker
            self.mqtt_client.connect(MQTT_BROKER, MQTT_PORT, keepalive=60)
            logger.info(f"✅ MQTT connected to {MQTT_BROKER}:{MQTT_PORT}")
            
        except Exception as e:
            logger.error(f"❌ MQTT connection failed: {e}")
            sys.exit(1)
    
    def _on_mqtt_connect(self, client, userdata, flags, rc):
        """MQTT connection callback"""
        if rc == 0:
            logger.info("✅ MQTT broker connected")
            # Subscribe to ESP8266 status topics
            client.subscribe(TOPIC_FEED_STATUS)
            client.subscribe(TOPIC_CAT_DETECTED)
            client.subscribe(TOPIC_HEARTBEAT)
            logger.info(f"📡 Subscribed to ESP8266 topics")
        else:
            logger.error(f"❌ MQTT connection failed with code: {rc}")
    
    def _on_mqtt_disconnect(self, client, userdata, rc):
        """MQTT disconnection callback"""
        logger.warning(f"⚠️ MQTT disconnected (code: {rc}), attempting reconnect...")
        while not self.stop_event.is_set():
            try:
                client.reconnect()
                break
            except Exception as e:
                logger.error(f"Reconnect failed: {e}")
                time.sleep(5)
    
    def _on_mqtt_message(self, client, userdata, msg):
        """Handle incoming MQTT messages from ESP8266"""
        topic = msg.topic
        try:
            payload = json.loads(msg.payload.decode())
        except json.JSONDecodeError:
            payload = {"raw": msg.payload.decode()}
        
        logger.info(f"📨 MQTT [{topic}]: {payload}")
        
        if topic == TOPIC_FEED_STATUS:
            self._handle_feed_complete(payload)
        elif topic == TOPIC_CAT_DETECTED:
            self._handle_cat_detected(payload)
        elif topic == TOPIC_HEARTBEAT:
            self._handle_heartbeat(payload)
    
    def _handle_feed_complete(self, payload):
        """Handle feeding completion from ESP8266"""
        user_id = payload.get("userId")
        success = payload.get("success", True)
        amount = payload.get("amount", 50)
        
        if not user_id:
            logger.warning("Feed complete without userId, skipping Firestore update")
            return
        
        try:
            # Log feeding to Firestore
            log_ref = self.db.collection("users").document(user_id).collection("feeding_logs")
            log_ref.add({
                "timestamp": firestore.SERVER_TIMESTAMP,
                "amount": amount,
                "type": "manual",
                "success": success,
                "source": "iot",
                "notes": "Fed via IoT gateway"
            })
            
            # Update feeder status
            status_ref = self.db.collection("users").document(user_id).collection("feeder").document("status")
            status_doc = status_ref.get()
            current_level = 100
            if status_doc.exists:
                current_level = status_doc.to_dict().get("foodLevel", 100)
            
            status_ref.set({
                "foodLevel": max(0, current_level - 5),
                "lastFed": firestore.SERVER_TIMESTAMP,
                "lastUpdated": firestore.SERVER_TIMESTAMP
            }, merge=True)
            
            # Clear pending command
            self._clear_pending_command(user_id)
            
            # Send push notification
            self._send_notification(
                user_id,
                title="🍽️ Feeding Complete!",
                body=f"{amount}g dispensed for your cat",
                data={"type": "manual_feeding", "amount": str(amount)}
            )
            
            logger.info(f"✅ Feeding logged for user {user_id}")
            
        except Exception as e:
            logger.error(f"❌ Error logging feeding: {e}")
    
    def _handle_cat_detected(self, payload):
        """Handle cat detection from ESP8266"""
        user_id = payload.get("userId")
        detected = payload.get("detected", True)
        
        if not user_id:
            # Broadcast to all connected users
            logger.info("Cat detected, updating all connected users")
            for uid in self.connected_users:
                self._update_cat_status(uid, detected)
            return
        
        self._update_cat_status(user_id, detected)
    
    def _update_cat_status(self, user_id, detected):
        """Update cat detection status in Firestore"""
        try:
            status_ref = self.db.collection("users").document(user_id).collection("feeder").document("status")
            status_ref.set({
                "catDetected": detected,
                "lastCatDetection": firestore.SERVER_TIMESTAMP if detected else None,
                "lastUpdated": firestore.SERVER_TIMESTAMP
            }, merge=True)
            
            if detected:
                self._send_notification(
                    user_id,
                    title="🐱 Cat Detected!",
                    body="Your cat is at the feeder",
                    data={"type": "cat_detection"}
                )
            
            logger.info(f"✅ Cat status updated for user {user_id}: {detected}")
            
        except Exception as e:
            logger.error(f"❌ Error updating cat status: {e}")
    
    def _handle_heartbeat(self, payload):
        """Handle ESP8266 heartbeat"""
        logger.debug(f"💓 ESP8266 heartbeat: {payload}")
    
    def _send_notification(self, user_id, title, body, data=None):
        """Send FCM push notification to user"""
        try:
            # Get user's FCM tokens
            tokens_ref = self.db.collection("users").document(user_id).collection("fcm_tokens")
            tokens = [doc.id for doc in tokens_ref.stream()]
            
            if not tokens:
                logger.info(f"No FCM tokens for user {user_id}")
                return
            
            message = messaging.MulticastMessage(
                notification=messaging.Notification(title=title, body=body),
                data=data or {},
                tokens=tokens
            )
            
            response = messaging.send_each_for_multicast(message)
            logger.info(f"📱 Notification sent: {response.success_count} success, {response.failure_count} failed")
            
            # Clean up invalid tokens
            for idx, resp in enumerate(response.responses):
                if not resp.success and hasattr(resp.exception, 'code'):
                    if resp.exception.code in ['messaging/invalid-registration-token', 
                                                'messaging/registration-token-not-registered']:
                        tokens_ref.document(tokens[idx]).delete()
                        logger.info(f"Removed invalid token: {tokens[idx][:20]}...")
            
        except Exception as e:
            logger.error(f"❌ Error sending notification: {e}")
    
    def _clear_pending_command(self, user_id):
        """Clear pending feed command for user"""
        try:
            cmd_ref = self.db.collection("users").document(user_id).collection("commands").document("pending")
            cmd_ref.delete()
        except Exception as e:
            logger.error(f"Error clearing command: {e}")
    
    def _setup_firestore_listeners(self):
        """Set up Firestore listeners for all users with commands"""
        logger.info("🔄 Setting up Firestore listeners...")
        
        # Listen to all users' command collections
        def on_users_snapshot(users_snapshot, changes, read_time):
            for change in changes:
                user_id = change.document.id
                if change.type.name == 'ADDED' or change.type.name == 'MODIFIED':
                    self.connected_users.add(user_id)
                    if user_id not in self.command_listeners:
                        self._setup_user_command_listener(user_id)
        
        # Initial setup - get all users
        users_ref = self.db.collection("users")
        users_ref.on_snapshot(on_users_snapshot)
    
    def _setup_user_command_listener(self, user_id):
        """Set up command listener for a specific user"""
        def on_command_snapshot(doc_snapshot, changes, read_time):
            for doc in doc_snapshot:
                if doc.exists:
                    command = doc.to_dict()
                    self._process_command(user_id, command)
        
        cmd_ref = self.db.collection("users").document(user_id).collection("commands").document("pending")
        self.command_listeners[user_id] = cmd_ref.on_snapshot(on_command_snapshot)
        logger.info(f"👂 Listening for commands from user: {user_id}")
    
    def _process_command(self, user_id, command):
        """Process a command from Firestore and relay to MQTT"""
        cmd_type = command.get("type")
        
        if cmd_type == "feed":
            amount = command.get("amount", 50)
            logger.info(f"🍽️ Feed command from {user_id}: {amount}g")
            
            # Publish to MQTT for ESP8266
            mqtt_payload = json.dumps({
                "userId": user_id,
                "command": "feed",
                "amount": amount,
                "timestamp": datetime.now().isoformat()
            })
            self.mqtt_client.publish(TOPIC_FEED_COMMAND, mqtt_payload)
            logger.info(f"📤 MQTT published to {TOPIC_FEED_COMMAND}")
        
        elif cmd_type == "ping":
            logger.info(f"🏓 Ping from {user_id}")
            # Could ping ESP8266 and report back
    
    def run(self):
        """Main run loop"""
        logger.info("🚀 Smart Cat Feeder Gateway starting...")
        
        # Set up Firestore listeners
        self._setup_firestore_listeners()
        
        # Start MQTT loop in background thread
        self.mqtt_client.loop_start()
        
        # Keep running until stopped
        try:
            while not self.stop_event.is_set():
                time.sleep(1)
        except KeyboardInterrupt:
            logger.info("⏹️ Shutdown requested...")
        finally:
            self.stop()
    
    def stop(self):
        """Clean shutdown"""
        logger.info("🛑 Shutting down gateway...")
        self.stop_event.set()
        self.mqtt_client.loop_stop()
        self.mqtt_client.disconnect()
        logger.info("✅ Gateway stopped")


# ============================================================================
# Main Entry Point
# ============================================================================

def main():
    # Handle signals for graceful shutdown
    gateway = SmartCatFeederGateway()
    
    def signal_handler(sig, frame):
        gateway.stop()
        sys.exit(0)
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    gateway.run()


if __name__ == "__main__":
    main()

