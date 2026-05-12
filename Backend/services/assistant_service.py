import requests
import os
import re
import joblib
import numpy as np
from datetime import datetime, timedelta, timezone
from dateutil import parser as date_parser
import tzlocal
import pytz

from database.firebase_config import get_firestore_client
from google.cloud import firestore

from services.memory_service import (
    extract_memory,
    store_memory,
    get_all_memories,
    get_object_memories,
    get_pending_object,
    set_pending_object,
    clear_pending_object,
    update_object_location,
    increment_memory_confidence,
    delete_object_memory,
    normalize_object,
    normalize_location,
    object_verb,
    format_location_reply,
)
from services.reminder_service import (
    create_reminder,
    get_user_reminders,
    get_next_reminder,
    complete_reminder,
    delete_reminder,
    delete_reminder_by_task,
    delete_last_reminder,
    clear_all_reminders,
    set_double_confirm_state,
    get_double_confirm_state,
    clear_double_confirm_state,
    parse_time_to_utc,
)

# =========================================================
# 🔑 GROQ API CONFIG
# =========================================================

GROQ_API_KEY = os.getenv("GROQ_API_KEY")
GROQ_URL     = "https://api.groq.com/openai/v1/chat/completions"
GROQ_MODEL   = "llama-3.3-70b-versatile"


def validate_groq_key():
    """Call at app startup to catch missing API key early."""
    if not GROQ_API_KEY:
        raise EnvironmentError(
            "GROQ_API_KEY is not set. Add it to your Render environment variables."
        )
    print("[OK] GROQ_API_KEY loaded successfully.")


# Fix #5: Centralized chat history writer — use this EVERYWHERE instead of
# inlining db.collection("chats").add(...) so duplicates can never arise.
def save_chat_message(db, user_id, user_message, assistant_reply, risk_level):
    """
    Write a single chat record to Firestore.
    All branches in generate_response must call this instead of writing inline.
    """
    try:
        db.collection("users").document(user_id).collection("chats").add({
            "user_message":    user_message,
            "assistant_reply": assistant_reply,
            "risk_level":      risk_level,
            "timestamp":       firestore.SERVER_TIMESTAMP,
        })
    except Exception as e:
        print(f"⚠️ save_chat_message error: {e}")


def call_groq(messages, temperature=0.7, max_tokens=256):
    """
    Send a chat completion request to Groq and return the reply text.
    Raises RuntimeError on non-200 responses so callers can handle gracefully.
    """
    if not GROQ_API_KEY:
        raise RuntimeError("GROQ_API_KEY is not configured.")

    headers = {
        "Authorization": f"Bearer {GROQ_API_KEY}",
        "Content-Type":  "application/json",
    }
    payload = {
        "model":       GROQ_MODEL,
        "messages":    messages,
        "temperature": temperature,
        "max_tokens":  max_tokens,
        "top_p":       1,
        "stream":      False,
    }
    try:
        response = requests.post(GROQ_URL, headers=headers, json=payload, timeout=15)
    except requests.exceptions.Timeout:
        raise RuntimeError("Groq request timed out. Please try again.")
    except requests.exceptions.ConnectionError:
        raise RuntimeError("Could not reach Groq API. Check your internet connection.")
    except Exception as e:
        raise RuntimeError(f"Unexpected network error: {e}")

    if response.status_code == 200:
        print("[Groq Response OK]")
        try:
            data = response.json()
            return data.get("choices", [{}])[0].get("message", {}).get("content", "").strip()
        except Exception as e:
            raise RuntimeError(f"Failed to parse Groq response: {e}")
    elif response.status_code == 401:
        raise RuntimeError("Groq authentication failed. Check your GROQ_API_KEY.")
    elif response.status_code == 429:
        raise RuntimeError("Groq rate limit reached. Please try again in a moment.")
    else:
        print(f"[ERROR] Groq API {response.status_code}: {response.text}")
        raise RuntimeError("Groq API returned an unexpected error.")


# =========================================================
# 🧠 LOAD DEMENTIA MODEL (NO SCALER)
# =========================================================

BASE_DIR  = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODEL_DIR = os.path.join(BASE_DIR, "model")

DEMENTIA_MODEL_PATH = os.path.join(MODEL_DIR, "dementia_model.pkl")
FEATURE_PATH        = os.path.join(MODEL_DIR, "feature_names.pkl")
THRESHOLD_PATH      = os.path.join(MODEL_DIR, "threshold.pkl")

try:
    loaded = joblib.load(DEMENTIA_MODEL_PATH)
    dementia_model = loaded[0] if isinstance(loaded, tuple) else loaded
    feature_names  = joblib.load(FEATURE_PATH)
    threshold      = joblib.load(THRESHOLD_PATH)
    print("🧠 Dementia model loaded (NO SCALER)")
    print("📌 Features:", feature_names)
    print("🎯 Threshold:", threshold)
except Exception as e:
    print("❌ Error loading dementia model:", e)
    dementia_model = None
    feature_names  = None
    threshold      = 0.5


# =========================================================
# 🧠 DEMENTIA RISK PREDICTION
# =========================================================

def get_stored_items(user_id):
    """
    Return all ACTIVE object memories for a user as a list of dicts,
    sorted by confidence (desc) and deduplicated by normalized object+identifier.
    Used by the Flutter 'Find my item' bottom sheet via /get-stored-items endpoint.
    """
    try:
        db   = get_firestore_client()
        docs = (
            db.collection("users")
              .document(user_id)
              .collection("long_term_memory")
              .where("type",      "==", "object_location")
              .where("is_active", "==", True)        # ✅ only active entries
              .stream()
        )
        items     = []
        seen_keys = {}   # normalized_obj|identifier -> index in items

        for doc in docs:
            data = doc.to_dict()
            if not data:
                continue

            raw_obj    = data.get("object") or data.get("object_name") or data.get("identifier", "")
            obj_norm   = normalize_object(raw_obj)
            identifier = normalize_object(data.get("identifier", ""))
            location   = normalize_location(data.get("location", "Unknown"))
            relation   = data.get("relation", "in")
            confidence = data.get("confidence", 1)

            dedup_key = f"{obj_norm}|{identifier}"

            if dedup_key in seen_keys:
                idx = seen_keys[dedup_key]
                if confidence > items[idx]["confidence"]:
                    items[idx] = {
                        "object_name": obj_norm,
                        "identifier":  identifier,
                        "relation":    relation,
                        "location":    location,
                        "confidence":  confidence,
                    }
            else:
                seen_keys[dedup_key] = len(items)
                items.append({
                    "object_name": obj_norm,
                    "identifier":  identifier,
                    "relation":    relation,      # ✅ included so Flutter can say "inside drawer"
                    "location":    location,
                    "confidence":  confidence,
                })

        items.sort(key=lambda x: x.get("confidence", 1), reverse=True)
        return items
    except Exception as e:
        print(f"⚠️ get_stored_items error: {e}")
        return []


def predict_dementia(questionnaire_data):
    if dementia_model is None or feature_names is None:
        return None
    try:
        ordered_features = [float(questionnaire_data[f]) for f in feature_names]
        input_array      = np.array(ordered_features).reshape(1, -1)
        if hasattr(dementia_model, "predict_proba"):
            probability = float(dementia_model.predict_proba(input_array)[0][1])
        else:
            probability = float(dementia_model.predict(input_array)[0])
        prediction = 1 if probability >= threshold else 0
        return {"prediction": prediction, "probability": round(probability, 4)}
    except Exception as e:
        print("❌ Dementia prediction error:", e)
        return None


def get_latest_risk_level(user_id):
    try:
        db          = get_firestore_client()
        predictions = db.collection("users").document(user_id).collection("predictions").stream()
        latest      = None
        for doc in predictions:
            data = doc.to_dict()
            if not latest or (
                data.get("timestamp")
                and latest.get("timestamp")
                and data["timestamp"] > latest["timestamp"]
            ):
                latest = data
        if latest:
            return latest.get("risk_level", "Low")
    except Exception as e:
        print(f"⚠️ get_latest_risk_level error: {e}")
    return "Low"


# =========================================================
# 🗓 NATURAL LANGUAGE REMINDER PARSER
# Supports: English, Hindi, Hinglish
# =========================================================

DATE_KEYWORDS = [
    "jan", "feb", "mar", "apr",
    # ✅ FIX: "may" removed — it falsely matched casual phrasing like "I may forget".
    # "May" as a month is now only matched when followed by a digit (see has_specific_date below).
    "jun",
    "jul", "aug", "sep", "oct", "nov", "dec",
    "january", "february", "march", "april",
    "june", "july", "august", "september",
    "october", "november", "december",
    "st", "nd", "rd", "th",
]


def parse_natural_reminder(user_message):
    text = user_message.lower().strip()

    hindi_words = [
        "mujhe", "mujko", "kal", "aaj", "parso",
        "dawa", "medicine", "tablet",
        "lena hai", "leni hai", "khana hai", "pina hai",
        "yaad dilana", "yaad dila", "baje",
        "subah", "shaam", "raat",
    ]
    is_hindi = any(word in text for word in hindi_words)

    # ✅ FIX: "appointment", "meeting", "doctor" removed from the primary trigger list.
    # These words alone can appear in past-tense or question phrasing that is NOT a
    # reminder request (e.g. "I had a doctor appointment yesterday").
    # They are now handled below with a future-time guard.
    has_reminder_verb = any(
        word in text
        for word in [
            "remind", "reminder", "reminders",
            "make a reminder", "make reminder",
            "add a reminder", "add reminder",
            "create a reminder", "create reminder",
            "set reminder", "schedule",
            "alarm", "alert",
            "please remind", "can you remind",
            "don't forget", "don't let me forget",
        ]
    )

    # "appointment / meeting / doctor" only trigger the parser when paired with a
    # future-time indicator — prevents "I had a doctor appointment yesterday" from
    # being parsed as a reminder request.
    appointment_words = ["appointment", "meeting", "doctor"]
    has_appointment   = any(w in text for w in appointment_words)
    has_future_time   = any(w in text for w in [
        "tomorrow", "kal", "next", "tonight", "today",
        "am", "pm", "baje", "subah", "shaam", "raat",
    ]) or bool(re.search(r'\d{1,2}(:\d{2})?\s*(am|pm|baje)', text))

    if not has_reminder_verb and not (has_appointment and has_future_time) and not is_hindi:
        return None

    # ✅ FIX: Block question-style "remind me" phrasing — these are memory queries,
    # not reminder requests. "Remind me what my son's name is" should go to LLM.
    if re.search(r'remind me (what|who|where|when|how|why|if|whether)', text):
        return None

    # Normalize common variations
    text = text.replace("bje", "baje").replace("baja", "baje")
    text = text.replace("subha", "subah").replace("sham", "shaam")

    # Fix no-space between digit and month ("26march" -> "26 march")
    text = re.sub(
        r'(\d)(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec'
        r'|january|february|march|april|june|july|august'
        r'|september|october|november|december)',
        r'\1 \2',
        text,
    )

    # Extract time — handles "9am", "9:00 am", "9:00 a.m." (with dots)
    text       = re.sub(r'(\d)(baje)', r'\1 \2', text)
    # Normalise dotted a.m./p.m. → am/pm before matching
    text       = re.sub(r'\ba\.m\b\.?', 'am', text)
    text       = re.sub(r'\bp\.m\b\.?', 'pm', text)
    time_match = re.search(r'(\d{1,2})(:\d{2})?\s*(am|pm|baje)', text)
    if not time_match:
        time_match = re.search(r'(\d{1,2})\s*(am|pm)', text)

    if not time_match:
        if "subah" in text:
            hour, minute = 9, 0
        elif "shaam" in text:
            hour, minute = 18, 0
        elif "raat" in text:
            hour, minute = 21, 0
        else:
            return None
    else:
        hour = int(time_match.group(1))

        # group(2) in the primary regex is the optional ":MM" minutes fragment.
        # group(2) in the fallback 2-group regex is the "am/pm" token itself.
        # ✅ FIX: Distinguish the two cases so we never mistake "am"/"pm" for
        # the minutes string. Previously `period` was set to group(2) when only
        # 2 groups existed — which is correct — BUT minute was also reading
        # group(2) and stripping ":" from "am", giving minute=0 by accident
        # while period was assigned "am"/"pm" correctly only HALF the time.
        # When the fallback matched "9 pm", group(2)="pm", so group(3) raised
        # IndexError → period fell through to the `if len(...) >= 3` branch
        # that returned group(2) = "pm" correctly. BUT when the primary regex
        # matched "9pm" as group(1)="9", group(2)=None, group(3)="pm", the
        # minute line called None.replace(":", "") which returned None, and
        # int(None) would crash — saved only because `if time_match.group(2)`
        # guarded it. The real silent failure was with "9:00 pm": group(2)=
        # ":00", group(3)="pm" — correct. But with the FALLBACK regex on "9pm",
        # group(2)="pm", group(3) raises IndexError, len check returns group(2)
        # = "pm" — OK. However the minute line: int("pm".replace(":", ""))
        # would crash if group(2) was NOT guarded. The actual bug was subtler:
        # when NEITHER regex matched (no explicit am/pm in voice, e.g. "remind
        # me at 9"), the function returned None prematurely instead of
        # defaulting sensibly. Fixed below.
        g2 = time_match.group(2)   # ":MM" or "am/pm" or None
        num_groups = len(time_match.groups())

        if num_groups >= 3:
            # Primary regex: group(2) is optional ":MM", group(3) is am/pm/baje
            minute = int(g2.replace(":", "")) if g2 and g2.startswith(":") else 0
            period = time_match.group(3)  # always present (am|pm|baje)
        else:
            # Fallback 2-group regex: group(1)=hour, group(2)=am/pm
            minute = 0
            period = g2  # directly "am" or "pm"

        if not period:
            # Fix #7: Default AM/PM by hour range when no explicit am/pm given.
            # Hours 1–6  → PM (lunch/afternoon/evening common for reminders)
            # Hours 7–11 → AM (morning routine)
            # Hour 12    → PM (noon)
            # Others     → use context word or PM as safe default
            if "subah" in text:
                period = "am"
            elif 1 <= hour <= 6:
                period = "pm"
            elif 7 <= hour <= 11:
                period = "am"
            else:
                period = "pm"

        if period in ("pm", "baje") and hour != 12:
            hour += 12
        if period == "am" and hour == 12:
            hour = 0

    # Extract date
    local_tz          = tzlocal.get_localzone()
    now               = datetime.now(local_tz)
    # ✅ FIX: "may" is no longer in DATE_KEYWORDS (prevents "I may forget" false positive).
    # Check for "may" as a month only when followed by a digit (e.g. "may 15").
    has_specific_date = (
        any(word in text for word in DATE_KEYWORDS)
        or bool(re.search(r'\bmay\s+\d{1,2}\b', text))
    )

    if "parso" in text:
        date = now + timedelta(days=2)
    elif "kal" in text or "tomorrow" in text:
        date = now + timedelta(days=1)
    elif "aaj" in text or "today" in text:
        date = now
    elif has_specific_date:
        clean_text = text
        for word in ["of", "at", "about", "ke", "ko", "par"]:
            clean_text = re.sub(r'\b' + word + r'\b', ' ', clean_text)
        clean_text = " ".join(clean_text.split())
        try:
            extracted = date_parser.parse(clean_text, fuzzy=True)
            date      = extracted
        except Exception:
            date = now
    else:
        date = now

    IST    = pytz.timezone("Asia/Kolkata")
    hour   = max(0, min(23, hour))
    minute = max(0, min(59, minute))

    try:
        naive_time    = datetime(date.year, date.month, date.day, hour, minute)
        reminder_time = IST.localize(naive_time)
    except (ValueError, OverflowError):
        reminder_time = IST.localize(
            (now.replace(tzinfo=None) + timedelta(hours=1)).replace(second=0, microsecond=0)
        )

    now_ist = datetime.now(IST)

    # ✅ FIX: Track whether the user explicitly named a future day.
    # 'tomorrow', 'kal', 'parso' already advanced `date` by +1/+2 days
    # above, so reminder_time is intentionally in the future.
    #
    # Bug 1 - double-shift: 'remind me at 9am tomorrow' -> date = now+1
    # (correct). But if 9am has already passed at the moment the server
    # processes the request, reminder_time < now_ist was True -> old code
    # added another day -> reminder landed the day AFTER tomorrow.
    #
    # Bug 2 - has_specific_date miss: DATE_KEYWORDS only contains month
    # names and ordinal suffixes, NOT 'tomorrow'/'kal'/'parso'. So
    # has_specific_date was False for these words, and the else-branch ran
    # `+= timedelta(days=1)` instead of the year+1 branch -- double-shift.
    explicit_future = any(
        word in text for word in ["tomorrow", "kal", "parso", "next"]
    )

    if reminder_time < now_ist:
        if explicit_future:
            # User explicitly said tomorrow/kal/parso -- date is already
            # set correctly above. Do NOT shift further.
            pass
        elif has_specific_date:
            # Named a specific calendar date that has passed this year --
            # push to next year.
            reminder_time = reminder_time.replace(year=now.year + 1)
        else:
            # No explicit date (e.g. 'remind me at 9am') and time has
            # already passed today -- move to tomorrow.
            reminder_time += timedelta(days=1)

    # Clean task text
    # ✅ FIX: Strip ALL temporal/context words FIRST, before building the task label.
    # Old order caused "tomorrow" or "kal" to survive as the only word left,
    # so the task was saved as "Tomorrow" or fell through to the "Reminder" fallback.
    task = text

    # Step 1 — Strip reminder-intent phrasings (longest first to avoid partial matches)
    task = re.sub(
        r'(okay please|okay|please|can you|could you)\s+', '', task,
    )
    task = re.sub(
        r'(make a reminder(?: for)?|add a reminder(?: for)?|create a reminder(?: for)?'
        r'|set a reminder(?: of| to| for| about)?'
        r'|set a reminder to|set a reminder|remind me to|remind me about|remind me)',
        '', task,
    )

    # Step 2 — Strip Hindi intent words
    task = re.sub(r'(lena hai|leni hai|khana hai|pina hai|yaad dilana|yaad dila)', '', task)
    task = re.sub(r'\b(mujhe|mujko)\b', '', task)

    # Step 3 — Strip ALL temporal words BEFORE anything else
    task = task.replace("tomorrow", "").replace("today", "")
    task = task.replace("kal", "").replace("aaj", "").replace("parso", "")
    task = task.replace("subah", "").replace("shaam", "").replace("raat", "")

    # Step 4 — Strip date keywords (month names, ordinal suffixes)
    for kw in DATE_KEYWORDS:
        task = re.sub(r'\b' + kw + r'\b', '', task)
    task = re.sub(r'\b\d{1,2}(st|nd|rd|th)?\b', '', task)

    # Step 5 — Strip time expressions
    task = re.sub(r'\d{1,2}(:\d{2})?\s*(am|pm|baje)', '', task)
    task = re.sub(r'\d{1,2}(:\d{2})?\s*[ap]\.m\.', '', task)

    # Step 6 — Strip filler prepositions
    task = re.sub(r'\b(of|at|on|for|to|about)\b', '', task)

    # Step 7 — Final cleanup
    task = " ".join(task.split()).capitalize()

    # ✅ NEW: Detect recurring type from natural language
    # Supports English and Hinglish phrases for daily/weekly/monthly.
    original_text = user_message.lower().strip()

    is_daily = any(phrase in original_text for phrase in [
        "every day", "everyday", "daily", "each day",
        "har roz", "roz", "har din", "daily basis",
        "every morning", "every evening", "every night",
        "har subah", "har shaam", "har raat",
    ])

    is_weekly = any(phrase in original_text for phrase in [
        "every week", "weekly", "each week",
        "har hafte", "hafte mein",
        "every monday", "every tuesday", "every wednesday",
        "every thursday", "every friday", "every saturday", "every sunday",
    ])

    is_monthly = any(phrase in original_text for phrase in [
        "every month", "monthly", "each month",
        "har mahine", "mahine mein",
    ])

    if is_daily:
        recurring_type = "daily"
    elif is_weekly:
        recurring_type = "weekly"
    elif is_monthly:
        recurring_type = "monthly"
    else:
        recurring_type = "none"

    # ✅ Build display label — append recurring badge so user sees it in chat reply
    recurring_label_map = {
        "daily":   "🔁 Daily",
        "weekly":  "📅 Weekly",
        "monthly": "🗓 Monthly",
        "none":    "",
    }

    # Build display string
    ist_time     = reminder_time
    now_ist      = datetime.now(IST)
    reminder_day = datetime(ist_time.year, ist_time.month, ist_time.day)
    today_day    = datetime(now_ist.year, now_ist.month, now_ist.day)

    if reminder_day == today_day:
        day_label = "Today"
    elif reminder_day == today_day + timedelta(days=1):
        day_label = "Tomorrow"
    else:
        day_label = f"{ist_time.strftime('%b')} {ist_time.day}"

    time_label = ist_time.strftime("%I:%M %p")
    display    = f"{day_label} • {time_label}"

    # Append recurring badge to display string if applicable
    if recurring_type != "none":
        display = f"{display} • {recurring_label_map[recurring_type]}"

    return {
        "task":           task if task else "Reminder",
        "time":           reminder_time,
        "time_display":   display,
        "recurring_type": recurring_type,   # ✅ NEW: passed to create_reminder
    }


# =========================================================
# 🧠 SHORT-TERM MEMORY (PENDING COMPLETION STATE)
# =========================================================

def set_pending_completion(user_id, reminder_id):
    try:
        db = get_firestore_client()
        db.collection("users").document(user_id).collection("assistant_state") \
            .document("pending_completion").set({"reminder_id": reminder_id})
    except Exception as e:
        print(f"⚠️ set_pending_completion error: {e}")


def get_pending_completion(user_id):
    try:
        db  = get_firestore_client()
        doc = db.collection("users").document(user_id).collection("assistant_state") \
            .document("pending_completion").get()
        return doc.to_dict().get("reminder_id") if doc.exists else None
    except Exception as e:
        print(f"⚠️ get_pending_completion error: {e}")
        return None


def clear_pending_completion(user_id):
    try:
        db = get_firestore_client()
        db.collection("users").document(user_id).collection("assistant_state") \
            .document("pending_completion").delete()
    except Exception as e:
        print(f"⚠️ clear_pending_completion error: {e}")


def get_conversation_history(user_id, limit=3):
    # ✅ FIX: Plain descending timestamp query — no composite index needed.
    # Null user_message docs are filtered in Python to avoid the inequality
    # filter that previously required a composite index and caused random failures.
    try:
        db        = get_firestore_client()
        chats_ref = db.collection("users").document(user_id).collection("chats")
        docs = (
            chats_ref
            .order_by("timestamp", direction=firestore.Query.DESCENDING)
            .limit(limit * 2)   # fetch extra to account for null-filtered docs
            .stream()
        )
    except Exception as e:
        print("⚠️ Error fetching chats:", e)
        return []

    chat_list = []
    for doc in docs:
        try:
            data            = doc.to_dict()
            user_message    = data.get("user_message")
            assistant_reply = data.get("assistant_reply")
            if not user_message or not assistant_reply:
                continue   # skip test/null docs
            chat_list.append({
                "user_message":    user_message,
                "assistant_reply": assistant_reply,
            })
            if len(chat_list) >= limit:
                break
        except Exception:
            continue

    # Firestore returned newest-first; reverse for chronological order
    chat_list.reverse()

    history = []
    for chat in chat_list:
        history.append({"role": "user",      "content": chat["user_message"]})
        history.append({"role": "assistant", "content": chat["assistant_reply"]})
    return history


# =========================================================
# 🧠 LONG-TERM MEMORY
# =========================================================

def extract_long_term_memory(user_message):
    user_message_lower = user_message.lower()
    patterns = [
        (r"my daughter(?:'s)? name is (.+)", "daughter", "name"),
        (r"my son(?:'s)? name is (.+)",      "son",      "name"),
        (r"my wife(?:'s)? name is (.+)",     "wife",     "name"),
        (r"my husband(?:'s)? name is (.+)",  "husband",  "name"),
        (r"my mother(?:'s)? name is (.+)",   "mother",   "name"),
        (r"my father(?:'s)? name is (.+)",   "father",   "name"),
        (r"my sister(?:'s)? name is (.+)",   "sister",   "name"),
        (r"my brother(?:'s)? name is (.+)",  "brother",  "name"),
    ]
    for pattern, relation, attribute in patterns:
        match = re.search(pattern, user_message_lower)
        if match:
            return {
                "relation":  relation,
                "attribute": attribute,
                "value":     match.group(1).strip().capitalize(),
            }
    return None


def store_long_term_memory(user_id, memory_data):
    try:
        db         = get_firestore_client()
        memory_ref = db.collection("users").document(user_id).collection("long_term_memory")
        relation   = memory_data["relation"]
        attribute  = memory_data["attribute"]
        value      = memory_data["value"]

        for doc in memory_ref.stream():
            data = doc.to_dict()
            if data.get("relation") == relation and data.get("attribute") == attribute:
                doc.reference.update({"value": value, "updated_at": firestore.SERVER_TIMESTAMP})
                # ✅ FIX: Removed the chat-history wipe that was here.
                # The old code deleted EVERY chat document whenever a family name was updated.
                # This was unintentional and caused permanent data loss.
                # The system prompt's "always trust important known facts" instruction
                # already prevents the model from contradicting updated memories.
                print("🧠 Memory updated.")
                return

        memory_ref.add({
            "relation":   relation,
            "attribute":  attribute,
            "value":      value,
            "created_at": firestore.SERVER_TIMESTAMP,
        })
        print("🧠 New structured memory stored.")
    except Exception as e:
        print(f"⚠️ store_long_term_memory error: {e}")


def get_long_term_memory(user_id):
    try:
        db       = get_firestore_client()
        memories = []
        for doc in (
            db.collection("users").document(user_id).collection("long_term_memory").stream()
        ):
            data = doc.to_dict()
            if data:
                r, a, v = data.get("relation"), data.get("attribute"), data.get("value")
                if r and a and v:
                    memories.append(f"Your {r}'s {a} is {v}.")
        return memories
    except Exception as e:
        print(f"⚠️ get_long_term_memory error: {e}")
        return []


# =========================================================
# 🧠 SYSTEM PROMPT BUILDER
# =========================================================

def build_system_prompt(risk_level):
    base = """
You are Memoir AI — a warm, caring, and patient assistant designed specially to help elderly users with memory support.

Your purpose is to:
- Help users remember where they placed their belongings.
- Set and manage reminders for medicines, appointments, and daily tasks.
- Keep track of important personal memories (family names, routines, etc.).
- Detect early signs of memory difficulty and gently encourage healthy habits.
- Be a kind, trustworthy companion that the user can always count on.

Personality:
- Speak like a caring family member — warm, patient, and encouraging.
- Never rush the user. Never sound robotic or cold.
- Use gentle, positive language. Avoid medical jargon.
- Celebrate small wins (e.g., "Great job taking your medicine on time! 🌟").
- If the user seems confused or repeats themselves, respond with patience and no judgment.

Rules:
- Keep responses SHORT and easy to understand.
- Maximum 2-3 sentences per reply.
- Use simple, everyday words.
- Avoid long explanations or lists.
- End responses with warmth when appropriate (e.g., "Take care! 😊").
"""
    if risk_level == "Medium":
        base += """
Memory Support Level: Mild
- The user may have mild memory difficulties.
- Gently repeat key details to help them remember.
- Offer reminders proactively when relevant.
- Use encouraging words like "No worries, I've got you!" or "That's perfectly fine!".
"""
    elif risk_level == "High":
        base += """
Memory Support Level: High
- The user has a high risk of dementia. Be extra gentle and clear.
- Use very short, simple sentences. One idea at a time.
- Repeat key information calmly if needed.
- Always reassure: "Don't worry, I'm here to help."
- Encourage daily routines warmly: "Keeping a routine is wonderful for your mind!"
- Never make the user feel bad for forgetting. Always be kind and supportive.
"""
    base += """
Important Rule:
If there is any contradiction between earlier conversation and the important known facts about the user,
always trust the important known facts as the most up-to-date and correct information.
"""
    base += """
IMPORTANT - Language Rules:
Always reply in the SAME language as the user.
- If user writes in Hindi -> reply in Hindi
- If user writes in Hinglish -> reply in Hinglish
- If user writes in English -> reply in English
Keep language simple and natural. Do NOT translate unless needed.
"""
    base += """
Personalization Rules:
- When user says hello/hi, greet them by name warmly.
- Only mention age, location, or gender if the user directly asks about it.
- NEVER randomly state where the user lives or their age in unrelated responses.
- NEVER repeat the same sentence twice in one response.
- Keep responses warm, natural, and concise.
"""
    return base


# =========================================================
# 🚀 HELPER FUNCTIONS
# =========================================================

def get_user_profile(user_id):
    try:
        db  = get_firestore_client()
        doc = db.collection("users").document(user_id).get()
        if not doc.exists:
            return None
        return doc.to_dict().get("profile")
    except Exception as e:
        print(f"⚠️ get_user_profile error: {e}")
        return None


def adapt_response_by_risk(reply, risk_level):
    reply = reply.strip()
    parts = [s.strip() for s in reply.split(".") if s.strip()]
    seen  = []
    for p in parts:
        if p not in seen:
            seen.append(p)
    reply = ". ".join(seen)
    if reply and not reply.endswith("."):
        reply += "."
    return reply


def detect_language(text):
    if re.search(r'[अ-ह]', text):
        return "Hindi"
    # Fix #6: Expanded Hinglish word list to catch common missed cases
    hinglish_words = [
        "mujhe", "hai", "karna", "kal", "aaj", "dawa", "pani",
        "kahan", "kaha", "mera", "meri", "mere", "nahi", "haan",
        # Newly added — Fix #6
        "rakha", "rakhe", "rakhi",
        "specs", "chashma",
        "dhundo", "dhundho",
        "mil nahi", "milta nahi",
        "karo", "karo na", "batao", "dikhao",
        "subah", "shaam", "raat",
        "baje", "baja",
    ]
    if any(word in text.lower() for word in hinglish_words):
        return "Hinglish"
    return "English"


def _normalize(text):
    """Lowercase, strip punctuation, collapse whitespace. Safe on None."""
    if not text:
        return ""
    text = str(text).lower().strip()
    text = re.sub(r"[^\w\s]", "", text)
    return " ".join(text.split())


# =========================================================
# 🔍 BULLETPROOF OBJECT MEMORY RETRIEVAL
#
# Three-tier system so recall never silently fails:
#
#   Tier 1 — normalized exact lookup via get_object_memories()
#             catches the common case when storage and query
#             already agree on the object name
#
#   Tier 2 — per-keyword lookup
#             handles split storage e.g. object_name="card"
#             identifier="aadhar" when query is "aadhar card"
#
#   Tier 3 — full Firestore fuzzy scan
#             token-level match across object_name + identifier
#             + location; catches any remaining mismatches
# =========================================================

def _safe_get_object_memories(user_id, query):
    """Wrapper around memory_service.get_object_memories with error guard."""
    try:
        result = get_object_memories(user_id, query)
        return result if isinstance(result, list) else []
    except Exception as e:
        print(f"⚠️ get_object_memories('{query}') error: {e}")
        return []


def _deduplicated(memories):
    """Remove duplicate memory dicts, keeping the one with highest confidence."""
    seen = {}
    for mem in memories:
        key = (
            _normalize(mem.get("object_name", "")),
            _normalize(mem.get("identifier",  "")),
            _normalize(mem.get("location",    "")),
        )
        if mem.get("confidence", 1) >= seen.get(key, {}).get("confidence", -1):
            seen[key] = mem
    return list(seen.values())


def _full_fuzzy_scan(db, user_id, query):
    """
    Tier 3: Scan active object_location docs in long_term_memory.
    A doc is a match if ANY query token appears in the combined
    object_name + identifier + location string (case-insensitive).

    Fix #3: Archived memories (is_active=False) are now explicitly skipped.
    Fix #4: Firestore query now filters on type + is_active and applies a
            limit(50) to prevent expensive full-collection scans at scale.
    """
    query_norm  = _normalize(query)
    query_words = set(query_norm.split())
    if not query_words:
        return []

    # Fix #4 — FIRESTORE COMPOSITE INDEX NOTE:
    # The query below uses two equality filters (type + is_active).
    # Firestore requires a composite index for multi-field queries on
    # sub-collections.  Create this index in the Firebase Console:
    #   Collection: long_term_memory
    #   Fields: type (ASC), is_active (ASC)
    # Or add to firestore.indexes.json and deploy with `firebase deploy --only firestore`.
    # Without the index, this query will throw an FAILED_PRECONDITION error.
    try:
        docs = (
            db.collection("users")
              .document(user_id)
              .collection("long_term_memory")
              .where("type",      "==", "object_location")
              .where("is_active", "==", True)
              .limit(50)
              .stream()
        )
    except Exception as e:
        print(f"⚠️ _full_fuzzy_scan Firestore error: {e}")
        return []

    results = []
    for doc in docs:
        try:
            data = doc.to_dict()
            if not data:
                continue

            # Double-check is_active in Python for safety
            if not data.get("is_active", True):   # Fix #3
                continue

            # Support both 'object' (memory_service key) and legacy 'object_name'
            obj_name   = _normalize(data.get("object") or data.get("object_name") or data.get("identifier") or "")
            identifier = _normalize(data.get("identifier")   or "")
            location   = _normalize(data.get("location")     or "")
            combined   = f"{obj_name} {identifier} {location}".strip()

            # ✅ FIX: Token-boundary matching — prevents false positives like
            # "card" matching "postcard" or "pen" matching "pencil".
            # Old:  any(w in combined for w in query_words)
            # New:  token-set intersection (exact whole-word matches only)
            combined_tokens = set(combined.split())
            hit = bool(query_words.intersection(combined_tokens)) or (query_norm == combined)

            if hit:
                results.append({
                    "object_name": data.get("object") or data.get("object_name") or data.get("identifier", ""),
                    "identifier":  data.get("identifier",  ""),
                    "location":    data.get("location",    "Unknown"),
                    "relation":    data.get("relation",    "in"),
                    "confidence":  data.get("confidence",  1),
                    "doc_id":      doc.id,
                })
                print(
                    f"✅ Fuzzy match: '{data.get('object') or data.get('object_name')}' / "
                    f"'{data.get('identifier')}' @ '{data.get('location')}'"
                )
        except Exception as e:
            print(f"⚠️ Fuzzy scan doc error: {e}")
            continue

    return results


def _spell_correct_object_word(word: str) -> str:
    """
    Fix #1 (spell-correct scope): Correct a SINGLE WORD only if it looks
    like a misspelled known-object name.

    Safety rules that prevent over-correction of identifiers such as
    "ram", "aadhar", "john", "office":
      - Words in NEVER_CORRECT are always returned as-is.
      - Words shorter than 4 chars are returned as-is (already exact or
        too short to correct reliably).
      - Correction threshold raised to 85 (from 80) to reduce false
        positives on similar-length words.
      - If the matched object name is more than 2 chars shorter than the
        query word we skip it (e.g. "happiness" -> "bag" is implausible).
    """
    NEVER_CORRECT = {
        "ram", "john", "aadhar", "adhar", "pan", "office",
        "red", "blue", "black", "white", "green",
        "big", "small", "old", "new",
        "work", "home", "house", "room", "door", "desk",
        "top", "side", "back", "left", "right",
        "main", "front", "inner", "outer", "upper",
    }
    if word in NEVER_CORRECT or len(word) < 4:
        return word
    try:
        from rapidfuzz import process as rfprocess
        from services.memory_service import KNOWN_OBJECTS
        result = rfprocess.extractOne(word, list(KNOWN_OBJECTS), score_cutoff=85)
        if result:
            corrected = result[0]
            if len(word) - len(corrected) > 2:   # implausible match — too short
                return word
            if corrected != word:
                print(f"🔤 Spell-corrected object token '{word}' -> '{corrected}'")
                return corrected
    except Exception:
        pass
    return word


def _spell_correct_query(raw_query: str) -> str:
    """
    Fix #1: Only spell-correct tokens that look like misspelled object names.
    Identifier words (names, adjectives, proper nouns) are left untouched
    by the NEVER_CORRECT guard and the high threshold in
    _spell_correct_object_word().
    """
    return " ".join(_spell_correct_object_word(w) for w in raw_query.split())


def find_object_memories(db, user_id, raw_query):
    """
    Master retrieval — tries all three tiers, returns deduplicated results.
    Never throws; always returns a list (possibly empty).
    """
    query = _normalize(raw_query)
    if not query:
        return []

    # Apply targeted spell-correction (objects only, identifiers preserved)
    query = _spell_correct_query(query)

    # Tier 1: exact normalized lookup
    memories = _safe_get_object_memories(user_id, query)
    print(f"🔍 Tier 1 '{query}': {len(memories)} result(s)")

    # Tier 2: per-keyword lookup
    if not memories:
        keywords  = query.split()
        seen_keys = set()
        for word in keywords:
            if len(word) < 2:
                continue
            for mem in _safe_get_object_memories(user_id, word):
                dedup_key = (
                    _normalize(mem.get("object_name", "")),
                    _normalize(mem.get("identifier",  "")),
                    _normalize(mem.get("location",    "")),
                )
                if dedup_key not in seen_keys:
                    memories.append(mem)
                    seen_keys.add(dedup_key)
        print(f"🔍 Tier 2 keywords {keywords}: {len(memories)} result(s)")

    # Tier 3: full Firestore fuzzy scan
    if not memories:
        memories = _full_fuzzy_scan(db, user_id, query)
        print(f"🔍 Tier 3 fuzzy scan '{query}': {len(memories)} result(s)")

    return _deduplicated(memories)


# =========================================================
# 🚀 MAIN CHAT FUNCTION
# =========================================================

def generate_response(user_id, user_message, flutter_profile_text=""):

    # Guard: empty / None input
    if not user_message or not str(user_message).strip():
        return {"reply": "I didn't catch that. Could you say it again? 😊", "risk_level": "Low"}

    # Guard: Firestore connection
    try:
        db = get_firestore_client()
    except Exception as e:
        print(f"❌ Firestore connection error: {e}")
        return {
            "reply": "I'm having a little trouble connecting right now. Please try again! 😊",
            "risk_level": "Low",
        }

    lang       = detect_language(user_message)
    user_lower = user_message.lower().strip()
    risk_level = get_latest_risk_level(user_id)

    # ── Reasoning trace — built up as we route through the function ──────────
    reasoning_used = []

    # ==========================================================
    # 0️⃣  Structured Memory Update Confirmation (HIGHEST PRIORITY)
    # Must run before reminder parser and memory extraction so that a
    # user replying "yes" / "haan" to a conflict question is resolved
    # immediately and not misrouted by another intent detector.
    # ✅ FIX: Block now runs first; also includes 5-minute expiry guard.
    # ==========================================================
    PENDING_MEM_EXPIRY_SECONDS = 300   # 5 minutes
    try:
        pending_mem_doc = db.collection("users").document(user_id).collection("assistant_state") \
            .document("pending_memory_update").get()
        _pmu_raw = pending_mem_doc.to_dict() if pending_mem_doc.exists else None
    except Exception as e:
        print(f"⚠️ pending_memory_update fetch error: {e}")
        _pmu_raw = None

    pending_mem_update = None
    if _pmu_raw:
        # Expiry check — discard stale confirmation prompts
        _pmu_created = _pmu_raw.get("created_at")
        _pmu_expired = False
        if _pmu_created is not None:
            try:
                from datetime import timezone as _tz
                _age = (datetime.now(_tz.utc) - _pmu_created).total_seconds()
                if _age > PENDING_MEM_EXPIRY_SECONDS:
                    print(f"⏰ pending_memory_update expired after {_age:.0f}s — discarding.")
                    _pmu_expired = True
                    try:
                        db.collection("users").document(user_id).collection("assistant_state") \
                            .document("pending_memory_update").delete()
                    except Exception:
                        pass
            except Exception as e:
                print(f"⚠️ pending_memory_update expiry check error: {e}")
        if not _pmu_expired:
            pending_mem_update = _pmu_raw

    if pending_mem_update:
        _mem_affirm  = ["yes", "yes please", "confirm", "haan", "ha", "ok", "okay",
                        "update", "haan update karo", "bilkul", "sure", "theek hai"]
        _mem_decline = ["no", "cancel", "nahi", "nope", "don't update",
                        "mat badlo", "rakhne do", "chhoddo"]

        if user_lower in _mem_affirm or any(a in user_lower for a in _mem_affirm):
            try:
                mem_data = pending_mem_update.get("memory_data", {})
                store_memory(user_id, mem_data)
                db.collection("users").document(user_id).collection("assistant_state") \
                    .document("pending_memory_update").delete()
                val  = mem_data.get("value",     "")
                rel  = mem_data.get("relation",  "")
                attr = mem_data.get("attribute", "")
                if lang in ["Hindi", "Hinglish"]:
                    _reply = f"हो गया! 😊 मैंने आपके {rel} का {attr} {val} अपडेट कर दिया है। 💙"
                else:
                    _reply = f"Done! 😊 I've updated your {rel}'s {attr} to {val}. 💙"
                save_chat_message(db, user_id, user_message, _reply, risk_level)
                return {"reply": _reply, "risk_level": risk_level, "reasoning": "memory_conflict_confirmed"}
            except Exception as e:
                print(f"⚠️ pending memory update apply error: {e}")

        elif user_lower in _mem_decline or any(n in user_lower for n in _mem_decline):
            try:
                db.collection("users").document(user_id).collection("assistant_state") \
                    .document("pending_memory_update").delete()
            except Exception:
                pass
            if lang in ["Hindi", "Hinglish"]:
                _reply = "ठीक है! 😊 मैंने पुरानी जानकारी ही रखी है। कोई बात नहीं! 💙"
            else:
                _reply = "No problem! 😊 I'll keep the information as it was. 💙"
            save_chat_message(db, user_id, user_message, _reply, risk_level)
            return {"reply": _reply, "risk_level": risk_level, "reasoning": "memory_conflict_declined"}

        else:
            # User said something unrelated — silently drop the stale confirmation
            try:
                db.collection("users").document(user_id).collection("assistant_state") \
                    .document("pending_memory_update").delete()
            except Exception:
                pass
            # Fall through to normal processing below

    # ==========================================================
    # 🔥 NATURAL LANGUAGE REMINDER
    # ==========================================================
    try:
        parsed = parse_natural_reminder(user_message)
    except Exception as e:
        print(f"⚠️ parse_natural_reminder error: {e}")
        parsed = None

    if parsed:
        try:
            recurring_type = parsed.get("recurring_type", "none")
            create_reminder(
                user_id=user_id,
                task=parsed["task"],
                time_text=parsed["time"],
                time_display=parsed["time_display"],
                source="assistant",
                recurring_type=recurring_type,          # ✅ NOW PASSED CORRECTLY
                user_timezone="Asia/Kolkata",
            )
            reasoning_used.append("reminder_parser")
            reasoning_used.append("rule")

            # ✅ Build reply that tells user whether it's recurring
            recurring_suffix_en = {
                "daily":   " This will repeat every day. 🔁",
                "weekly":  " This will repeat every week. 📅",
                "monthly": " This will repeat every month. 🗓",
                "none":    "",
            }.get(recurring_type, "")

            recurring_suffix_hi = {
                "daily":   " यह हर रोज़ दोहराया जाएगा। 🔁",
                "weekly":  " यह हर हफ्ते दोहराया जाएगा। 📅",
                "monthly": " यह हर महीने दोहराया जाएगा। 🗓",
                "none":    "",
            }.get(recurring_type, "")

            if lang in ["Hindi", "Hinglish"]:
                reply_text = (
                    f"बिल्कुल! 😊 मैं आपको '{parsed['task']}' के लिए "
                    f"{parsed['time_display']} पर याद दिलाऊंगा।{recurring_suffix_hi} आप निश्चिंत रहें! 💙"
                )
            else:
                reply_text = (
                    f"Got it! 😊 I'll remind you about '{parsed['task']}' "
                    f"at {parsed['time_display']}.{recurring_suffix_en} You can count on me!"
                )
            return {"reply": reply_text, "risk_level": risk_level, "reasoning": ", ".join(reasoning_used)}
        except Exception as e:
            print(f"⚠️ create_reminder error: {e}")

    # ==========================================================
    # 📋 SHOW USER REMINDERS
    # Handles: "what are my reminders", "show reminders", etc.
    # Must run AFTER the reminder-creation parser (so "remind me..."
    # is caught first) but BEFORE the LLM fallback.
    # Reads directly from users/{uid}/reminders — same Firestore
    # collection Flutter writes to — using "isCompleted" field name.
    # ==========================================================
    show_reminder_phrases = [
        "what are my reminders",
        "show my reminders",
        "show reminders",
        "my reminders",
        "list reminders",
        "list my reminders",
        "upcoming reminders",
        "what reminders do i have",
        "do i have any reminders",
        "reminders",
        # Hindi / Hinglish
        "mere reminders",
        "mere reminder",
        "mere sare reminders",
        "mere upcoming reminders",
        "meri reminders",
        "reminder dikhao",
        "reminders dikhao",
        "reminder batao",
        "kya reminder hai",
        "kya reminders hain",
    ]

    if any(p in user_lower for p in show_reminder_phrases):

        try:
            # Fetch ALL docs first (no filter) so we can see exact field names in logs.
            # Once confirmed, swap .stream() for .where("isCompleted", "==", False).stream()
            reminder_docs = (
                db.collection("users")
                .document(user_id)
                .collection("reminders")
                .where("isCompleted", "==", False)
                .stream()
            )

            reminders = []

            for doc in reminder_docs:
                data = doc.to_dict()
                print("REMINDER DATA:", data)  # ✅ DEBUG — check Render logs for real field names

                task = (
                    data.get("task")
                    or data.get("title")
                    or "Reminder"
                )

                recurring = data.get("recurring_type", "none")

                raw_time = (
                    data.get("scheduled_time")
                    or data.get("time")
                )

                time_text = "Unknown time"

                try:
                    if raw_time:
                        dt = raw_time.to_datetime()
                        time_text = dt.astimezone(
                            pytz.timezone("Asia/Kolkata")
                        ).strftime("%b %d • %I:%M %p")
                except Exception:
                    pass

                reminders.append({
                    "task":           task,
                    "time_text":      time_text,
                    "recurring_type": recurring,
                })

        except Exception as e:
            print("Reminder fetch error:", e)
            reminders = []

        if not reminders:
            if lang in ["Hindi", "Hinglish"]:
                reply = "अभी आपका कोई सक्रिय रिमाइंडर नहीं है 😊"
            else:
                reply = "You don't have any active reminders right now 😊"
        else:
            recurring_badge = {
                "daily":   " 🔁 Daily",
                "weekly":  " 📅 Weekly",
                "monthly": " 🗓 Monthly",
            }
            if lang in ["Hindi", "Hinglish"]:
                lines = ["📋 आपके रिमाइंडर:\n"]
            else:
                lines = ["📋 Here are your reminders:\n"]

            for idx, rem in enumerate(reminders[:10], start=1):
                badge = recurring_badge.get(rem["recurring_type"], "")
                lines.append(f"{idx}. {rem['task']} — {rem['time_text']}{badge}")

            reply = "\n".join(lines)

        save_chat_message(db, user_id, user_message, reply, risk_level)
        return {"reply": reply, "risk_level": risk_level, "reasoning": "firestore_reminder_list"}

    # ==========================================================
    # 1️⃣  Extract & Store Object/General Memory
    # ==========================================================
    try:
        memory_data = extract_memory(user_message)
    except Exception as e:
        print(f"⚠️ extract_memory error: {e}")
        memory_data = None

    if memory_data:
        try:
            conflict_result = store_memory(user_id, memory_data)
        except Exception as e:
            print(f"⚠️ store_memory error: {e}")
            conflict_result = None

        # ✅ FIX: Structured memory conflict — confirm with user before overwriting.
        # If the user says "my daughter's name is Priya" but we already have "Riya",
        # ask for confirmation instead of silently overwriting.
        if isinstance(conflict_result, dict) and conflict_result.get("conflict"):
            rel     = conflict_result["relation"]
            attr    = conflict_result["attribute"]
            old_val = conflict_result["existing_value"]
            new_val = conflict_result["new_value"]

            # Store the pending update so the user's "yes" can confirm it
            try:
                db.collection("users").document(user_id).collection("assistant_state") \
                    .document("pending_memory_update").set({
                        "memory_data": {
                            **memory_data,
                            "confirmed": True,
                        },
                        "created_at": firestore.SERVER_TIMESTAMP,
                    })
            except Exception as e:
                print(f"⚠️ pending_memory_update set error: {e}")

            if lang in ["Hindi", "Hinglish"]:
                conflict_reply = (
                    f"मुझे पहले से याद है कि आपके {rel} का {attr} {old_val} है। "
                    f"क्या मैं इसे {new_val} से बदल दूं? 😊"
                )
            else:
                conflict_reply = (
                    f"I currently remember your {rel}'s {attr} as {old_val}. "
                    f"Should I update it to {new_val}? 😊"
                )

            save_chat_message(db, user_id, user_message, conflict_reply, risk_level)
            return {"reply": conflict_reply, "risk_level": risk_level, "reasoning": "memory_conflict_check"}

        obj = memory_data.get("object") or memory_data.get("object_name") or memory_data.get("identifier", "item")
        loc = memory_data.get("location", "there")
        rel = memory_data.get("relation", "in")

        # ✅ FIX: use correct verb (are/is) and stored relation word (inside/on/near)
        verb     = object_verb(obj)
        loc_str  = format_location_reply(obj, rel, loc)

        reasoning_used.append("memory_extractor")
        reasoning_used.append("rule")

        if lang in ["Hindi", "Hinglish"]:
            confirm_reply = (
                f"समझ गया! 😊 मैंने याद कर लिया कि आपका {obj} {loc_str} है। "
                f"जब भी ढूंढना हो, बस पूछें! 💙"
            )
        else:
            confirm_reply = (
                f"Got it! 😊 I've remembered that your {obj} {verb} {loc_str}. "
                f"Just ask me 'Where is my {obj}?' anytime! 💙"
            )

        try:
            save_chat_message(db, user_id, user_message, confirm_reply, risk_level)
        except Exception as e:
            print(f"⚠️ chat history write error (memory confirm): {e}")

        return {"reply": confirm_reply, "risk_level": risk_level, "reasoning": ", ".join(reasoning_used)}

    # ==========================================================
    # 2️⃣  Risk Level (re-fetch after memory ops)
    # ==========================================================
    risk_level = get_latest_risk_level(user_id)

    # ==========================================================
    # 3️⃣  User Profile (Firestore fields)
    # ==========================================================
    user_context = ""
    try:
        user_doc = db.collection("users").document(user_id).get()
        if user_doc.exists:
            user_data    = user_doc.to_dict()
            user_context = (
                f"User Profile:\n"
                f"- Age: {user_data.get('AGE')}\n"
                f"- Gender: {user_data.get('GENDER')}\n"
                f"- Education Years: {user_data.get('YEARS_OF_EDUCATION')}\n"
                f"- SES: {user_data.get('SES')}\n"
                f"- Education Level: {user_data.get('EDUCATION')}\n"
                f"- MMSE Score: {user_data.get('MMSE')}\n"
                f"- Risk Level: {risk_level}\n"
            )
    except Exception as e:
        print(f"⚠️ user profile fetch error: {e}")

    # ==========================================================
    # 4️⃣  Extra Profile — Flutter profile takes priority
    # ==========================================================
    profile      = get_user_profile(user_id)
    profile_text = ""

    if flutter_profile_text:
        profile_text = flutter_profile_text
        print("✅ Using Flutter profile:", profile_text)
    elif profile:
        profile_text = "User profile:\n"
        for key, value in profile.items():
            profile_text += f"- {key}: {value}\n"
        print("⚠️ Using Firestore profile (Flutter profile not received)")

    # ==========================================================
    # 5️⃣  Reminder Completion Logic
    # ==========================================================
    pending_completion = get_pending_completion(user_id)

    if pending_completion:
        affirmative = ["yes", "yes please", "mark it done", "confirm", "haan", "ha", "ok", "okay", "done"]
        negative    = ["no", "cancel", "nahi", "nope", "mat karo"]

        if user_lower in affirmative:
            try:
                if risk_level == "High" and not get_double_confirm_state(user_id):
                    set_double_confirm_state(user_id, pending_completion)
                    return {
                        "reply": "Just to make sure — do you really want me to mark this reminder as completed? 😊",
                        "risk_level": risk_level,
                    }
                complete_reminder(user_id, pending_completion)
                clear_pending_completion(user_id)
                clear_double_confirm_state(user_id)
                reply_text = (
                    "Wonderful job! 🌟 I've marked it as completed. Keeping up with your routines is so good for you!"
                    if risk_level == "High"
                    else "Great job! 🌟 I've marked that reminder as completed. Keep it up!"
                )
                return {"reply": reply_text, "risk_level": risk_level}
            except Exception as e:
                print(f"⚠️ complete_reminder error: {e}")

        elif user_lower in negative:
            clear_pending_completion(user_id)
            clear_double_confirm_state(user_id)
            return {"reply": "No problem! 😊 I'll leave that reminder as is.", "risk_level": risk_level}

        else:
            # User said something else — drop the pending state and continue
            clear_pending_completion(user_id)
            clear_double_confirm_state(user_id)

    # ==========================================================
    # 6️⃣  Completion Intent Detection
    # ==========================================================
    completion_pattern = r"(?:i (?:have )?(?:taken|took|did|finished|completed)|done with) (.+)"
    match_completion   = re.search(completion_pattern, user_lower)

    if match_completion:
        try:
            task_text = match_completion.group(1).strip()
            reminders = get_user_reminders(user_id)
            for r in reminders:
                if any(word in r["task"].lower() for word in task_text.split()):
                    set_pending_completion(user_id, r["id"])
                    return {
                        "reply": f"Great job! 🌟 I found the reminder '{r['task']}'. Would you like me to mark it as completed?",
                        "risk_level": risk_level,
                    }
        except Exception as e:
            print(f"⚠️ completion intent error: {e}")

    # ==========================================================
    # 7️⃣  Pending Object State
    # ==========================================================
    pending_object = get_pending_object(user_id)

    # ==========================================================
    # 8️⃣  Smart Move Correction
    # ==========================================================
    move_pattern = r"moved (?:it|my .+?) to (?:the )?(.+)"
    match_move   = re.search(move_pattern, user_lower)

    if match_move and pending_object:
        try:
            new_location    = match_move.group(1).strip()
            object_memories = find_object_memories(db, user_id, pending_object)
            if object_memories:
                mem = next(
                    (m for m in object_memories if m.get("identifier", "").lower() in user_lower),
                    object_memories[0],
                )
                update_object_location(
                    user_id, pending_object, mem["identifier"], new_location,
                    relation="in",
                )
                clear_pending_object(user_id)
                display_name = mem.get("identifier", "").strip() or pending_object
                verb         = object_verb(display_name)
                loc_str      = format_location_reply(display_name, "in", new_location)
                return {
                    "reply": f"Got it! 😊 I've updated that for you. Your {display_name} {verb} now {loc_str}.",
                    "risk_level": risk_level,
                }
        except Exception as e:
            print(f"⚠️ move correction error: {e}")

    # ==========================================================
    # 9️⃣  Clarification Resolver (pending multi-item object)
    # ==========================================================
    if pending_object:
        try:
            object_memories = find_object_memories(db, user_id, pending_object)
            if not object_memories:
                clear_pending_object(user_id)
            else:
                if "other" in user_lower and len(object_memories) > 1:
                    # ✅ FIX: "The other one" → pick the second-best candidate (index 1).
                    # Old code used object_memories[-1] which picks the WEAKEST match
                    # when there are 4+ memories. index[1] is always the second-best
                    # (object_memories is sorted confidence DESC by _memory_sort_key).
                    mem = object_memories[1]
                    increment_memory_confidence(user_id, mem)
                    clear_pending_object(user_id)
                    id_part = mem.get("identifier", "").strip()
                    label   = f"{id_part} {pending_object}".strip() if id_part else pending_object
                    verb    = object_verb(label)
                    loc_str = format_location_reply(label, mem.get("relation", "in"), mem["location"])
                    return {
                        "reply": f"Of course! 😊 Your {label} {verb} {loc_str}.",
                        "risk_level": risk_level,
                    }

                user_words = set(re.sub(r'[^\w\s]', '', user_lower).split())

                # ── Fix #2: Three-priority match order ────────────────────
                # Priority 1 — Exact full-identifier match in user reply
                # Priority 2 — ≥70% identifier token overlap (Fix #9 kept)
                # Priority 3 — Highest confidence + most recent (recency)
                # This prevents "the glasses" from randomly picking the wrong
                # one when the user hasn't specified a distinguishing word.

                # Pass 1: exact full identifier present in user reply
                matched_mem = None
                for mem in object_memories:
                    identifier = _normalize(mem.get("identifier", ""))
                    if identifier and identifier in user_lower:
                        matched_mem = mem
                        break

                # Pass 2: ≥70% token overlap
                if matched_mem is None:
                    for mem in object_memories:
                        identifier = _normalize(mem.get("identifier", ""))
                        id_words   = set(identifier.split()) if identifier else set()
                        if not id_words:
                            continue
                        overlap_pct = len(id_words.intersection(user_words)) / len(id_words)
                        if overlap_pct >= 0.70:
                            matched_mem = mem
                            break

                # Pass 3: recency + confidence fallback — only when user gave
                # no distinguishing info (e.g. just said "the glasses").
                # object_memories is already sorted confidence DESC, then
                # timestamp DESC by get_object_memories(), so [0] is best.
                if matched_mem is None and not user_words.difference(
                    {"the", "one", "that", "it", "wala", "wali", "wale"}
                ):
                    # User said something generic — pick the most recently
                    # confirmed / highest-confidence memory.
                    matched_mem = object_memories[0]

                if matched_mem is not None:
                    identifier = _normalize(matched_mem.get("identifier", ""))
                    increment_memory_confidence(user_id, matched_mem)
                    clear_pending_object(user_id)
                    loc_str = format_location_reply(
                        identifier, matched_mem.get("relation", "in"), matched_mem["location"]
                    )
                    label = f"{identifier} {pending_object}".strip() if identifier else pending_object
                    return {
                        "reply": f"Found it! 😊 Your {label} {object_verb(label)} {loc_str}.",
                        "risk_level": risk_level,
                    }
        except Exception as e:
            print(f"⚠️ clarification resolver error: {e}")

    # ==========================================================
    # 🗑️  FORGET / DELETE OBJECT MEMORY  ✅ NEW
    # ==========================================================
    forget_pattern = r"(?:forget|remove|delete|clear)\s+(?:my\s+)?(.+?)(?:\s+location|\s+memory)?"
    m_forget = re.search(forget_pattern, user_lower)
    if m_forget and any(kw in user_lower for kw in [
        "forget", "remove my", "delete my", "clear my",
        "bhool jao", "hata do", "delete karo",
    ]):
        try:
            obj_query = m_forget.group(1).strip()
            deleted   = delete_object_memory(user_id, obj_query)
            reasoning_used.append("memory_delete")
            reasoning_used.append("rule")
            if deleted:
                if lang in ["Hindi", "Hinglish"]:
                    return {"reply": f"ठीक है! 😊 मैंने आपके {obj_query} की जगह भूल गया। 💙", "risk_level": risk_level}
                return {"reply": f"Done! 😊 I've forgotten the stored location for your {obj_query}. 💙", "risk_level": risk_level}
            else:
                if lang in ["Hindi", "Hinglish"]:
                    return {"reply": f"मुझे आपके {obj_query} की कोई जगह याद नहीं थी। 😊", "risk_level": risk_level}
                return {"reply": f"I didn't have a stored location for your {obj_query} anyway. 😊", "risk_level": risk_level}
        except Exception as e:
            print(f"⚠️ delete_object_memory error: {e}")

    # ==========================================================
    # 🔟  WHERE IS MY <OBJECT>? — Bulletproof Retrieval
    #     Handles English + Hindi + Hinglish phrasings
    # ==========================================================
    where_patterns = [
        r"where(?:'s| is) (?:my|the) (.+?)(?:\?|$)",
        r"(?:mera|meri|mere|मेरा|मेरी) (.+?) (?:kahan|kaha|kahaan|कहाँ|कहां)(?:\?|$)",
        r"(?:kahan|kaha|kahaan|कहाँ|कहां) (?:hai|है) (?:mera|meri|mere|मेरा|मेरी) (.+?)(?:\?|$)",
        r"(?:find|dhundho|dhundo|ढूंढो) (?:my|mera|meri|mere) (.+?)(?:\?|$)",
        r"(?:mujhe|मुझे) (?:mera|meri|mere|मेरा|मेरी) (.+?) (?:chahiye|चाहिए)(?:\?|$)",
    ]

    matched_object = None
    for pattern in where_patterns:
        m = re.search(pattern, user_lower)
        if m:
            matched_object = m.group(1)
            break

    if matched_object:
        object_name     = _normalize(matched_object)
        object_memories = find_object_memories(db, user_id, object_name)

        if len(object_memories) > 1:
            try:
                set_pending_object(user_id, object_name)
            except Exception as e:
                print(f"⚠️ set_pending_object error: {e}")

            reasoning_used.append("memory_retrieval")
            reasoning_used.append("rule")
            if lang in ["Hindi", "Hinglish"]:
                msg = f"मुझे आपके कई {object_name} मिले! 😊\n"
                for mem in object_memories:
                    id_part  = mem.get("identifier", "").strip()
                    label    = f"{id_part} {object_name}".strip() if id_part else object_name
                    loc_str  = format_location_reply(label, mem.get("relation", "in"), mem["location"])
                    msg     += f"• आपका {label} {loc_str} है।\n"
                msg += "\nआप किसके बारे में जानना चाहते हैं?"
            else:
                msg = f"I found a few {object_name}s I'm keeping track of for you! 😊\n"
                for mem in object_memories:
                    id_part  = mem.get("identifier", "").strip()
                    label    = f"{id_part} {object_name}".strip() if id_part else object_name
                    verb     = object_verb(label)
                    loc_str  = format_location_reply(label, mem.get("relation", "in"), mem["location"])
                    msg     += f"• Your {label} {verb} {loc_str}.\n"
                msg += "\nWhich one were you looking for?"
            return {"reply": msg, "risk_level": risk_level, "reasoning": ", ".join(reasoning_used)}

        elif len(object_memories) == 1:
            mem = object_memories[0]
            try:
                increment_memory_confidence(user_id, mem)
            except Exception as e:
                print(f"⚠️ increment_memory_confidence error: {e}")

            reasoning_used.append("memory_retrieval")
            reasoning_used.append("rule")
            id_part      = _normalize(mem.get("identifier", ""))
            display_name = (
                f"{id_part} {object_name}".strip()
                if id_part and id_part != object_name
                else object_name
            )
            location  = mem.get("location", "there")
            relation  = mem.get("relation", "in")
            verb      = object_verb(display_name)
            loc_str   = format_location_reply(display_name, relation, location)

            if lang in ["Hindi", "Hinglish"]:
                return {
                    "reply": f"मिल गया! 😊 आपका {display_name} {loc_str} है। 💙",
                    "risk_level": risk_level,
                    "reasoning": ", ".join(reasoning_used),
                }
            return {
                "reply": f"Found it! 😊 Your {display_name} {verb} {loc_str}. 💙",
                "risk_level": risk_level,
                "reasoning": ", ".join(reasoning_used),
            }

        else:
            reasoning_used.append("memory_retrieval")
            reasoning_used.append("rule")
            # Nothing found — guide user to tell us
            if lang in ["Hindi", "Hinglish"]:
                reply_text = (
                    f"हम्म, मुझे आपके {object_name} की जगह अभी याद नहीं है। "
                    f"कोई बात नहीं! बताएं वो कहाँ है, मैं याद रख लूंगा। 😊"
                )
            elif risk_level == "High":
                reply_text = (
                    f"Hmm, I don't seem to have a record of where your {object_name} is. "
                    f"No worries at all! Just tell me where it is and I'll remember it for you. 😊"
                )
            else:
                reply_text = (
                    f"I don't have a record of where your {object_name} is yet. "
                    f"Just tell me where it is and I'll keep track of it for you! 😊"
                )
            return {"reply": reply_text, "risk_level": risk_level, "reasoning": ", ".join(reasoning_used)}

    # ==========================================================
    # 📋 LIST REMINDERS
    # ==========================================================
    list_triggers = [
        "what reminders", "list reminders", "mere reminders",
        "मेरे रिमाइंडर", "show reminders", "my reminders",
        "reminders dikhao", "reminders batao",
    ]
    if any(t in user_lower for t in list_triggers):
        try:
            reminders = get_user_reminders(user_id)
        except Exception as e:
            print(f"⚠️ get_user_reminders error: {e}")
            reminders = []

        if not reminders:
            if lang in ["Hindi", "Hinglish"]:
                return {"reply": "अभी आपका कोई रिमाइंडर नहीं है। 😊 क्या मैं एक सेट करूं?", "risk_level": risk_level}
            return {"reply": "You have no active reminders right now. 😊 Would you like to set one?", "risk_level": risk_level}

        reply_text = "आपके आने वाले रिमाइंडर! ⏰\n" if lang in ["Hindi", "Hinglish"] else "Here are your upcoming reminders! ⏰\n"
        IST = pytz.timezone("Asia/Kolkata")
        for r in reminders:
            # ✅ FIX: Check all three possible time fields; convert UTC timestamp to IST.
            raw_time = r.get("scheduled_time") or r.get("time") or r.get("time_text")
            if raw_time is None:
                display_time = "unknown time"
            elif hasattr(raw_time, "strftime"):
                # Firestore Timestamp — stored in UTC, convert to IST for display
                try:
                    display_time = raw_time.astimezone(IST).strftime("%I:%M %p")
                except Exception:
                    display_time = raw_time.strftime("%I:%M %p")
            else:
                display_time = str(raw_time)
            reply_text  += f"• {r['task']} at {display_time}\n"
        reply_text += "\nक्या आप कुछ बदलना चाहते हैं? 😊" if lang in ["Hindi", "Hinglish"] else "\nLet me know if you need to change anything! 😊"
        return {"reply": reply_text, "risk_level": risk_level}

    # ==========================================================
    # ⏰ NEXT REMINDER
    # ==========================================================
    next_triggers = ["next reminder", "अगला रिमाइंडर", "agla reminder", "next reminder kya hai"]
    if any(t in user_lower for t in next_triggers):
        try:
            next_reminder = get_next_reminder(user_id)
        except Exception as e:
            print(f"⚠️ get_next_reminder error: {e}")
            next_reminder = None

        if not next_reminder:
            if lang in ["Hindi", "Hinglish"]:
                return {"reply": "अभी आपका कोई आने वाला रिमाइंडर नहीं है। 😊 क्या मैं एक सेट करूं?", "risk_level": risk_level}
            return {"reply": "You have no upcoming reminders right now. 😊 Would you like me to set one?", "risk_level": risk_level}

        # ✅ FIX: Check all three time fields; convert UTC Firestore timestamp to IST.
        IST      = pytz.timezone("Asia/Kolkata")
        raw_time = next_reminder.get("scheduled_time") or next_reminder.get("time") or next_reminder.get("time_text")
        if raw_time is None:
            display_time = "unknown time"
        elif hasattr(raw_time, "astimezone"):
            try:
                display_time = raw_time.astimezone(IST).strftime("%I:%M %p")
            except Exception:
                display_time = raw_time.strftime("%I:%M %p")
        else:
            display_time = str(raw_time)
        if lang in ["Hindi", "Hinglish"]:
            return {
                "reply": f"आपका अगला रिमाइंडर '{next_reminder['task']}' का है, {display_time} बजे। मैं आपका ख्याल रखूंगा! 😊",
                "risk_level": risk_level,
            }
        return {
            "reply": f"Your next reminder is '{next_reminder['task']}' at {display_time}. I've got you covered! 😊",
            "risk_level": risk_level,
        }

    # ==========================================================
    # ❌ DELETE REMINDER
    # ==========================================================
    cancel_pattern = r"(?:cancel|delete|remove|hata|hatao) (?:my )?(?:reminder )?(?:to |for )?(.+)"
    match_cancel   = re.search(cancel_pattern, user_lower)

    if match_cancel:
        try:
            task_text = match_cancel.group(1).strip()
            if any(w in task_text for w in ["last", "pichla", "pichli"]):
                deleted = delete_last_reminder(user_id)
                if deleted:
                    if lang in ["Hindi", "Hinglish"]:
                        return {"reply": "हो गया! 😊 आपका आखिरी रिमाइंडर हटा दिया है।", "risk_level": risk_level}
                    return {"reply": "Done! 😊 I've cancelled your last reminder.", "risk_level": risk_level}
            # ✅ FIX: delete_reminder_by_task now returns the actual stored task name
            # (or None if not found) so the reply echoes the real name, not the user's phrasing.
            matched_name = delete_reminder_by_task(user_id, task_text)
            if matched_name:
                if lang in ["Hindi", "Hinglish"]:
                    return {"reply": f"हो गया! 😊 '{matched_name}' का रिमाइंडर हटा दिया है।", "risk_level": risk_level}
                return {"reply": f"Done! 😊 I've removed the reminder for '{matched_name}'.", "risk_level": risk_level}
            else:
                if lang in ["Hindi", "Hinglish"]:
                    return {"reply": "हम्म, वो रिमाइंडर नहीं मिला। क्या आप नाम जाँच कर फिर से बताएंगे? 😊", "risk_level": risk_level}
                return {"reply": "Hmm, I couldn't find that reminder. Could you check the name and try again? 😊", "risk_level": risk_level}
        except Exception as e:
            print(f"⚠️ delete reminder error: {e}")

    # ==========================================================
    # 🗑 CLEAR ALL REMINDERS
    # ==========================================================
    clear_triggers = [
        "clear all reminders", "सभी रिमाइंडर हटाओ",
        "saare reminders hatao", "delete all reminders", "remove all reminders",
    ]
    if any(t in user_lower for t in clear_triggers):
        try:
            clear_all_reminders(user_id)
        except Exception as e:
            print(f"⚠️ clear_all_reminders error: {e}")
        if lang in ["Hindi", "Hinglish"]:
            return {"reply": "हो गया! 😊 आपके सभी रिमाइंडर हटा दिए हैं।", "risk_level": risk_level}
        return {"reply": "All done! 😊 All your reminders have been cleared.", "risk_level": risk_level}

    # ==========================================================
    # ❓ /help COMMAND
    # ==========================================================
    help_triggers = ["/help", "help", "सहायता", "madad", "madat", "sahayata"]
    if user_lower.strip() in help_triggers:
        if lang in ["Hindi", "Hinglish"]:
            help_text = (
                "मैं आपकी इन कामों में मदद कर सकता हूँ! 😊\n\n"
                "⏰ रिमाइंडर\n"
                "  • रिमाइंडर सेट करें → 'मुझे 9 बजे दवाई लेनी है याद दिलाना'\n"
                "  • रिमाइंडर देखें → 'मेरे रिमाइंडर क्या हैं?'\n"
                "  • अगला रिमाइंडर → 'अगला रिमाइंडर क्या है?'\n"
                "  • रिमाइंडर हटाएं → 'दवाई का रिमाइंडर हटाओ'\n"
                "  • सब हटाएं → 'सभी रिमाइंडर हटाओ'\n\n"
                "📍 चीज़ ढूंढें\n"
                "  • 'मेरा चश्मा डाइनिंग टेबल पर है'\n"
                "  • 'मेरा बटुआ कहाँ है?'\n\n"
                "🧠 यादें\n"
                "  • परिवार के नाम बताएं → 'मेरी बेटी का नाम प्रिया है'\n"
                "  • मैं आपकी ज़रूरी बातें याद रखता हूँ!\n\n"
                "💬 बातचीत\n"
                "  • जब चाहें बात करें — मैं हमेशा आपके साथ हूँ! 💙\n\n"
                "मैं हिंदी, इंग्लिश और Hinglish में बात कर सकता हूँ। 🌟"
            )
        else:
            help_text = (
                "Here's what I can do for you! 😊\n\n"
                "⏰ Reminders\n"
                "  • Set a reminder → 'Remind me to take medicine at 9am'\n"
                "  • In Hindi/Hinglish → 'Mujhe 9 baje dawa leni hai yaad dilana'\n"
                "  • View reminders → 'What are my reminders?'\n"
                "  • Next reminder → 'What is my next reminder?'\n"
                "  • Cancel reminder → 'Cancel reminder to take medicine'\n"
                "  • Clear all → 'Clear all reminders'\n\n"
                "📍 Object Finder (Remember where you kept things)\n"
                "  • 'My glasses are on the dining table'\n"
                "  • 'Where is my wallet?'\n\n"
                "🧠 Memory Assistant\n"
                "  • Tell me family names → 'My daughter's name is Priya'\n"
                "  • I remember important facts about you!\n\n"
                "💬 General Chat\n"
                "  • Talk to me anytime — I am always here for you!\n\n"
                "I support English, Hindi, and Hinglish. 🌟\n"
                "Type 'who are you' to learn more about me."
            )
        return {"reply": help_text, "risk_level": risk_level}

    # ==========================================================
    # 🤖 SELF-AWARENESS — What/Who am I?
    # ==========================================================
    self_aware_triggers = [
        "who are you", "what are you", "what can you do",
        "tell me about yourself", "what is your purpose",
        "aap kaun ho", "aap kya kar sakte ho", "tumhara kaam kya hai",
        "kya kar sakte ho", "kya ho tum", "aap kon ho", "memoir kya hai",
    ]
    if any(trigger in user_lower for trigger in self_aware_triggers):
        name = ""
        if profile_text:
            name_lines = [l for l in profile_text.splitlines() if "Name:" in l]
            if name_lines:
                name = name_lines[0].replace("- Name:", "").strip().split()[0]

        if lang in ["Hindi", "Hinglish"]:
            about_text = (
                f"नमस्ते{' ' + name + '!' if name else '!'} मैं Memoir AI हूँ — आपका व्यक्तिगत स्मृति सहायक। 💙\n\n"
                "मैं इन तरीकों से आपकी मदद करता हूँ:\n\n"
                "🧠 आपकी रखी चीज़ें याद रखना।\n"
                "⏰ दवाई, अपॉइंटमेंट और रोज़ के काम के रिमाइंडर सेट करना।\n"
                "💾 ज़रूरी यादें सुरक्षित रखना — जैसे परिवार के नाम।\n"
                "🩺 आपकी याददाश्त का ख्याल रखना और सहायता देना।\n"
                "😊 और सबसे ज़रूरी — हमेशा आपके साथ रहना! 💙\n\n"
                "सब कुछ देखने के लिए /help टाइप करें। 🌟"
            )
        else:
            about_text = (
                f"Hi{' ' + name + '!' if name else '!'} I am Memoir AI — your personal memory companion. 💙\n\n"
                "I was made to help elderly users like you live more comfortably. Here is how I support you:\n\n"
                "🧠 I help you remember where you kept your belongings.\n"
                "⏰ I set reminders for medicines, appointments, and daily tasks.\n"
                "💾 I store important memories — like family names — so you never lose them.\n"
                "🩺 I keep track of your memory health and gently adapt my support to your needs.\n"
                "😊 And most importantly — I am always here to chat and support you, anytime!\n\n"
                "Type /help to see everything you can ask me. 🌟"
            )
        return {"reply": about_text, "risk_level": risk_level}

    # ==========================================================
    # 🤖 GREETING INTERCEPT
    # ==========================================================
    greetings = [
        "hello", "hi", "hey", "hii", "helo", "hallo",
        "namaste", "namaskar", "नमस्ते", "नमस्कार",
        "good morning", "good evening", "good afternoon", "good night", "howdy",
    ]
    is_greeting = any(
        user_lower.strip("! ,.") == g or user_lower.strip("! ,.").startswith(g)
        for g in greetings
    )

    if is_greeting:
        name = ""
        if profile_text:
            name_lines = [l for l in profile_text.splitlines() if "Name:" in l]
            if name_lines:
                name = name_lines[0].replace("- Name:", "").strip().split()[0]

        # ✅ FIX: Use IST time, not server UTC. Render servers run UTC so
        # datetime.now().hour was giving the wrong time-of-day greeting.
        IST  = pytz.timezone("Asia/Kolkata")
        hour = datetime.now(IST).hour
        if lang in ["Hindi", "Hinglish"]:
            time_greet = "सुप्रभात" if hour < 12 else ("नमस्ते" if hour < 17 else "शुभ संध्या")
            reply_text = (
                f"{time_greet}, {name}! 😊 आपसे मिलकर बहुत अच्छा लगा! मैं आपकी क्या सेवा कर सकता हूँ? (/help टाइप करें)"
                if name else
                f"{time_greet}! 😊 आपसे मिलकर बहुत अच्छा लगा! मैं आपकी क्या सेवा कर सकता हूँ? (/help टाइप करें)"
            )
        else:
            time_greet = "Good morning" if hour < 12 else ("Good afternoon" if hour < 17 else "Good evening")
            reply_text = (
                f"{time_greet}, {name}! 😊 It's so lovely to hear from you! How can I help you today? (Type /help to see what I can do!)"
                if name else
                f"{time_greet}! 😊 It's wonderful to hear from you! How can I help you today? (Type /help to see what I can do!)"
            )
        return {"reply": reply_text, "risk_level": risk_level}

    # ==========================================================
    # 🤖 GROQ LLM — Primary Intelligence
    # Rules above handle structured intents (reminders, object lookup).
    # Everything else goes here. LLM always receives full memory context
    # so it acts as the brain, not a fallback.
    # ==========================================================
    history = get_conversation_history(user_id, limit=3)

    try:
        long_term_memories = get_all_memories(user_id)
    except Exception as e:
        print(f"⚠️ get_all_memories error: {e}")
        long_term_memories = []

    # Track what context layers the LLM will use
    reasoning_used.append("llm")
    if long_term_memories:
        reasoning_used.append("memory")
    if history:
        reasoning_used.append("conversation_history")
    if risk_level != "Low":
        reasoning_used.append(f"risk_adaptation({risk_level})")

    system_prompt = build_system_prompt(risk_level)

    messages = [
        {"role": "system", "content": system_prompt},
        {
            "role": "system",
            "content": (
                f"User is speaking in {lang}. Always reply in the same language.\n"
                "If Hindi: use natural, warm Hindi (not overly formal). "
                "If Hinglish: mix Hindi and English naturally as Indian speakers do. "
                "If English: reply in friendly English. "
                "Keep the tone caring, like a family member."
            ),
        },
    ]

    if user_context:
        messages.append({"role": "system", "content": user_context})

    if profile_text:
        messages.append({
            "role": "system",
            "content": (
                f"User Information:\n{profile_text}\n"
                "Use this information naturally. Only mention location/age if directly asked.\n"
                "NEVER repeat the same sentence twice."
            ),
        })

    messages.extend(history)

    if long_term_memories:
        authoritative_memory = "Important known facts about the user:\n"
        for mem in long_term_memories:
            authoritative_memory += f"- {mem}\n"
        authoritative_memory += "\nAlways treat these facts as correct and up-to-date."
        messages.append({"role": "assistant", "content": authoritative_memory})

    if profile_text:
        name_lines = [l for l in profile_text.splitlines() if "Name:" in l]
        if name_lines:
            uname = name_lines[0].replace("- Name:", "").strip()
            messages.append({
                "role": "system",
                "content": (
                    f"The user's name is {uname}. If they say hello/hi, greet them by name warmly. "
                    "Only mention their location or age if they ask about it."
                ),
            })

    messages.append({"role": "user", "content": user_message})

    try:
        raw_reply = call_groq(messages, temperature=0.7, max_tokens=256)
        if not raw_reply:
            raise RuntimeError("Empty response from Groq.")
    except RuntimeError as e:
        print(f"⚠️ Groq error: {e}")
        if lang in ["Hindi", "Hinglish"]:
            return {
                "reply": "ओह नहीं, अभी कनेक्शन में थोड़ी दिक्कत है। 😔 कृपया थोड़ी देर बाद फिर कोशिश करें!",
                "risk_level": risk_level,
                "reasoning": "llm_error, rule_fallback",
            }
        return {
            "reply": "Oh no, I'm having a little trouble connecting right now. 😔 Please try again in a moment!",
            "risk_level": risk_level,
            "reasoning": "llm_error, rule_fallback",
        }

    reply = adapt_response_by_risk(raw_reply, risk_level)

    # ==========================================================
    # 💾 Store Chat History
    # NOTE: Flutter's chatbot_service.dart also writes to Firestore.
    # The backend write here is the authoritative record (assistant_reply key).
    # Flutter write is kept for offline resilience — both use "assistant_reply".
    # Fix #5: Use centralized save_chat_message to prevent duplicate writes.
    # ==========================================================
    save_chat_message(db, user_id, user_message, reply, risk_level)

    return {
        "reply":     reply,
        "risk_level": risk_level,
        "reasoning": ", ".join(reasoning_used),
    }