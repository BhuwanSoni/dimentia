from database.firebase_config import get_firestore_client
from google.cloud import firestore
from datetime import datetime, timedelta
from dateutil import parser
from apscheduler.schedulers.background import BackgroundScheduler
import pytz
import uuid


# ==========================================================
# Scheduler Initialization
# ==========================================================

scheduler = BackgroundScheduler()
scheduler.start()


# ==========================================================
# Utility: Parse Time
# ==========================================================



def parse_time_to_utc(time_text, user_timezone="Asia/Kolkata"):
    """
    Convert time_text (datetime or ISO string) to UTC.
    - If already timezone-aware → convert directly to UTC (no double-localize)
    - If naive → localize to user_timezone first, then convert to UTC
    Default timezone is Asia/Kolkata (IST) since Render servers run UTC
    and we always want to treat user input as IST unless told otherwise.
    """
    local = pytz.timezone(user_timezone)

    if isinstance(time_text, datetime):
        if time_text.tzinfo is not None:
            # ✅ Already aware (e.g. IST-aware from parse_natural_reminder)
            return time_text.astimezone(pytz.utc)
        # Naive datetime → localize to IST then convert
        localized_time = local.localize(time_text)
        return localized_time.astimezone(pytz.utc)

    parsed_time = parser.parse(time_text)

    if parsed_time.tzinfo is None:
        localized_time = local.localize(parsed_time)
    else:
        localized_time = parsed_time

    return localized_time.astimezone(pytz.utc)


# ==========================================================
# Create Reminder
# ==========================================================

def create_reminder(
    user_id,
    task,
    time_text,
    source="assistant",
    recurring_type="none",
    user_timezone="Asia/Kolkata",  # ✅ FIX: was "UTC" — caused time-shifted ghost reminders
    time_display=None       # ✅ human-readable string for display (e.g. "8pm") — optional
):

    db = get_firestore_client()
    reminder_id = str(uuid.uuid4())

    scheduled_time = parse_time_to_utc(time_text, user_timezone)

    # ✅ DEBUG: log the resolved time so you can verify IST→UTC conversion is correct
    print("REMINDER TIME:", scheduled_time)
    print("USER TIMEZONE:", user_timezone)

    # time_text stored in Firestore should be a readable string, not a datetime object.
    # Use time_display if provided, otherwise fall back to isoformat of scheduled_time.
    firestore_time_text = time_display if time_display else scheduled_time.strftime("%I:%M %p")

    db.collection("users") \
        .document(user_id) \
        .collection("reminders") \
        .document(reminder_id) \
        .set({
    "task": task,
    "title": task,  # ✅ ADD THIS LINE (IMPORTANT)
    "scheduled_time": scheduled_time,
    "time": scheduled_time,  # ✅ ADD THIS LINE (VERY IMPORTANT)
    "time_text": firestore_time_text,
    "timezone": user_timezone,
    "recurring_type": recurring_type,
    "completed": False,
    "source": source,
    "created_at": firestore.SERVER_TIMESTAMP,
    "last_modified": firestore.SERVER_TIMESTAMP
})

    # ✅ FIX: Commented out — Flutter already schedules local notifications via
    # the Firestore stream in ReminderPage. Running APScheduler here too causes
    # duplicate / ghost notifications on every reminder.
    # schedule_job(user_id, reminder_id, scheduled_time, recurring_type)

    return reminder_id


# ==========================================================
# Scheduler Logic
# ==========================================================

def schedule_job(user_id, reminder_id, scheduled_time, recurring_type):

    if recurring_type == "daily":
        scheduler.add_job(
            trigger_reminder,
            'interval',
            days=1,
            args=[user_id, reminder_id],
            next_run_time=scheduled_time
        )

    elif recurring_type == "weekly":
        scheduler.add_job(
            trigger_reminder,
            'interval',
            weeks=1,
            args=[user_id, reminder_id],
            next_run_time=scheduled_time
        )

    else:
        scheduler.add_job(
            trigger_reminder,
            'date',
            run_date=scheduled_time,
            args=[user_id, reminder_id]
        )


def trigger_reminder(user_id, reminder_id):
    print(f"⏰ Trigger reminder for user {user_id}, reminder {reminder_id}")
    # Here later you can:
    # - Send push notification
    # - Send websocket event
    # - Send mobile notification
    # - Send assistant auto-message


# ==========================================================
# Get Reminders
# ==========================================================

def get_user_reminders(user_id, include_completed=False):
    db = get_firestore_client()

    query = db.collection("users") \
        .document(user_id) \
        .collection("reminders")

    if not include_completed:
        query = query.where("completed", "==", False)

    docs = query.stream()

    reminders = []

    for doc in docs:
        data = doc.to_dict()
        data["id"] = doc.id
        reminders.append(data)

    return reminders


# ==========================================================
# Get Next Reminder
# ==========================================================

def get_next_reminder(user_id):
    db = get_firestore_client()

    now = datetime.now(pytz.utc)  # ✅ aware — matches UTC-aware scheduled_time for comparison

    docs = db.collection("users") \
        .document(user_id) \
        .collection("reminders") \
        .where("completed", "==", False) \
        .stream()

    upcoming = []

    for doc in docs:
        data = doc.to_dict()
        if data.get("scheduled_time") and data["scheduled_time"] > now:
            data["id"] = doc.id
            upcoming.append(data)

    if not upcoming:
        return None

    upcoming.sort(key=lambda x: x["scheduled_time"])
    return upcoming[0]


# ==========================================================
# Complete Reminder
# ==========================================================

def complete_reminder(user_id, reminder_id):
    db = get_firestore_client()

    db.collection("users") \
        .document(user_id) \
        .collection("reminders") \
        .document(reminder_id) \
        .update({
            "completed": True,
            "completed_at": firestore.SERVER_TIMESTAMP,  # ✅ lets Flutter stream detect exact completion time
            "last_modified": firestore.SERVER_TIMESTAMP
        })

    return True


def set_double_confirm_state(user_id, reminder_id):
    db = get_firestore_client()
    db.collection("users").document(user_id).set({
        "double_confirm_reminder": reminder_id
    }, merge=True)


def get_double_confirm_state(user_id):
    db = get_firestore_client()
    doc = db.collection("users").document(user_id).get()
    if doc.exists:
        return doc.to_dict().get("double_confirm_reminder")
    return None


def clear_double_confirm_state(user_id):
    db = get_firestore_client()
    db.collection("users").document(user_id).update({
        "double_confirm_reminder": firestore.DELETE_FIELD
    })


# ==========================================================
# Delete Reminder
# ==========================================================

def delete_reminder(user_id, reminder_id):
    db = get_firestore_client()

    db.collection("users") \
        .document(user_id) \
        .collection("reminders") \
        .document(reminder_id) \
        .delete()

    return True


# ==========================================================
# Delete By Task
# ==========================================================

def delete_reminder_by_task(user_id, task_text):
    db = get_firestore_client()

    docs = db.collection("users") \
        .document(user_id) \
        .collection("reminders") \
        .where("completed", "==", False) \
        .stream()

    for doc in docs:
        data = doc.to_dict()
        if task_text.lower() in data.get("task", "").lower():
            doc.reference.delete()
            return True

    return False


# ==========================================================
# Delete Last Reminder
# ==========================================================

def delete_last_reminder(user_id):
    db = get_firestore_client()

    docs = db.collection("users") \
        .document(user_id) \
        .collection("reminders") \
        .order_by("created_at", direction=firestore.Query.DESCENDING) \
        .limit(1) \
        .stream()

    for doc in docs:
        doc.reference.delete()
        return True

    return False


# ==========================================================
# Clear All Reminders
# ==========================================================

def clear_all_reminders(user_id):
    db = get_firestore_client()

    docs = db.collection("users") \
        .document(user_id) \
        .collection("reminders") \
        .stream()

    for doc in docs:
        doc.reference.delete()

    return True