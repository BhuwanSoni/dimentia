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

def get_stored_items(user_id):
    """
    Return all object memories for a user as a list of dicts:
    [{ object_name, identifier, location, confidence }, ...]
    Used by the Flutter 'Find my item' bottom sheet.
    """
    db    = get_firestore_client()
    docs  = (
        db.collection("users")
          .document(user_id)
          .collection("object_memories")
          .stream()
    )
    items = []
    for doc in docs:
        data = doc.to_dict()
        if data:
            items.append({
                "object_name": data.get("object_name") or data.get("identifier", ""),
                "identifier":  data.get("identifier", ""),
                "location":    data.get("location", "Unknown"),
                "confidence":  data.get("confidence", 1),
            })
    return items


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

    # 🕐 Combine date + time (always IST-aware so Render UTC server doesn't shift it)
    IST = pytz.timezone("Asia/Kolkata")
    hour   = max(0, min(23, hour))
    minute = max(0, min(59, minute))

    try:
        # Build naive first, then localize to IST — never treat as UTC
        naive_time    = datetime(date.year, date.month, date.day, hour, minute)
        reminder_time = IST.localize(naive_time)          # ✅ IST-aware
    except (ValueError, OverflowError):
        reminder_time = IST.localize(
            (now.replace(tzinfo=None) + timedelta(hours=1)).replace(second=0, microsecond=0)
        )

    now_ist = datetime.now(IST)
    if reminder_time < now_ist:
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

    # 🕒 Build display string (reminder_time is now IST-aware)
    ist_time     = reminder_time                          # already IST-aware
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
- Maximum 2–3 sentences per reply.
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
IMPORTANT — Language Rules:
Always reply in the SAME language as the user.

- If user writes in Hindi → reply in Hindi
- If user writes in Hinglish → reply in Hinglish
- If user writes in English → reply in English

Keep language simple and natural. Do NOT translate unless needed.
"""
    base += """
Personalization Rules:
- When user says hello/hi, greet them by name warmly. Example: "Hello Bhuwan! 😊 So lovely to see you! How can I help you today?"
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
# 🔍 FUZZY OBJECT MEMORY SCANNER
# Fallback when memory_service.get_object_memories() misses
# a freshly-stored item due to field-name or casing mismatch.
# =========================================================

def _fuzzy_scan_object_memories(db, user_id, query):
    """
    Scan ALL docs in object_memories and return any whose
    object_name / identifier / location fields contain the query
    as a substring (case-insensitive).
    Returns a list of dicts compatible with the existing memory format.
    """
    query_lower = query.lower().strip()
    query_words = set(query_lower.split())

    try:
        docs = (
            db.collection("users")
              .document(user_id)
              .collection("object_memories")
              .stream()
        )
    except Exception as e:
        print(f"⚠️ _fuzzy_scan_object_memories error: {e}")
        return []

    results = []
    for doc in docs:
        data = doc.to_dict()
        if not data:
            continue

        # Collect all text fields we want to match against
        obj_name   = str(data.get("object_name")  or data.get("identifier") or "").lower()
        identifier = str(data.get("identifier")   or "").lower()
        location   = str(data.get("location")     or "").lower()

        # Match if query appears as substring OR any query word appears in the object name
        combined = f"{obj_name} {identifier}"
        hit = (
            query_lower in combined
            or any(w in combined for w in query_words if len(w) > 2)
        )
        if hit:
            results.append({
                "object_name": data.get("object_name") or data.get("identifier", ""),
                "identifier":  data.get("identifier",  ""),
                "location":    data.get("location",    "Unknown"),
                "confidence":  data.get("confidence",  1),
                "doc_id":      doc.id,
            })
            print(f"✅ Fuzzy match found: {data}")

    return results


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
            time_text=parsed["time"],       # ✅ already IST-aware datetime
            time_display=parsed["time_display"],
            source="assistant",
            recurring_type="none",
            user_timezone="Asia/Kolkata",   # ✅ always IST, never rely on server local
        )
        if lang in ["Hindi", "Hinglish"]:
            reply_text = f"बिल्कुल! 😊 मैं आपको '{parsed['task']}' के लिए {parsed['time_display']} पर याद दिलाऊंगा। आप निश्चिंत रहें! 💙"
        else:
            reply_text = f"Got it! 😊 I'll remind you about '{parsed['task']}' at {parsed['time_display']}. You can count on me!"
        return {"reply": reply_text, "risk_level": risk_level}

    # ==========================================================
    # 1️⃣ Extract & Store Memory
    # ==========================================================
    memory_data = extract_memory(user_message)
    if memory_data:
        store_memory(user_id, memory_data)

        # ✅ FIX: Return a clear confirmation so the user knows the item was saved.
        # Previously the code fell through to the Groq LLM which gave a vague/wrong reply.
        obj = memory_data.get("object_name") or memory_data.get("identifier", "item")
        loc = memory_data.get("location", "there")

        if lang in ["Hindi", "Hinglish"]:
            confirm_reply = (
                f"समझ गया! 😊 मैंने याद कर लिया कि आपका {obj} {loc} में है। "
                f"जब भी ढूंढना हो, बस पूछें! 💙"
            )
        else:
            confirm_reply = (
                f"Got it! 😊 I've remembered that your {obj} is in the {loc}. "
                f"Just ask me 'Where is my {obj}?' anytime! 💙"
            )

        # Also save this exchange to chat history so it appears in conversation log
        db.collection("users").document(user_id).collection("chats").add({
            "user_message":    user_message,
            "assistant_reply": confirm_reply,
            "risk_level":      risk_level,
            "timestamp":       firestore.SERVER_TIMESTAMP,
        })

        return {"reply": confirm_reply, "risk_level": risk_level}

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
                    "reply": "Just to make sure — do you really want me to mark this reminder as completed? 😊",
                    "risk_level": risk_level,
                }
            complete_reminder(user_id, pending_completion)
            clear_pending_completion(user_id)
            clear_double_confirm_state(user_id)
            if risk_level == "High":
                reply_text = "Wonderful job! 🌟 I've marked it as completed. Keeping up with your routines is so good for you — I'm proud of you!"
            else:
                reply_text = "Great job! 🌟 I've marked that reminder as completed. Keep it up!"
            return {"reply": reply_text, "risk_level": risk_level}

        if user_lower in ["no", "cancel"]:
            clear_pending_completion(user_id)
            clear_double_confirm_state(user_id)
            return {"reply": "No problem! 😊 I'll leave that reminder as is.", "risk_level": risk_level}

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
                    "reply": f"Great job! 🌟 I found the reminder '{r['task']}'. Would you like me to mark it as completed?",
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
                        "reply": f"Got it! 😊 I've updated that for you. Your {mem['identifier']} {pending_object} is now in the {new_location}.",
                        "risk_level": risk_level,
                    }
            mem = object_memories[0]
            update_object_location(user_id, pending_object, mem["identifier"], new_location)
            clear_pending_object(user_id)
            return {
                "reply": f"Got it! 😊 I've updated that for you. Your {mem['identifier']} {pending_object} is now in the {new_location}.",
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
                    "reply": f"Of course! 😊 Your {mem['identifier']} {pending_object} is in the {mem['location']}.",
                    "risk_level": risk_level,
                }
            for mem in object_memories:
                identifier = mem["identifier"].lower()
                if identifier in user_lower:
                    increment_memory_confidence(user_id, mem)
                    clear_pending_object(user_id)
                    return {
                        "reply": f"Found it! 😊 Your {identifier} {pending_object} is in the {mem['location']}.",
                        "risk_level": risk_level,
                    }

    # ==========================================================
    # 🔟 Ambiguity Detection
    # ==========================================================
    match = re.search(r"where is (?:my|the) (.+)|(?:mera|meri|मेरा|मेरी) (.+?) (?:kahan|कहाँ)", user_lower)

    if match:
        object_name     = re.sub(r"[^\w\s]", "", match.group(1) or match.group(2) or "").strip()
        object_memories = get_object_memories(user_id, object_name)

        # ✅ FIX: If get_object_memories returns nothing, do a direct Firestore
        #    fuzzy scan so freshly-stored items are found immediately.
        if not object_memories:
            object_memories = _fuzzy_scan_object_memories(db, user_id, object_name)

        if len(object_memories) > 1:
            set_pending_object(user_id, object_name)
            if lang in ["Hindi", "Hinglish"]:
                clarification_message = f"मुझे आपके कई {object_name} मिले! 😊\n"
                for mem in object_memories:
                    clarification_message += f"• आपका {mem['identifier']} {object_name} {mem['location']} में है।\n"
                clarification_message += "\nआप किसके बारे में जानना चाहते हैं?"
            else:
                clarification_message = f"I found a few {object_name}s I'm keeping track of for you! 😊\n"
                for mem in object_memories:
                    clarification_message += f"• Your {mem['identifier']} {object_name} is in the {mem['location']}.\n"
                clarification_message += "\nWhich one were you looking for?"
            return {"reply": clarification_message, "risk_level": risk_level}

        elif len(object_memories) == 1:
            mem = object_memories[0]
            increment_memory_confidence(user_id, mem)
            # ✅ FIX: Build a clean label — don't print blank identifier prefix
            identifier = mem.get("identifier", "").strip()
            display_name = f"{identifier} {object_name}".strip() if identifier and identifier.lower() != object_name.lower() else object_name
            location = mem.get("location", "there")
            if lang in ["Hindi", "Hinglish"]:
                return {
                    "reply": f"मिल गया! 😊 आपका {display_name} {location} में है। 💙",
                    "risk_level": risk_level,
                }
            return {
                "reply": f"Found it! 😊 Your {display_name} is in the {location}. 💙",
                "risk_level": risk_level,
            }
        else:
            if lang in ["Hindi", "Hinglish"]:
                reply_text = f"हम्म, मुझे आपके {object_name} की जगह नहीं पता। कोई बात नहीं! बताएं कहाँ है, मैं याद रख लूंगा। 😊"
            elif risk_level == "High":
                reply_text = f"Hmm, I don't know where your {object_name} is right now. No worries! Just tell me where it is and I'll remember it for you. 😊"
            else:
                reply_text = f"I don't have a record of where your {object_name} is, but I'd love to help! Just tell me where it is and I'll keep track of it for you. 😊"
            return {"reply": reply_text, "risk_level": risk_level}

    # ==========================================================
    # 📋 LIST REMINDERS
    # ==========================================================
    if "what reminders" in user_lower or "list reminders" in user_lower \
            or "mere reminders" in user_lower or "मेरे रिमाइंडर" in user_message:
        reminders = get_user_reminders(user_id)
        if not reminders:
            if lang in ["Hindi", "Hinglish"]:
                return {"reply": "अभी आपका कोई रिमाइंडर नहीं है। 😊 क्या मैं एक सेट करूं?", "risk_level": risk_level}
            return {"reply": "You have no active reminders right now. 😊 Would you like to set one?", "risk_level": risk_level}
        if lang in ["Hindi", "Hinglish"]:
            reply_text = "आपके आने वाले रिमाइंडर! ⏰\n"
        else:
            reply_text = "Here are your upcoming reminders! ⏰\n"
        for r in reminders:
            raw_time     = r.get("time") or r.get("time_text")
            display_time = raw_time.strftime("%I:%M %p") if hasattr(raw_time, "strftime") else str(raw_time)
            reply_text  += f"• {r['task']} at {display_time}\n"
        if lang in ["Hindi", "Hinglish"]:
            reply_text += "\nक्या आप कुछ बदलना चाहते हैं? 😊"
        else:
            reply_text += "\nLet me know if you need to change anything! 😊"
        return {"reply": reply_text, "risk_level": risk_level}

    # ==========================================================
    # ⏰ NEXT REMINDER
    # ==========================================================
    if "next reminder" in user_lower or "अगला रिमाइंडर" in user_message:
        next_reminder = get_next_reminder(user_id)
        if not next_reminder:
            if lang in ["Hindi", "Hinglish"]:
                return {"reply": "अभी आपका कोई आने वाला रिमाइंडर नहीं है। 😊 क्या मैं एक सेट करूं?", "risk_level": risk_level}
            return {"reply": "You have no upcoming reminders right now. 😊 Would you like me to set one?", "risk_level": risk_level}
        raw_time     = next_reminder.get("time") or next_reminder.get("time_text")
        display_time = raw_time.strftime("%I:%M %p") if hasattr(raw_time, "strftime") else str(raw_time)
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
    cancel_pattern = r"(?:cancel|delete|remove) (?:my )?(?:reminder )?(?:to )?(.+)"
    match_cancel   = re.search(cancel_pattern, user_lower)

    if match_cancel:
        task_text = match_cancel.group(1).strip()
        if "last" in task_text:
            deleted = delete_last_reminder(user_id)
            if deleted:
                if lang in ["Hindi", "Hinglish"]:
                    return {"reply": "हो गया! 😊 आपका आखिरी रिमाइंडर हटा दिया है।", "risk_level": risk_level}
                return {"reply": "Done! 😊 I've cancelled your last reminder.", "risk_level": risk_level}
        deleted = delete_reminder_by_task(user_id, task_text)
        if deleted:
            if lang in ["Hindi", "Hinglish"]:
                return {"reply": f"हो गया! 😊 '{task_text}' का रिमाइंडर हटा दिया है।", "risk_level": risk_level}
            return {"reply": f"Done! 😊 I've removed the reminder for '{task_text}'.", "risk_level": risk_level}
        else:
            if lang in ["Hindi", "Hinglish"]:
                return {"reply": "हम्म, वो रिमाइंडर नहीं मिला। क्या आप नाम जाँच कर फिर से बताएंगे? 😊", "risk_level": risk_level}
            return {"reply": "Hmm, I couldn't find that reminder. Could you check the name and try again? 😊", "risk_level": risk_level}

    # ==========================================================
    # 🗑 CLEAR ALL REMINDERS
    # ==========================================================
    if "clear all reminders" in user_lower or "सभी रिमाइंडर हटाओ" in user_message:
        clear_all_reminders(user_id)
        if lang in ["Hindi", "Hinglish"]:
            return {"reply": "हो गया! 😊 आपके सभी रिमाइंडर हटा दिए हैं।", "risk_level": risk_level}
        return {"reply": "All done! 😊 All your reminders have been cleared.", "risk_level": risk_level}

    # ==========================================================
    # ❓ /help COMMAND
    # ==========================================================
    if user_lower.strip() in ["/help", "help", "सहायता", "madad"]:
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
        "kya kar sakte ho", "kya ho tum",
        "aap kon ho", "memoir kya hai",
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

        hour = datetime.now().hour
        if lang in ["Hindi", "Hinglish"]:
            if hour < 12:
                time_greet = "सुप्रभात"
            elif hour < 17:
                time_greet = "नमस्ते"
            else:
                time_greet = "शुभ संध्या"
            if name:
                reply_text = f"{time_greet}, {name}! 😊 आपसे मिलकर बहुत अच्छा लगा! मैं आपकी क्या सेवा कर सकता हूँ? (/help टाइप करें)"
            else:
                reply_text = f"{time_greet}! 😊 आपसे मिलकर बहुत अच्छा लगा! मैं आपकी क्या सेवा कर सकता हूँ? (/help टाइप करें)"
        else:
            if hour < 12:
                time_greet = "Good morning"
            elif hour < 17:
                time_greet = "Good afternoon"
            else:
                time_greet = "Good evening"
            if name:
                reply_text = (
                    f"{time_greet}, {name}! 😊 It's so lovely to hear from you! "
                    f"How can I help you today? (Type /help to see what I can do!)"
                )
            else:
                reply_text = (
                    f"{time_greet}! 😊 It's wonderful to hear from you! "
                    f"How can I help you today? (Type /help to see what I can do!)"
                )
        return {"reply": reply_text, "risk_level": risk_level}

    # ==========================================================
    # 🤖 GROQ LLM FALLBACK (replaces llm.create_chat_completion)
    # ==========================================================
    history            = get_conversation_history(user_id, limit=3)
    long_term_memories = get_all_memories(user_id)
    system_prompt      = build_system_prompt(risk_level)

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
        if lang in ["Hindi", "Hinglish"]:
            return {
                "reply": "ओह नहीं, अभी कनेक्शन में थोड़ी दिक्कत है। 😔 कृपया थोड़ी देर बाद फिर कोशिश करें!",
                "risk_level": risk_level,
            }
        return {
            "reply": f"Oh no, I'm having a little trouble connecting right now. 😔 Please try again in a moment! ({str(e)})",
            "risk_level": risk_level,
        }

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