"""
services/fcm_service.py

FCM push notification sender for the Memoir backend.
Called by reminder_service.py when a reminder is missed (or missed 3+ times).

Requirements (already in requirements.txt via firebase-admin):
  firebase-admin >= 6.0.0   ← includes firebase_admin.messaging
No new pip package needed.

Usage:
  from services.fcm_service import send_fcm_to_user, check_escalation
"""

import firebase_admin
from firebase_admin import messaging
from database.firebase_config import get_firestore_client


# ==========================================================
# Send FCM to a single user
# ==========================================================

def send_fcm_to_user(
    user_id:    str,
    title:      str,
    body:       str,
    alert_type: str = "task",   # 'medicine' | 'emergency' | 'missed' | 'task'
) -> bool:
    """
    Look up the user's FCM token from Firestore and send a push notification.

    alert_type maps to:
      'emergency' → emergency_channel  (high-priority vibration)
      anything else → reminder_channel

    Returns True if the message was accepted by FCM, False otherwise.
    """
    db = get_firestore_client()

    try:
        user_doc = db.collection("users").document(user_id).get()
    except Exception as e:
        print(f"⚠️ FCM: Firestore lookup failed for {user_id}: {e}")
        return False

    if not user_doc.exists:
        print(f"⚠️ FCM: user {user_id} not found in Firestore")
        return False

    token = user_doc.to_dict().get("fcm_token")
    if not token:
        print(f"⚠️ FCM: no fcm_token saved for user {user_id}")
        return False

    channel_id = "emergency_channel" if alert_type == "emergency" else "reminder_channel"

    message = messaging.Message(
        notification=messaging.Notification(title=title, body=body),
        data={"alert_type": alert_type},
        android=messaging.AndroidConfig(
            priority="high",
            notification=messaging.AndroidNotification(
                channel_id=channel_id,
                sound="default",
            ),
        ),
        token=token,
    )

    try:
        response = messaging.send(message)
        print(f"✅ FCM sent to {user_id}: {response}")
        return True
    except messaging.UnregisteredError:
        # Token is stale — clear it so we don't keep trying
        print(f"⚠️ FCM: token for {user_id} is unregistered — clearing from Firestore")
        try:
            db.collection("users").document(user_id).update({"fcm_token": None})
        except Exception:
            pass
        return False
    except Exception as e:
        print(f"❌ FCM send failed for {user_id}: {e}")
        return False


# ==========================================================
# Escalation — called when the same reminder is missed 3+ times
# ==========================================================

def check_escalation(user_id: str, reminder_id: str) -> None:
    """
    Increment miss_count on the reminder.
    If miss_count reaches 3, fire an emergency-level FCM notification.

    Call this from mark_reminder_missed() in reminder_service.py
    (already wired — see the updated reminder_service.py).
    """
    from google.cloud import firestore as _fs   # local import to avoid circular

    db = get_firestore_client()
    ref = (
        db.collection("users")
          .document(user_id)
          .collection("reminders")
          .document(reminder_id)
    )

    try:
        doc = ref.get()
    except Exception as e:
        print(f"⚠️ check_escalation: Firestore fetch failed: {e}")
        return

    if not doc.exists:
        return

    data       = doc.to_dict()
    miss_count = data.get("miss_count", 0) + 1
    task       = data.get("task", "your task")

    try:
        ref.update({
            "miss_count":    miss_count,
            "last_modified": _fs.SERVER_TIMESTAMP,
        })
    except Exception as e:
        print(f"⚠️ check_escalation: miss_count update failed: {e}")

    if miss_count >= 3:
        print(f"🚨 Escalation: {reminder_id} missed {miss_count} times — sending emergency FCM")
        send_fcm_to_user(
            user_id=user_id,
            title="🚨 Urgent — Please Take Your Medicine",
            body=f'"{task}" has been missed {miss_count} times. Please act now.',
            alert_type="emergency",
        )
    else:
        print(f"📊 miss_count for {reminder_id} = {miss_count}")