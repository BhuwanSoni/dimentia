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
# ✅ VALID RECURRING TYPES
# ==========================================================

VALID_RECURRING_TYPES = {"none", "daily", "weekly", "monthly", "custom"}


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
            return time_text.astimezone(pytz.utc)
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
    recurring_type="none",          # ✅ none | daily | weekly | monthly | custom
    user_timezone="Asia/Kolkata",
    time_display=None,              # ✅ human-readable string (e.g. "8:00 AM") — optional
    custom_days=None,               # ✅ for recurring_type="custom": list of weekday ints (0=Mon … 6=Sun)
):
    """
    Create a reminder in Firestore.

    recurring_type values:
      "none"    — one-time reminder
      "daily"   — fires every day at the same time
      "weekly"  — fires every week on the same weekday
      "monthly" — fires every month on the same day-of-month
      "custom"  — fires on specific weekdays (pass custom_days=[0,2,4] for Mon/Wed/Fri)
    """
    db = get_firestore_client()
    reminder_id = str(uuid.uuid4())

    # ✅ Sanitise recurring_type so bad values from the frontend don't slip through
    if recurring_type not in VALID_RECURRING_TYPES:
        print(f"⚠️ Invalid recurring_type '{recurring_type}' — defaulting to 'none'")
        recurring_type = "none"

    scheduled_time = parse_time_to_utc(time_text, user_timezone)

    print("REMINDER TIME:", scheduled_time)
    print("USER TIMEZONE:", user_timezone)
    print("RECURRING TYPE:", recurring_type)

    firestore_time_text = time_display if time_display else scheduled_time.strftime("%I:%M %p")

    doc_data = {
        "task":           task,
        "title":          task,
        "scheduled_time": scheduled_time,
        "time":           scheduled_time,
        "time_text":      firestore_time_text,
        "timezone":       user_timezone,
        "recurring_type": recurring_type,       # ✅ stored for Flutter to display badge
        "completed":      False,
        "source":         source,
        "created_at":     firestore.SERVER_TIMESTAMP,
        "last_modified":  firestore.SERVER_TIMESTAMP,
        # ✅ NEW: missed-reminder tracking
        "missed":         False,
        "missed_at":      None,
        "snoozed_until":  None,
    }

    # ✅ Store custom weekday list for "custom" recurring type
    if recurring_type == "custom" and custom_days:
        doc_data["custom_days"] = custom_days

    db.collection("users") \
        .document(user_id) \
        .collection("reminders") \
        .document(reminder_id) \
        .set(doc_data)

    return reminder_id


# ==========================================================
# ✅ NEW: Snooze / Reschedule a Missed Reminder
# ==========================================================

def snooze_reminder(user_id, reminder_id, snooze_minutes=10):
    """
    Reschedule a reminder by snooze_minutes from now.
    Flutter calls this after the user taps "Remind me again in 10 min".
    """
    db = get_firestore_client()
    now_utc = datetime.now(pytz.utc)
    snooze_time = now_utc + timedelta(minutes=snooze_minutes)

    db.collection("users") \
        .document(user_id) \
        .collection("reminders") \
        .document(reminder_id) \
        .update({
            "scheduled_time": snooze_time,
            "time":           snooze_time,
            "completed":      False,
            "missed":         False,
            "snoozed_until":  snooze_time,
            "last_modified":  firestore.SERVER_TIMESTAMP,
        })
    return snooze_time


# ==========================================================
# ✅ NEW: Mark a Reminder as Missed
# ==========================================================

def mark_reminder_missed(user_id, reminder_id):
    """
    Mark a reminder as missed so Flutter can show the "You missed X" banner.
    Called by the backend scheduler or by Flutter after detecting a past-due reminder.
    """
    db = get_firestore_client()
    db.collection("users") \
        .document(user_id) \
        .collection("reminders") \
        .document(reminder_id) \
        .update({
            "missed":        True,
            "missed_at":     firestore.SERVER_TIMESTAMP,
            "last_modified": firestore.SERVER_TIMESTAMP,
        })
    return True


# ==========================================================
# ✅ NEW: Reschedule Recurring Reminder After Completion
#
# For daily/weekly/monthly reminders, after the user completes
# one occurrence we create the NEXT occurrence automatically so
# the reminder stays alive in the Firestore stream.
# ==========================================================

def advance_recurring_reminder(user_id, reminder_id):
    """
    After a recurring reminder fires/completes, push its scheduled_time
    forward by the correct interval and reset completed=False.
    Returns the new scheduled_time (UTC datetime) or None if not recurring.
    """
    db = get_firestore_client()
    ref = db.collection("users") \
            .document(user_id) \
            .collection("reminders") \
            .document(reminder_id)

    doc = ref.get()
    if not doc.exists:
        return None

    data = doc.to_dict()
    recurring_type = data.get("recurring_type", "none")
    if recurring_type == "none":
        return None

    raw_time = data.get("scheduled_time") or data.get("time")
    if raw_time is None:
        return None

    # Ensure aware datetime
    st = raw_time
    if hasattr(st, "tzinfo") and st.tzinfo is None:
        st = pytz.utc.localize(st)

    if recurring_type == "daily":
        next_time = st + timedelta(days=1)
    elif recurring_type == "weekly":
        next_time = st + timedelta(weeks=1)
    elif recurring_type == "monthly":
        # Same day next month (handles month-length edge cases)
        month = st.month + 1
        year  = st.year + (1 if month > 12 else 0)
        month = (month - 1) % 12 + 1
        import calendar
        max_day = calendar.monthrange(year, month)[1]
        day = min(st.day, max_day)
        next_time = st.replace(year=year, month=month, day=day)
    elif recurring_type == "custom":
        custom_days = data.get("custom_days", [])
        next_time = _next_custom_day(st, custom_days)
    else:
        return None

    ref.update({
        "scheduled_time": next_time,
        "time":           next_time,
        "completed":      False,
        "missed":         False,
        "last_modified":  firestore.SERVER_TIMESTAMP,
    })

    print(f"🔁 Recurring reminder advanced: {reminder_id} → {next_time}")
    return next_time


def _next_custom_day(current_time, weekday_list):
    """
    Given a UTC datetime and a list of weekday ints (0=Mon…6=Sun),
    return the next occurrence after current_time.
    """
    if not weekday_list:
        return current_time + timedelta(weeks=1)

    for days_ahead in range(1, 8):
        candidate = current_time + timedelta(days=days_ahead)
        if candidate.weekday() in weekday_list:
            return candidate

    return current_time + timedelta(weeks=1)


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
    elif recurring_type == "monthly":
        # APScheduler doesn't have a native "monthly" trigger —
        # use cron trigger with day-of-month
        scheduler.add_job(
            trigger_reminder,
            'cron',
            day=scheduled_time.day,
            hour=scheduled_time.hour,
            minute=scheduled_time.minute,
            args=[user_id, reminder_id],
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
    # After triggering, advance recurring reminders so the next occurrence
    # is ready in Firestore for Flutter to pick up via stream.
    advance_recurring_reminder(user_id, reminder_id)


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

    query = query.order_by("scheduled_time")

    docs  = query.stream()
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
    now = datetime.now(pytz.utc)

    docs = db.collection("users") \
        .document(user_id) \
        .collection("reminders") \
        .where("completed", "==", False) \
        .stream()

    upcoming = []

    for doc in docs:
        data = doc.to_dict()
        raw_time = data.get("scheduled_time") or data.get("time")
        if raw_time is None:
            continue
        try:
            st = raw_time
            if hasattr(st, 'tzinfo') and st.tzinfo is None:
                st = pytz.utc.localize(st)
            if st > now:
                data["id"] = doc.id
                data["scheduled_time"] = st
                upcoming.append(data)
        except Exception as e:
            print(f"⚠️ get_next_reminder comparison error for {doc.id}: {e}")
            continue

    if not upcoming:
        return None

    upcoming.sort(key=lambda x: x["scheduled_time"])
    return upcoming[0]


# ==========================================================
# ✅ NEW: Get Missed Reminders
# ==========================================================

def get_missed_reminders(user_id):
    """
    Return all reminders that are past-due, not completed, and not yet
    explicitly marked missed. Flutter uses this list to surface
    "You missed X — remind again in 10 min?" banners.
    """
    db = get_firestore_client()
    now = datetime.now(pytz.utc)

    docs = db.collection("users") \
        .document(user_id) \
        .collection("reminders") \
        .where("completed", "==", False) \
        .stream()

    missed = []
    for doc in docs:
        data = doc.to_dict()
        raw_time = data.get("scheduled_time") or data.get("time")
        if raw_time is None:
            continue
        try:
            st = raw_time
            if hasattr(st, "tzinfo") and st.tzinfo is None:
                st = pytz.utc.localize(st)
            # Past-due by more than 5 minutes and not snoozed
            if st < now - timedelta(minutes=5):
                data["id"] = doc.id
                data["scheduled_time"] = st
                missed.append(data)
        except Exception as e:
            print(f"⚠️ get_missed_reminders error for {doc.id}: {e}")
            continue

    return missed


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
            "completed":     True,
            "completed_at":  firestore.SERVER_TIMESTAMP,
            "last_modified": firestore.SERVER_TIMESTAMP,
        })

    # ✅ For recurring reminders, advance to next occurrence automatically
    advance_recurring_reminder(user_id, reminder_id)

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
            actual_task = data.get("task", task_text)
            doc.reference.delete()
            return actual_task

    return None


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