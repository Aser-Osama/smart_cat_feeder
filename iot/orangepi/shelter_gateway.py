#!/usr/bin/env python3
"""
Shelter Cat Monitoring - Firebase ↔ MQTT Gateway
=================================================

This gateway runs on the Orange Pi 3B and bridges:
- MQTT messages from 4 ESP8266 nodes (W, X, Y, Z) → Firebase Firestore
- Firebase configuration updates → MQTT broadcast to nodes
- Alert processing and FCM push notifications

Architecture:
    ESP8266 Nodes (W,X,Y,Z) ↔ MQTT ↔ [This Gateway] ↔ Firebase Cloud ↔ Flutter App

Topics handled:
    shelter/node/{W,X,Y,Z}/telemetry  - Sensor data
    shelter/node/{W,X,Y,Z}/routing    - Routing decisions
    shelter/node/{W,X,Y,Z}/alert      - Alerts
    shelter/mesh/neighbor             - Inter-node beacons
    shelter/broadcast/config          - Config updates to nodes
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
MQTT_CLIENT_ID = "shelter-gateway"

# MQTT Topics
TOPIC_TELEMETRY_PREFIX = "shelter/node/"
TOPIC_ROUTING_PREFIX = "shelter/node/"
TOPIC_ALERT_PREFIX = "shelter/node/"
TOPIC_MESH_NEIGHBOR = "shelter/mesh/neighbor"
TOPIC_MESH_FORWARD = "shelter/mesh/forward"
TOPIC_BROADCAST_CONFIG = "shelter/broadcast/config"

# Node IDs
NODE_IDS = ['W', 'X', 'Y', 'Z']

# Logging setup
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler('/var/log/shelter-gateway.log', mode='a')
    ]
)
logger = logging.getLogger(__name__)

# ============================================================================
# Gateway Class
# ============================================================================

class ShelterMonitoringGateway:
    def __init__(self):
        self.mqtt_client = None
        self.db = None
        self.stop_event = Event()
        self.node_status = {}  # Track last update time per node
        
        # Initialize Firebase
        self._init_firebase()
        
        # Initialize MQTT
        self._init_mqtt()
        
        # Initialize node tracking
        for node_id in NODE_IDS:
            self.node_status[node_id] = {
                'last_seen': None,
                'online': False,
                'battery': 100,
                'plate_status': 'unknown',
                'cat_present': False
            }
    
    def _init_firebase(self):
        """Initialize Firebase Admin SDK"""
        try:
            cred_path = os.getenv(
                "GOOGLE_APPLICATION_CREDENTIALS",
                "/opt/smart-cat-feeder/firebase-credentials.json"
            )
            
            if not os.path.exists(cred_path):
                logger.error(f"Firebase credentials not found at: {cred_path}")
                logger.warning("Running in OFFLINE mode - data will not sync to cloud")
                self.db = None
                return
            
            cred = credentials.Certificate(cred_path)
            firebase_admin.initialize_app(cred)
            self.db = firestore.client()
            logger.info("✅ Firebase initialized successfully")
            
            # Start listening for calibration updates
            self._start_calibration_listeners()
            
        except Exception as e:
            logger.error(f"❌ Firebase initialization failed: {e}")
            self.db = None
    
    def _init_mqtt(self):
        """Initialize MQTT client"""
        try:
            self.mqtt_client = mqtt.Client(client_id=MQTT_CLIENT_ID)
            self.mqtt_client.on_connect = self._on_mqtt_connect
            self.mqtt_client.on_disconnect = self._on_mqtt_disconnect
            self.mqtt_client.on_message = self._on_mqtt_message
            
            self.mqtt_client.connect(MQTT_BROKER, MQTT_PORT, keepalive=60)
            logger.info(f"✅ MQTT connected to {MQTT_BROKER}:{MQTT_PORT}")
            
        except Exception as e:
            logger.error(f"❌ MQTT connection failed: {e}")
            sys.exit(1)
    
    def _on_mqtt_connect(self, client, userdata, flags, rc):
        """MQTT connection callback"""
        if rc == 0:
            logger.info("✅ MQTT broker connected")
            
            # Subscribe to all node topics
            for node_id in NODE_IDS:
                client.subscribe(f"shelter/node/{node_id}/telemetry")
                client.subscribe(f"shelter/node/{node_id}/routing")
                client.subscribe(f"shelter/node/{node_id}/alert")
            
            # Subscribe to mesh topics
            client.subscribe(TOPIC_MESH_NEIGHBOR)
            client.subscribe(TOPIC_MESH_FORWARD)
            
            logger.info(f"📡 Subscribed to topics for nodes: {NODE_IDS}")
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
        """Handle incoming MQTT messages"""
        topic = msg.topic
        try:
            payload = json.loads(msg.payload.decode())
        except (json.JSONDecodeError, UnicodeDecodeError) as e:
            # Binary ESP-NOW data or malformed JSON - skip
            logger.debug(f"Skipping non-JSON message on {topic}: {e}")
            return
        
        logger.debug(f"📨 MQTT [{topic}]: {json.dumps(payload)[:200]}")
        
        # Route to appropriate handler based on topic
        if "/telemetry" in topic:
            self._handle_telemetry(payload)
        elif "/routing" in topic:
            self._handle_routing(payload)
        elif "/alert" in topic:
            self._handle_alert(payload)
        elif topic == TOPIC_MESH_NEIGHBOR:
            self._handle_neighbor_beacon(payload)
    
    # ========================================================================
    # MESSAGE HANDLERS
    # ========================================================================
    
    def _handle_telemetry(self, payload):
        """Handle sensor telemetry from a node (supports both full and compact formats)"""
        
        # Check if this is compact format (forwarded via ESP-NOW)
        # Compact format uses short keys: n, u, d, c, r, p, b, s, h, rt
        if 'n' in payload and 'nodeId' not in payload:
            # Expand compact format to full format
            plate_map = {'e': 'empty', 'f': 'filled', 'u': 'unknown'}
            
            # Get route from compact format, append SINK
            route = payload.get('rt', [payload.get('n', '?')])
            if isinstance(route, list):
                route = route + ['SINK']
            else:
                route = [payload.get('n', '?'), 'SINK']
            
            # Determine nextHop from route
            if len(route) > 2:
                next_hop = '->'.join(route[1:-1])  # Show relay nodes
            else:
                next_hop = 'direct'
            
            payload = {
                'nodeId': payload.get('n', '?'),
                'userId': payload.get('u', 'EyrwFFoBJ8TlVFepJvqdeooOBwA2'),
                'sensors': {
                    'ultrasonic': {
                        'distanceCm': payload.get('d', 0),
                        'catPresent': payload.get('c', 0) == 1
                    },
                    'color': {
                        'red': payload.get('r', 0),
                        'green': 0,
                        'blue': 0,
                        'plateStatus': plate_map.get(payload.get('p', 'u'), 'unknown'),
                        'isBrown': payload.get('p') == 'f'
                    }
                },
                'battery': {
                    'percentage': payload.get('b', 0),
                    'voltage': 0
                },
                'network': {
                    'rssi': payload.get('s', -100),
                    'hopCount': payload.get('h', 1),
                    'route': route,
                    'nextHop': next_hop
                }
            }
            logger.info(f"📡 Expanded compact telemetry from Node {payload['nodeId']}, route: {route}")
        
        node_id = payload.get("nodeId", "?")
        user_id = payload.get("userId", "EyrwFFoBJ8TlVFepJvqdeooOBwA2")  # Default user ID
        timestamp = payload.get("timestamp", 0)
        
        logger.info(f"📊 Telemetry from Node {node_id} (userId: {user_id})")
        
        # Extract sensor data
        sensors = payload.get("sensors", {})
        ultrasonic = sensors.get("ultrasonic", {})
        color = sensors.get("color", {})
        battery = payload.get("battery", {})
        network = payload.get("network", {})
        
        # Check if this is the first telemetry from this node
        was_offline = not self.node_status.get(node_id, {}).get('online', False)
        
        # Update local tracking
        self.node_status[node_id] = {
            'last_seen': datetime.now(),
            'online': True,
            'battery': battery.get('percentage', 0),
            'plate_status': color.get('plateStatus', 'unknown'),
            'cat_present': ultrasonic.get('catPresent', False)
        }
        
        # If node just came online, send calibration
        if was_offline:
            logger.info(f"✅ Node {node_id} came online, sending calibration...")
            self._send_calibration_to_node(node_id)
        
        # Log details
        logger.info(f"   Ultrasonic: {ultrasonic.get('distanceCm', '?')}cm, Cat: {ultrasonic.get('catPresent', '?')}")
        logger.info(f"   Color: RGB({color.get('red', '?')},{color.get('green', '?')},{color.get('blue', '?')}), Plate: {color.get('plateStatus', '?')}")
        logger.info(f"   Battery: {battery.get('percentage', '?')}%, Route: {network.get('route', [])}")
        
        # Update Firestore
        if self.db and user_id:
            try:
                node_ref = self.db.collection("users").document(user_id).collection("nodes").document(node_id)
                node_ref.set({
                    'nodeId': node_id,
                    'displayName': f'Bowl {node_id}',
                    'plateStatus': color.get('plateStatus', 'unknown'),
                    'catPresent': ultrasonic.get('catPresent', False),
                    'batteryPercent': battery.get('percentage', 0),
                    'batteryVoltage': battery.get('voltage', 0),
                    'rssi': network.get('rssi', -100),
                    'hopCount': network.get('hopCount', 1),
                    'route': network.get('route', []),
                    'nextHop': network.get('nextHop', 'SINK'),
                    'lastUpdate': firestore.SERVER_TIMESTAMP,
                    'isOnline': True,
                    'lastColorReading': {
                        'red': color.get('red', 0),
                        'green': color.get('green', 0),
                        'blue': color.get('blue', 0),
                        'isBrown': color.get('isBrown', False)
                    },
                    'ultrasonicDistanceCm': ultrasonic.get('distanceCm', 0)
                }, merge=True)
                
                logger.info(f"✅ Node {node_id} status updated in Firestore for user {user_id}")
                
            except Exception as e:
                logger.error(f"❌ Firestore update failed: {e}")
    
    def _handle_routing(self, payload):
        """Handle routing decision updates from a node"""
        node_id = payload.get("nodeId", "?")
        user_id = payload.get("userId", "EyrwFFoBJ8TlVFepJvqdeooOBwA2")
        
        decision = payload.get("routingDecision", {})
        prev_hop = decision.get("previousNextHop", "?")
        new_hop = decision.get("newNextHop", "?")
        reason = decision.get("reason", "")
        candidates = decision.get("candidates", [])
        
        logger.info(f"🔀 Routing update from Node {node_id}: {prev_hop} → {new_hop}")
        logger.info(f"   Reason: {reason}")
        logger.info(f"   Candidates: {candidates}")
        
        # Log to Firestore for demo proof
        if self.db and user_id:
            try:
                log_ref = self.db.collection("users").document(user_id).collection("routing_logs")
                log_ref.add({
                    'nodeId': node_id,
                    'timestamp': firestore.SERVER_TIMESTAMP,
                    'previousNextHop': prev_hop,
                    'newNextHop': new_hop,
                    'reason': reason,
                    'candidates': candidates,
                    'selectedScore': decision.get('selectedScore', 0)
                })
                logger.debug(f"✅ Routing decision logged for Node {node_id}")
                
            except Exception as e:
                logger.error(f"❌ Routing log failed: {e}")
    
    def _handle_alert(self, payload):
        """Handle alerts from nodes"""
        alert_id = payload.get("alertId", f"alert_{time.time()}")
        node_id = payload.get("nodeId", "?")
        alert_type = payload.get("type", "unknown")
        user_id = payload.get("userId")
        message = payload.get("message", "")
        details = payload.get("details", {})
        severity = payload.get("severity", "warning")
        
        logger.warning(f"🚨 ALERT from Node {node_id}: {alert_type}")
        logger.warning(f"   Message: {message}")
        logger.warning(f"   Details: {details}")
        
        # Store in Firestore
        if self.db and user_id:
            try:
                alert_ref = self.db.collection("users").document(user_id).collection("alerts").document(alert_id)
                alert_ref.set({
                    'alertId': alert_id,
                    'nodeId': node_id,
                    'type': alert_type,
                    'severity': severity,
                    'timestamp': firestore.SERVER_TIMESTAMP,
                    'message': message,
                    'details': details,
                    'acknowledged': False
                })
                logger.info(f"✅ Alert {alert_id} stored in Firestore")
                
            except Exception as e:
                logger.error(f"❌ Alert storage failed: {e}")
        
        # Send push notification for warnings
        if severity in ['warning', 'critical'] and user_id:
            self._send_alert_notification(user_id, alert_type, node_id, message)
    
    def _handle_neighbor_beacon(self, payload):
        """Handle inter-node neighbor beacons (for mesh awareness)"""
        node_id = payload.get("nodeId", "?")
        battery = payload.get("battery", 0)
        rssi = payload.get("rssi", -100)
        
        logger.debug(f"📡 Neighbor beacon: Node {node_id}, Battery {battery}%, RSSI {rssi}")
    
    def _send_calibration_to_node(self, node_id):
        """Send stored calibration to a node (called when node comes online)"""
        if not self.db:
            return
        
        try:
            calibration_ref = (
                self.db.collection('shelter')
                .document('nodes')
                .collection(node_id)
                .document('calibration')
            )
            
            calibration_doc = calibration_ref.get()
            if calibration_doc.exists:
                calibration_data = calibration_doc.to_dict()
                self._forward_calibration_to_mqtt(node_id, calibration_data)
                logger.info(f"📤 Sent stored calibration to newly connected node {node_id}")
        except Exception as e:
            logger.error(f"❌ Failed to send calibration to {node_id}: {e}")
    
    def _start_calibration_listeners(self):
        """Start Firebase listeners for calibration updates"""
        if not self.db:
            return
        
        logger.info("📡 Setting up calibration listeners for all nodes")
        
        for node_id in NODE_IDS:
            try:
                # Watch: shelter/nodes/{nodeId}/calibration
                calibration_ref = (
                    self.db.collection('shelter')
                    .document('nodes')
                    .collection(node_id)
                    .document('calibration')
                )
                
                # Create callback for this specific node
                def make_callback(node_id):
                    def on_snapshot(doc_snapshot, changes, read_time):
                        for doc in doc_snapshot:
                            if doc.exists:
                                self._forward_calibration_to_mqtt(node_id, doc.to_dict())
                    return on_snapshot
                
                # Watch for changes
                calibration_ref.on_snapshot(make_callback(node_id))
                logger.info(f"✅ Calibration listener active for node {node_id}")
                
            except Exception as e:
                logger.error(f"❌ Failed to setup calibration listener for {node_id}: {e}")
    
    def _forward_calibration_to_mqtt(self, node_id, calibration_data):
        """Forward calibration from Firebase to MQTT"""
        try:
            # Remove timestamp if present (not needed for ESP8266)
            if 'timestamp' in calibration_data:
                del calibration_data['timestamp']
            
            topic = f"shelter/node/{node_id}/config/calibration"
            payload = json.dumps(calibration_data)
            
            self.mqtt_client.publish(topic, payload, qos=1)
            logger.info(f"📤 Forwarded calibration to {node_id}: {calibration_data.get('colorName', 'unknown')}")
            
        except Exception as e:
            logger.error(f"❌ Failed to forward calibration to {node_id}: {e}")
    
    # ========================================================================
    # NOTIFICATIONS
    # ========================================================================
    
    def _send_alert_notification(self, user_id, alert_type, node_id, message):
        """Send FCM push notification for an alert"""
        try:
            # Get user's FCM tokens
            tokens_ref = self.db.collection("users").document(user_id).collection("fcm_tokens")
            tokens = [doc.id for doc in tokens_ref.stream()]
            
            if not tokens:
                logger.info(f"No FCM tokens for user {user_id}")
                return
            
            # Build notification
            title_map = {
                'empty_plate': f'🍽️ Empty Plate at Bowl {node_id}',
                'low_battery': f'🔋 Low Battery on Node {node_id}',
                'node_offline': f'📡 Node {node_id} Offline',
                'cat_present': f'🐱 Cat at Bowl {node_id}'
            }
            title = title_map.get(alert_type, f'Alert from Node {node_id}')
            
            fcm_message = messaging.MulticastMessage(
                notification=messaging.Notification(title=title, body=message),
                data={
                    'type': alert_type,
                    'nodeId': node_id,
                    'click_action': 'FLUTTER_NOTIFICATION_CLICK'
                },
                tokens=tokens
            )
            
            response = messaging.send_each_for_multicast(fcm_message)
            logger.info(f"📱 Notification sent: {response.success_count} success, {response.failure_count} failed")
            
            # Clean up invalid tokens
            for idx, resp in enumerate(response.responses):
                if not resp.success:
                    error_code = getattr(resp.exception, 'code', None)
                    if error_code in ['messaging/invalid-registration-token',
                                      'messaging/registration-token-not-registered']:
                        tokens_ref.document(tokens[idx]).delete()
                        logger.info(f"Removed invalid token")
            
        except Exception as e:
            logger.error(f"❌ Notification error: {e}")
    
    # ========================================================================
    # NODE MONITORING
    # ========================================================================
    
    def _monitor_node_status(self):
        """Background thread to monitor node connectivity"""
        while not self.stop_event.is_set():
            try:
                now = datetime.now()
                
                for node_id, status in self.node_status.items():
                    last_seen = status.get('last_seen')
                    if last_seen:
                        delta = (now - last_seen).total_seconds()
                        
                        # Mark as offline if no update in 2 minutes
                        if delta > 120 and status['online']:
                            logger.warning(f"⚠️ Node {node_id} appears offline (last seen {delta:.0f}s ago)")
                            status['online'] = False
                            
                            # Update Firestore with timestamp to trigger listeners
                            if self.db:
                                user_id = "EyrwFFoBJ8TlVFepJvqdeooOBwA2"
                                try:
                                    node_ref = self.db.collection("users").document(user_id).collection("nodes").document(node_id)
                                    node_ref.update({
                                        'isOnline': False,
                                        'lastUpdate': firestore.SERVER_TIMESTAMP
                                    })
                                    logger.info(f"✅ Marked node {node_id} as offline in Firestore")
                                except Exception as e:
                                    logger.error(f"❌ Failed to mark node {node_id} offline: {e}")
                
                time.sleep(30)  # Check every 30 seconds
                
            except Exception as e:
                logger.error(f"Node monitor error: {e}")
                time.sleep(10)
    
    # ========================================================================
    # MAIN RUN LOOP
    # ========================================================================
    
    def run(self):
        """Main run loop"""
        logger.info("🚀 Shelter Monitoring Gateway starting...")
        logger.info(f"   Monitoring nodes: {NODE_IDS}")
        
        # Start node monitoring thread
        monitor_thread = Thread(target=self._monitor_node_status, daemon=True)
        monitor_thread.start()
        
        # Start MQTT loop
        self.mqtt_client.loop_start()
        
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
    gateway = ShelterMonitoringGateway()
    
    def signal_handler(sig, frame):
        gateway.stop()
        sys.exit(0)
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    gateway.run()


if __name__ == "__main__":
    main()
