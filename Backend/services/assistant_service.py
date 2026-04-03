import requests
import os
import re
import joblib
import numpy as np
from datetime import datetime, timedelta, timezone
from dateutil import parser as date_parser
import tzlocal

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
# 🔑 GROQ API CONFIG (replaces local LLaMA model)
# =========================================================

GROQ_API_KEY = os.getenv("GROQ_API_KEY") 
GROQ_URL     = "https://api.groq.com/openai/v1/chat/completions"
GROQ_MODEL   = "llama-3.3-70b-versatile"

from services.assistant_service import validate_groq_key
def validate_groq_key():
    """Call at app startup to catch missing API key early."""
    if not GROQ_API_KEY:
        raise EnvironmentError(
            "GROQ_API_KEY is not set. Add it to your Render environment variables."
        )
    print("[OK] GROQ_API_KEY loaded successfully.")


def call_groq(messages, temperature=0.7, max_tokens=256):
    """
    Send a chat completion request to Groq and return the reply text.
    Raises RuntimeError on non-200 responses so callers can handle gracefully.
    """
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
    # FIX 3: Reduced timeout from 30 → 10 for faster failure & better UX
    try:
        response = requests.post(GROQ_URL, headers=headers, json=payload, timeout=10)
    except requests.exceptions.Timeout:
        raise RuntimeError("Groq request timed out. Please try again.")
    except requests.exceptions.ConnectionError:
        raise RuntimeError("Could not reach Groq API. Check your internet connection.")

    if response.status_code == 200:
        # FIX 4: Debug log on successful response
        print("[Groq Response OK]")
        # FIX 2: Safe response parsing — prevents crashes on unexpected structure
        data = response.json()
        return data.get("choices", [{}])[0].get("message", {}).get("content", "No response")
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

def predict_dementia(questionnaire_data):
    if dementia_model is None:
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
        print("❌ Chatbot prediction error:", e)
        return None


def get_latest_risk_level(user_id):
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
    return "Low"


# =========================================================
# 🗓 NATURAL LANGUAGE REMINDER PARSER
# Supports: English, Hindi, Hinglish
# =========================================================

DATE_KEYWORDS = [
    "jan", "feb", "mar", "apr", "may", "jun",
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

    if not any(
        word in text
        for word in ["remind", "reminder", "appointment", "meeting", "doctor"]
    ) and not is_hindi:
        return None

    # Normalize common variations
    text = text.replace("bje", "baje").replace("baja", "baje")
    text = text.replace("subha", "subah").replace("sham", "shaam")

    # Fix no-space between digit and month ("26march" → "26 march")
    text = re.sub(
        r'(\d)(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec'
        r'|january|february|march|april|june|july|august'
        r'|september|october|november|december)',
        r'\1 \2',
        text,
    )

    # ⏰ Extract time
    text       = re.sub(r'(\d)(baje)', r'\1 \2', text)
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
        hour   = int(time_match.group(1))
        minute = int(time_match.group(2).replace(":", "")) if time_match.group(2) else 0
        period = time_match.group(3) if len(time_match.groups()) >= 3 else time_match.group(2)

        if not period:
            period = "am" if "subah" in text else "pm"

        if period in ("pm", "baje") and hour != 12:
            hour += 12
        if period == "am" and hour == 12:
            hour = 0

    # 📅 Extract date
    local_tz        = tzlocal.get_localzone()
    now             = datetime.now(local_tz)
    has_specific_date = any(word in text for word in DATE_KEYWORDS)

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

    # 🕐 Combine date + time
    hour   = max(0, min(23, hour))
    minute = max(0, min(59, minute))

    try:
        reminder_time = datetime(date.year, date.month, date.day, hour, minute)
    except (ValueError, OverflowError):
        reminder_time = (now.replace(tzinfo=None) + timedelta(hours=1)).replace(
            second=0, microsecond=0
        )

    now_naive = now.replace(tzinfo=None)
    if reminder_time < now_naive:
        if has_specific_date:
            reminder_time = reminder_time.replace(year=now.year + 1)
        else:
            reminder_time += timedelta(days=1)

    # 🧠 Clean task text
    task = text
    task = re.sub(
        r'(set a reminder of|set a reminder to|set a reminder|remind me to|remind me about|remind me)',
        '', task,
    )
    task = re.sub(r'(lena hai|leni hai|khana hai|pina hai|yaad dilana|yaad dila)', '', task)
    task = re.sub(r'\b(mujhe|mujko|aaj|kal|parso)\b', '', task)
    task = re.sub(r'\b(of|at|on|for|to|about)\b', '', task)
    task = re.sub(r'\d{1,2}(:\d{2})?\s*(am|pm|baje)', '', task)
    task = task.replace("subah", "").replace("shaam", "").replace("raat", "")
    task = task.replace("tomorrow", "").replace("today", "").replace("aaj", "")
    task = task.replace("kal", "").replace("parso", "")
    for kw in DATE_KEYWORDS:
        task = re.sub(r'\b' + kw + r'\b', '', task)
    task = re.sub(r'\b\d{1,2}(st|nd|rd|th)?\b', '', task)
    task = " ".join(task.split()).capitalize()

    # 🕒 Build display string
    local_time   = reminder_time.replace(tzinfo=local_tz)
    reminder_day = datetime(reminder_time.year, reminder_time.month, reminder_time.day)
    today_day    = datetime(now.year, now.month, now.day)

    if reminder_day == today_day:
        day_label = "Today"
    elif reminder_day == today_day + timedelta(days=1):
        day_label = "Tomorrow"
    else:
        day_label = f"{local_time.strftime('%b')} {local_time.day}"

    time_label = local_time.strftime("%I:%M %p")
    display    = f"{day_label} • {time_label}"

    return {
        "task":         task if task else "Reminder",
        "time":         reminder_time,
        "time_display": display,
    }


# =========================================================
# 🧠 SHORT-TERM MEMORY (PENDING COMPLETION STATE)
# =========================================================

def set_pending_completion(user_id, reminder_id):
    db = get_firestore_client()
    db.collection("users").document(user_id).collection("assistant_state") \
        .document("pending_completion").set({"reminder_id": reminder_id})


def get_pending_completion(user_id):
    db  = get_firestore_client()
    doc = db.collection("users").document(user_id).collection("assistant_state") \
        .document("pending_completion").get()
    return doc.to_dict().get("reminder_id") if doc.exists else None


def clear_pending_completion(user_id):
    db = get_firestore_client()
    db.collection("users").document(user_id).collection("assistant_state") \
        .document("pending_completion").delete()


def get_conversation_history(user_id, limit=3):
    db        = get_firestore_client()
    chats_ref = db.collection("users").document(user_id).collection("chats")
    try:
        docs = chats_ref.stream()
    except Exception as e:
        print("⚠️ Error fetching chats:", e)
        return []

    chat_list = []
    for doc in docs:
        data            = doc.to_dict()
        user_message    = data.get("user_message")
        assistant_reply = data.get("assistant_reply")
        timestamp       = data.get("timestamp")
        if not user_message or not assistant_reply:
            continue
        chat_list.append({
            "user_message":    user_message,
            "assistant_reply": assistant_reply,
            "timestamp":       timestamp,
        })

    def safe_timestamp(chat):
        ts = chat.get("timestamp")
        try:
            if ts:
                return ts.timestamp()
        except Exception:
            pass
        return 0

    chat_list.sort(key=safe_timestamp)
    chat_list = chat_list[-limit:]

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
        (r"my daughter's name is (.+)", "daughter", "name"),
        (r"my son's name is (.+)",      "son",      "name"),
        (r"my wife's name is (.+)",     "wife",     "name"),
        (r"my husband's name is (.+)",  "husband",  "name"),
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
    db         = get_firestore_client()
    memory_ref = db.collection("users").document(user_id).collection("long_term_memory")
    relation   = memory_data["relation"]
    attribute  = memory_data["attribute"]
    value      = memory_data["value"]

    for doc in memory_ref.stream():
        data = doc.to_dict()
        if data.get("relation") == relation and data.get("attribute") == attribute:
            doc.reference.update({"value": value, "updated_at": firestore.SERVER_TIMESTAMP})
            for chat_doc in (
                db.collection("users").document(user_id).collection("chats").stream()
            ):
                chat_doc.reference.delete()
            print("🧠 Memory updated and old chat history cleared.")
            return

    memory_ref.add({
        "relation":   relation,
        "attribute":  attribute,
        "value":      value,
        "created_at": firestore.SERVER_TIMESTAMP,
    })
    print("🧠 New structured memory stored.")


def get_long_term_memory(user_id):
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


# =========================================================
# 🧠 SYSTEM PROMPT BUILDER
# =========================================================

def build_system_prompt(risk_level):
    base = """
You are Memoir AI, a calm and supportive assistant for elderly users.

Rules:
- Keep responses SHORT.
- Maximum 2 sentences.
- Use simple language.
- Avoid long explanations.
"""
    if risk_level == "Medium":
        base += """
The user may have mild memory difficulties.
Use simple language.
Repeat important details gently.
"""
    elif risk_level == "High":
        base += """
The user has high dementia risk.
Use very short sentences.
Be extremely clear.
Repeat key information.
Encourage reminders.
Be calm and reassuring.
Encourage daily routines.
Avoid complex explanations.
"""
    base += """
Important Rule:
If there is any contradiction between earlier conversation and the important known facts about the user,
always trust the important known facts as the most up-to-date and correct information.
"""
    base += """
IMPORTANT:
Always reply in the SAME language as the user.

- If user writes in Hindi → reply in Hindi
- If user writes in Hinglish → reply in Hinglish
- If user writes in English → reply in English

Keep language simple and natural.
Do NOT translate unless needed.
"""
    base += """
Personalization Rules:
- When user says hello/hi, greet them by name warmly. Example: "Hello Bhuwan! How can I help you today?"
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
    db  = get_firestore_client()
    doc = db.collection("users").document(user_id).get()
    if not doc.exists:
        return None
    return doc.to_dict().get("profile")


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
    hinglish_words = ["mujhe", "hai", "karna", "kal", "aaj", "dawa", "pani"]
    if any(word in text.lower() for word in hinglish_words):
        return "Hinglish"
    return "English"


# =========================================================
# 🚀 MAIN CHAT FUNCTION
# =========================================================

def generate_response(user_id, user_message, flutter_profile_text=""):

    db         = get_firestore_client()
    lang       = detect_language(user_message)
    user_lower = user_message.lower().strip()
    risk_level = get_latest_risk_level(user_id)

    # ==========================================================
    # 🔥 NATURAL LANGUAGE REMINDER
    # ==========================================================
    parsed = parse_natural_reminder(user_message)

    if parsed:
        create_reminder(
            user_id=user_id,
            task=parsed["task"],
            time_text=parsed["time"],
            time_display=parsed["time_display"],
            source="assistant",
            recurring_type="none",
            user_timezone=str(tzlocal.get_localzone()),
        )
        if lang in ["Hindi", "Hinglish"]:
            reply_text = f"ठीक है, मैं आपको {parsed['time_display']} पर {parsed['task']} की याद दिलाऊंगा।"
        else:
            reply_text = f"Okay, I will remind you about {parsed['task']} at {parsed['time_display']}."
        return {"reply": reply_text, "risk_level": risk_level}

    # ==========================================================
    # 1️⃣ Extract & Store Memory
    # ==========================================================
    memory_data = extract_memory(user_message)
    if memory_data:
        store_memory(user_id, memory_data)

    # ==========================================================
    # 2️⃣ Risk Level
    # ==========================================================
    risk_level = get_latest_risk_level(user_id)

    # ==========================================================
    # 3️⃣ USER PROFILE
    # ==========================================================
    user_doc     = db.collection("users").document(user_id).get()
    user_context = ""

    if user_doc.exists:
        user_data    = user_doc.to_dict()
        user_context = f"""
User Profile:
- Age: {user_data.get('AGE')}
- Gender: {user_data.get('GENDER')}
- Education Years: {user_data.get('YEARS_OF_EDUCATION')}
- SES: {user_data.get('SES')}
- Education Level: {user_data.get('EDUCATION')}
- MMSE Score: {user_data.get('MMSE')}
- Risk Level: {risk_level}
"""

    # ==========================================================
    # 4️⃣ EXTRA PROFILE — Flutter profile takes priority
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
    # 5️⃣ REMINDER COMPLETION LOGIC
    # ==========================================================
    pending_completion = get_pending_completion(user_id)

    if pending_completion:
        if user_lower in ["yes", "yes please", "mark it done", "confirm"]:
            if risk_level == "High" and not get_double_confirm_state(user_id):
                set_double_confirm_state(user_id, pending_completion)
                return {
                    "reply": "Just to make sure — do you really want me to mark this reminder as completed?",
                    "risk_level": risk_level,
                }
            complete_reminder(user_id, pending_completion)
            clear_pending_completion(user_id)
            clear_double_confirm_state(user_id)
            if risk_level == "High":
                reply_text = "Good job.\nI have marked it as completed.\nKeeping routines helps your memory."
            else:
                reply_text = "Okay. I've marked the reminder as completed."
            return {"reply": reply_text, "risk_level": risk_level}

        if user_lower in ["no", "cancel"]:
            clear_pending_completion(user_id)
            clear_double_confirm_state(user_id)
            return {"reply": "Okay, I will not mark it as completed.", "risk_level": risk_level}

        clear_pending_completion(user_id)
        clear_double_confirm_state(user_id)

    # ==========================================================
    # 6️⃣ Completion Intent Detection
    # ==========================================================
    completion_pattern = r"(?:i (?:have )?(?:taken|took|did|finished|completed)|done with) (.+)"
    match_completion   = re.search(completion_pattern, user_lower)

    if match_completion:
        task_text = match_completion.group(1).strip()
        reminders = get_user_reminders(user_id)
        for r in reminders:
            if any(word in r["task"].lower() for word in task_text.split()):
                set_pending_completion(user_id, r["id"])
                return {
                    "reply": f"I found the reminder '{r['task']}'. Do you want me to mark it as completed?",
                    "risk_level": risk_level,
                }

    # ==========================================================
    # 7️⃣ Pending Object State
    # ==========================================================
    pending_object = get_pending_object(user_id)

    # ==========================================================
    # 8️⃣ Smart Move Correction
    # ==========================================================
    move_pattern = r"moved (?:it|my .+?) to the (.+)"
    match_move   = re.search(move_pattern, user_lower)

    if match_move and pending_object:
        new_location    = match_move.group(1).strip()
        object_memories = get_object_memories(user_id, pending_object)
        if object_memories:
            for mem in object_memories:
                if mem["identifier"].lower() in user_lower:
                    update_object_location(user_id, pending_object, mem["identifier"], new_location)
                    clear_pending_object(user_id)
                    return {
                        "reply": f"Okay. I've updated the location. Your {mem['identifier']} {pending_object} is now in the {new_location}.",
                        "risk_level": risk_level,
                    }
            mem = object_memories[0]
            update_object_location(user_id, pending_object, mem["identifier"], new_location)
            clear_pending_object(user_id)
            return {
                "reply": f"Okay. I've updated the location. Your {mem['identifier']} {pending_object} is now in the {new_location}.",
                "risk_level": risk_level,
            }

    # ==========================================================
    # 9️⃣ Clarification Resolver
    # ==========================================================
    if pending_object:
        object_memories = get_object_memories(user_id, pending_object)
        if not object_memories:
            clear_pending_object(user_id)
        else:
            if "other" in user_lower and len(object_memories) > 1:
                mem = object_memories[-1]
                increment_memory_confidence(user_id, mem)
                clear_pending_object(user_id)
                return {
                    "reply": f"Your {mem['identifier']} {pending_object} is in the {mem['location']}.",
                    "risk_level": risk_level,
                }
            for mem in object_memories:
                identifier = mem["identifier"].lower()
                if identifier in user_lower:
                    increment_memory_confidence(user_id, mem)
                    clear_pending_object(user_id)
                    return {
                        "reply": f"Your {identifier} {pending_object} is in the {mem['location']}.",
                        "risk_level": risk_level,
                    }

    # ==========================================================
    # 🔟 Ambiguity Detection
    # ==========================================================
    match = re.search(r"where is (?:my|the) (.+)", user_lower)

    if match:
        object_name     = re.sub(r"[^\w\s]", "", match.group(1)).strip()
        object_memories = get_object_memories(user_id, object_name)

        if len(object_memories) > 1:
            set_pending_object(user_id, object_name)
            clarification_message = f"You have multiple {object_name}s:\n"
            for mem in object_memories:
                clarification_message += f"- {mem['identifier']} {object_name} is in the {mem['location']}.\n"
            clarification_message += "Which one are you referring to?"
            return {"reply": clarification_message, "risk_level": risk_level}

        elif len(object_memories) == 1:
            mem = object_memories[0]
            increment_memory_confidence(user_id, mem)
            return {
                "reply": f"Your {mem['identifier']} {object_name} is in the {mem['location']}.",
                "risk_level": risk_level,
            }
        else:
            if risk_level == "High":
                reply_text = f"I don't know where your {object_name} is.\nYou can tell me. I will remember."
            else:
                reply_text = f"I don't have any record of where your {object_name} is. You can tell me and I'll remember it."
            return {"reply": reply_text, "risk_level": risk_level}

    # ==========================================================
    # 📋 LIST REMINDERS
    # ==========================================================
    if "what reminders" in user_lower or "list reminders" in user_lower:
        reminders = get_user_reminders(user_id)
        if not reminders:
            return {"reply": "You don't have any active reminders.", "risk_level": risk_level}
        reply_text = "Here are your reminders:\n"
        for r in reminders:
            raw_time     = r.get("time") or r.get("time_text")
            display_time = raw_time.strftime("%I:%M %p") if hasattr(raw_time, "strftime") else str(raw_time)
            reply_text  += f"- {r['task']} at {display_time}\n"
        return {"reply": reply_text, "risk_level": risk_level}

    # ==========================================================
    # ⏰ NEXT REMINDER
    # ==========================================================
    if "next reminder" in user_lower:
        next_reminder = get_next_reminder(user_id)
        if not next_reminder:
            return {"reply": "You don't have any upcoming reminders.", "risk_level": risk_level}
        raw_time     = next_reminder.get("time") or next_reminder.get("time_text")
        display_time = raw_time.strftime("%I:%M %p") if hasattr(raw_time, "strftime") else str(raw_time)
        return {
            "reply": f"Your next reminder is {next_reminder['task']} at {display_time}.",
            "risk_level": risk_level,
        }

    # ==========================================================
    # ❌ DELETE REMINDER
    # ==========================================================
    cancel_pattern = r"(?:cancel|delete|remove) (?:my )?(?:reminder )?(?:to )?(.+)"
    match_cancel   = re.search(cancel_pattern, user_lower)

    if match_cancel:
        task_text = match_cancel.group(1).strip()
        if "last" in task_text:
            deleted = delete_last_reminder(user_id)
            if deleted:
                return {"reply": "Okay. I've cancelled your last reminder.", "risk_level": risk_level}
        deleted = delete_reminder_by_task(user_id, task_text)
        if deleted:
            return {"reply": f"Okay. I've removed the reminder for {task_text}.", "risk_level": risk_level}
        else:
            return {"reply": "I couldn't find that reminder.", "risk_level": risk_level}

    # ==========================================================
    # 🗑 CLEAR ALL REMINDERS
    # ==========================================================
    if "clear all reminders" in user_lower:
        clear_all_reminders(user_id)
        return {"reply": "All your reminders have been cleared.", "risk_level": risk_level}

    # ==========================================================
    # 🤖 GREETING INTERCEPT
    # ==========================================================
    greetings = [
        "hello", "hi", "hey", "hii", "helo", "hallo",
        "namaste", "namaskar",
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

        hour = datetime.now().hour
        if hour < 12:
            time_greet = "Good morning"
        elif hour < 17:
            time_greet = "Good afternoon"
        else:
            time_greet = "Good evening"

        reply_text = f"{time_greet}, {name}! 😊 How can I help you today?" if name \
                     else f"{time_greet}! 😊 How can I help you today?"
        return {"reply": reply_text, "risk_level": risk_level}

    # ==========================================================
    # 🤖 GROQ LLM FALLBACK (replaces llm.create_chat_completion)
    # ==========================================================
    history            = get_conversation_history(user_id, limit=3)
    long_term_memories = get_all_memories(user_id)
    system_prompt      = build_system_prompt(risk_level)

    messages = [
        {"role": "system", "content": system_prompt},
        {"role": "system", "content": f"User is speaking in {lang}. Speak like a friendly assistant in that language."},
    ]

    if user_context:
        messages.append({"role": "system", "content": user_context})

    if profile_text:
        name_lines = [l for l in profile_text.splitlines() if "Name:" in l]
        messages.append({
            "role": "system",
            "content": f"User Information:\n{profile_text}\nUse this information naturally. Only mention location/age if directly asked.\nNEVER repeat the same sentence twice.",
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
                "content": f"The user's name is {uname}. If they say hello/hi, greet them by name warmly. Only mention their location or age if they ask about it.",
            })

    messages.append({"role": "user", "content": user_message})

    try:
        raw_reply = call_groq(messages, temperature=0.7, max_tokens=256)
    except RuntimeError as e:
        return {"reply": str(e), "risk_level": risk_level}

    reply = adapt_response_by_risk(raw_reply, risk_level)

    # ==========================================================
    # 💾 Store Chat History
    # ==========================================================
    db.collection("users").document(user_id).collection("chats").add({
        "user_message":    user_message,
        "assistant_reply": reply,
        "risk_level":      risk_level,
        "timestamp":       firestore.SERVER_TIMESTAMP,
    })

    return {"reply": reply, "risk_level": risk_level}