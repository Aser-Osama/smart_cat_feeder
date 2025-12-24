#!/usr/bin/env python3
import os
import json
import time
import logging
import threading
import paho.mqtt.client as mqtt

import firebase_admin
from firebase_admin import credentials, firestore

# Cat detection auto-reset timer
cat_detection_timer = None
CAT_DETECTION_RESET_SECONDS = 30  # Reset catDetected to false after 30 seconds


# =============================================================================
# Config (edit only if your topics/paths differ)
# =============================================================================

# If your ESP uses a specific uid in payloads, set this.
# Otherwise export SCF_USER_ID in systemd Environment=... or keep empty and
# we will try to infer from payload["userId"] or payload["uid"].
USER_ID = os.getenv("SCF_USER_ID", "").strip()

# MQTT
MQTT_HOST = os.getenv("SCF_MQTT_HOST", "127.0.0.1").strip()
MQTT_PORT = int(os.getenv("SCF_MQTT_PORT", "1883"))

# Firestore paths (unified schema)
# Commands:     users/{uid}/commands      (documents created by app/cloud functions)
# Status:       users/{uid}/feeder/status (single doc for current feeder state)
# Status Logs:  users/{uid}/status_logs   (history of status updates)
# Feeding Logs: users/{uid}/feeding_logs  (history of feedings)
FIRESTORE_USERS_COLLECTION = "users"
FIRESTORE_COMMANDS_SUBCOL = "commands"
FIRESTORE_STATUS_LOGS_SUBCOL = "status_logs"
FIRESTORE_FEEDING_LOGS_SUBCOL = "feeding_logs"

# MQTT topics (matches MD reference table)
TOPIC_COMMAND_DISPENSE = "feeder/control/dispense"
TOPIC_STATUS_PREFIX = "feeder/status/"


# =============================================================================
# Logging
# =============================================================================

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
log = logging.getLogger("scf-gateway")


# =============================================================================
# Helpers
# =============================================================================

def get_uid_from_payload(payload: dict) -> str:
    """Try to get the Firebase UID from env or payload."""
    if USER_ID:
        return USER_ID
    for k in ("userId", "uid", "user_id"):
        v = payload.get(k)
        if isinstance(v, str) and v.strip():
            return v.strip()
    return ""


def safe_json_loads(b: bytes):
    try:
        return json.loads(b.decode("utf-8"))
    except Exception:
        return None


# =============================================================================
# Firebase init
# =============================================================================

def init_firestore():
    # Prefer GOOGLE_APPLICATION_CREDENTIALS from systemd
    cred_path = os.getenv("GOOGLE_APPLICATION_CREDENTIALS", "").strip()

    # If not set, fall back to the required file path in your project
    if not cred_path:
        cred_path = "/srv/smart-cat-feeder/gateway/firebase-credentials.json"

    if not os.path.exists(cred_path):
        raise FileNotFoundError(
            f"Firebase credentials not found at: {cred_path}\n"
            "Fix: place firebase-credentials.json and/or set "
            "GOOGLE_APPLICATION_CREDENTIALS in the service."
        )

    # Initialize once
    if not firebase_admin._apps:
        cred = credentials.Certificate(cred_path)
        firebase_admin.initialize_app(cred)
        log.info("✅ Firebase initialized using %s", cred_path)

    db = firestore.client()
    return db


# =============================================================================
# Firestore -> MQTT (listen to commands)
# =============================================================================

def start_firestore_listener(db, mqtt_client: mqtt.Client):
    """
    Listens on users/{uid}/commands for newly created docs and publishes them to MQTT.
    Updates command status after processing.
    """
    # We need a UID. If you didn't set env SCF_USER_ID, we still can't listen
    # because Firestore path needs uid.
    if not USER_ID:
        log.warning(
            "⚠️ SCF_USER_ID not set. Firestore listener needs a uid path.\n"
            "Set it in systemd: Environment=\"SCF_USER_ID=...\" \n"
            "Or hardcode USER_ID in this script."
        )
        return None

    # Only listen for pending commands
    commands_ref = (
        db.collection(FIRESTORE_USERS_COLLECTION)
          .document(USER_ID)
          .collection(FIRESTORE_COMMANDS_SUBCOL)
          .where("status", "==", "pending")
    )

    log.info("👂 Listening Firestore commands at users/%s/%s (status=pending)", USER_ID, FIRESTORE_COMMANDS_SUBCOL)

    def on_snapshot(col_snapshot, changes, read_time):
        for ch in changes:
            # Only publish newly created commands
            if ch.type.name != "ADDED":
                continue

            doc = ch.document
            data = doc.to_dict() or {}
            doc_id = doc.id
            
            # Skip if already processed (status check just in case)
            if data.get("status") != "pending":
                continue
            
            # Add document ID for tracking (ESP/gateway will use this)
            data["commandId"] = doc_id
            data["userId"] = USER_ID

            try:
                payload = json.dumps(data, separators=(",", ":"), default=str)
                mqtt_client.publish(TOPIC_COMMAND_DISPENSE, payload, qos=0)
                log.info("➡️ Firestore -> MQTT: %s %s", TOPIC_COMMAND_DISPENSE, payload)
                
                # Update command status to 'sent'
                doc.reference.update({
                    "status": "sent",
                    "sentAt": firestore.SERVER_TIMESTAMP,
                })
                log.info("📝 Command %s status updated to 'sent'", doc_id)
                
            except Exception as e:
                log.exception("Failed Firestore -> MQTT publish: %s", e)
                # Mark command as failed
                try:
                    doc.reference.update({
                        "status": "failed",
                        "error": str(e),
                        "failedAt": firestore.SERVER_TIMESTAMP,
                    })
                except Exception:
                    pass

    # Keep reference alive
    watch = commands_ref.on_snapshot(on_snapshot)
    return watch


# =============================================================================
# MQTT -> Firestore (ESP status)
# =============================================================================

def on_connect(client, userdata, flags, reason_code, properties=None):
    log.info("✅ MQTT connected: reason_code=%s", reason_code)
    client.subscribe("#")  # keep your logger behavior


def on_message(client, userdata, msg):
    topic = msg.topic
    raw = msg.payload
    text = raw.decode(errors="replace")

    # Keep your current behavior
    log.info("MQTT: %s %s", topic, text)

    # Only forward ESP status topics to Firestore
    if not topic.startswith(TOPIC_STATUS_PREFIX):
        return

    db: firestore.Client = userdata["db"]

    payload_obj = safe_json_loads(raw)
    if payload_obj is None:
        # store raw text if not JSON
        payload_obj = {"raw": text}

    uid = get_uid_from_payload(payload_obj)
    if not uid:
        # If your ESP publishes no uid/userId, you MUST set SCF_USER_ID.
        log.warning(
            "⚠️ No userId/uid in payload and SCF_USER_ID not set. "
            "Skipping Firestore write."
        )
        return

    # Determine what kind of status update this is
    status_type = topic.replace(TOPIC_STATUS_PREFIX, "")  # e.g., "cat_detected", "fed", "heartbeat"
    
    try:
        # Update the feeder/status document (what Flutter app expects)
        feeder_status_ref = (
            db.collection(FIRESTORE_USERS_COLLECTION)
              .document(uid)
              .collection("feeder")
              .document("status")
        )
        
        # Build update based on status type
        update_data = {
            "lastUpdated": firestore.SERVER_TIMESTAMP,
        }
        
        if status_type == "cat_detected":
            global cat_detection_timer
            detected = payload_obj.get("detected", True)
            update_data["catDetected"] = detected
            if detected:
                update_data["lastCatDetection"] = firestore.SERVER_TIMESTAMP
                
                # Cancel any existing reset timer
                if cat_detection_timer is not None:
                    cat_detection_timer.cancel()
                
                # Schedule auto-reset of catDetected to false
                # This ensures the Cloud Function can trigger again on next detection
                # We pass db and uid explicitly to avoid closure issues
                def reset_cat_detection(db_ref, user_id):
                    try:
                        log.info("⏰ Auto-resetting catDetected to false for user %s", user_id)
                        reset_ref = (
                            db_ref.collection(FIRESTORE_USERS_COLLECTION)
                                  .document(user_id)
                                  .collection("feeder")
                                  .document("status")
                        )
                        reset_ref.set({
                            "catDetected": False,
                            "lastUpdated": firestore.SERVER_TIMESTAMP,
                        }, merge=True)
                        log.info("✅ catDetected reset to false - next detection will trigger notification")
                    except Exception as e:
                        log.warning("⚠️ Failed to reset catDetected: %s", e)
                
                cat_detection_timer = threading.Timer(
                    CAT_DETECTION_RESET_SECONDS, 
                    reset_cat_detection,
                    args=[db, uid]  # Pass db and uid explicitly
                )
                cat_detection_timer.daemon = True
                cat_detection_timer.start()
                log.info("⏱️ Cat detection will auto-reset in %ds", CAT_DETECTION_RESET_SECONDS)
                
            log.info("🐱 Cat detection: %s", detected)
            
        elif status_type == "fed":
            amount = float(payload_obj.get("amount", 50.0))
            success = payload_obj.get("success", True)
            command_id = payload_obj.get("commandId")
            
            update_data["lastFed"] = firestore.SERVER_TIMESTAMP
            
            # Decrease food level
            current_doc = feeder_status_ref.get()
            if current_doc.exists:
                current_level = current_doc.to_dict().get("foodLevel", 100)
                update_data["foodLevel"] = max(0, current_level - 5)
            
            log.info("🍽️ Feeding complete: %sg, success=%s", amount, success)
            
            # Create feeding log entry (unified schema)
            feeding_log_ref = (
                db.collection(FIRESTORE_USERS_COLLECTION)
                  .document(uid)
                  .collection(FIRESTORE_FEEDING_LOGS_SUBCOL)
            )
            feeding_log_ref.add({
                "timestamp": firestore.SERVER_TIMESTAMP,
                "amount": amount,
                "type": payload_obj.get("type", "manual"),
                "success": success,
                "scheduleName": payload_obj.get("scheduleName"),
                "scheduleId": payload_obj.get("scheduleId"),
                "notes": f"Fed via IoT gateway",
                "source": "iot",
            })
            log.info("📝 Feeding log created for user %s", uid)
            
            # Update command status to 'completed' if we have a commandId
            if command_id:
                try:
                    command_ref = (
                        db.collection(FIRESTORE_USERS_COLLECTION)
                          .document(uid)
                          .collection(FIRESTORE_COMMANDS_SUBCOL)
                          .document(command_id)
                    )
                    command_ref.update({
                        "status": "completed",
                        "completedAt": firestore.SERVER_TIMESTAMP,
                        "result": {"success": success, "amount": amount},
                    })
                    log.info("✅ Command %s marked as completed", command_id)
                except Exception as e:
                    log.warning("⚠️ Could not update command status: %s", e)
            
        elif status_type == "heartbeat":
            # Just update lastUpdated (already in update_data)
            update_data["iotConnected"] = True
            log.info("💓 Heartbeat received")
        
        # Merge update into existing document (create if doesn't exist)
        feeder_status_ref.set(update_data, merge=True)
        log.info("⬅️ MQTT -> Firestore: users/%s/feeder/status updated", uid)
        
        # Also log to status_logs collection for history
        status_log_ref = (
            db.collection(FIRESTORE_USERS_COLLECTION)
              .document(uid)
              .collection(FIRESTORE_STATUS_LOGS_SUBCOL)
        )
        status_log_ref.add({
            "topic": topic,
            "statusType": status_type,
            "data": payload_obj,
            "createdAt": firestore.SERVER_TIMESTAMP,
        })
        
    except Exception as e:
        log.exception("Failed MQTT -> Firestore write: %s", e)


# =============================================================================
# Main
# =============================================================================

def main():
    db = init_firestore()

    c = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    c.user_data_set({"db": db})
    c.on_connect = on_connect
    c.on_message = on_message

    log.info("Connecting to MQTT broker %s:%s ...", MQTT_HOST, MQTT_PORT)
    c.connect(MQTT_HOST, MQTT_PORT)

    # Start Firestore listener (only works if USER_ID is set)
    watch = start_firestore_listener(db, c)

    # Run MQTT loop forever
    log.info("🚀 Gateway running (MQTT logger + Firebase bridge)")
    c.loop_forever()


if __name__ == "__main__":
    main()

