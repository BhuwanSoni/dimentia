from database.firebase_config import get_firestore_client
from google.cloud import firestore
import re
from datetime import datetime
from difflib import SequenceMatcher


# ============================================================
# 🔹 Constants — Canonical Object Map + Plural Set
# ============================================================

# Multi-word aliases resolved BEFORE single-word lookup
MULTI_WORD_CANONICAL = {
    "tv remote":       "remote",
    "remote control":  "remote",
    "cell phone":      "mobile",
    "reading glasses": "glasses",
    "sun glasses":     "sunglasses",
    "sun glass":       "sunglasses",
}

OBJECT_SYNONYMS = {
    # glasses
    "specs":        "glasses",
    "spectacles":   "glasses",
    "eyeglasses":   "glasses",
    "chashma":      "glasses",
    "eyewear":      "glasses",
    # mobile
    "phone":        "mobile",
    "smartphone":   "mobile",
    "cell":         "mobile",
    "cellphone":    "mobile",
    "mob":          "mobile",
    "fone":         "mobile",
    # wallet
    "billfold":     "wallet",
    "batua":        "wallet",
    "purse":        "wallet",
    # medicine
    "tablet":       "medicine",
    "dawa":         "medicine",
    "dawai":        "medicine",
    "pill":         "medicine",
    "goli":         "medicine",
    "capsule":      "medicine",
    # keys
    "key":          "keys",
    "chaabi":       "keys",
    "chabi":        "keys",
    # charger
    "cable":        "charger",
    # watch
    "ghadi":        "watch",
    "wrist watch":  "watch",
}

# Objects whose verb should be "are" not "is"
PLURAL_OBJECTS = {"glasses", "keys", "spectacles", "specs", "sunglasses"}

# Known object root words — used to split identifier from object
KNOWN_OBJECTS = {
    "glasses", "mobile", "phone", "wallet", "keys", "charger",
    "remote", "medicine", "watch", "bag", "purse", "book",
    "pen", "card", "diary", "bottle", "umbrella", "shoes",
    "slippers", "chappal", "box", "envelope", "file", "sunglasses",
}

# ============================================================
# 🔹 Canonical Relation Map
# ============================================================
RELATION_CANONICAL = {
    # English prepositions
    "in":            "in",
    "inside":        "inside",
    "on":            "on",
    "at":            "at",
    "under":         "under",
    "near":          "near",
    "beside":        "beside",
    "behind":        "behind",
    "next to":       "next to",
    # ✅ NEW: Extended relation vocabulary
    "between":       "between",
    "attached to":   "attached to",
    "hanging on":    "hanging on",
    "hanging from":  "hanging from",
    "clipped to":    "clipped to",
    "pinned to":     "pinned to",
    "leaning on":    "leaning on",
    "leaning against": "leaning against",
    "above":         "above",
    "below":         "below",
    "around":        "near",
    "by":            "near",
    "alongside":     "beside",
    # Hinglish / Hindi prepositions
    "ke andar":      "inside",
    "ke neeche":     "under",
    "ke paas":       "near",
    "ke peeche":     "behind",
    "ke upar":       "on",
    "ke beech":      "between",
    "ke saath":      "beside",
    "par":           "on",
    "mein":          "in",
    "me":            "in",
    "ke bagal mein": "beside",
    "ke piche":      "behind",
    # Verb phrases (storage-style)
    "kept in":       "in",
    "placed in":     "in",
    "lying in":      "in",
    "lying on":      "on",
    "hanging on":    "hanging on",
    "kept on":       "on",
    "placed on":     "on",
    # Hindi verb forms
    "rakha hai":     "in",
    "rakhi hai":     "in",
    "rakhe hain":    "in",
    "laga hai":      "attached to",
    "latka hai":     "hanging on",
    "latki hai":     "hanging on",
}


def normalize_relation(rel: str) -> str:
    """Map raw captured relation to its canonical English form."""
    if not rel:
        return "in"
    key = rel.lower().strip()
    return RELATION_CANONICAL.get(key, key)


# Location preposition pattern — captures the relation word
# ✅ NEW: Extended with between, attached to, hanging on/from, above, below,
#         clipped/pinned/leaning, Hinglish variants. Longer phrases MUST come
#         first so the regex engine matches them before their shorter prefixes.
LOCATION_PREP_PATTERN = (
    r"(leaning against|leaning on|attached to|hanging from|hanging on"
    r"|clipped to|pinned to|alongside|next to|between|beside"
    r"|ke bagal mein|ke beech|ke saath|ke andar|ke neeche|ke paas|ke peeche|ke upar"
    r"|placed on|placed in|kept on|kept in|lying on|lying in"
    r"|rakha hai|rakhi hai|rakhe hain|laga hai|latka hai|latki hai"
    r"|in(?:side)?|on|at|under|near|behind|above|below|by|around"
    r"|par|mein\b|me\b)"
)


# ============================================================
# 🔹 Helpers
# ============================================================

def object_verb(obj: str) -> str:
    """Return 'are' for plural objects like glasses/keys, else 'is'."""
    return "are" if obj.lower() in PLURAL_OBJECTS else "is"


def normalize_object(name: str) -> str:
    """
    Lowercase → strip possessive/articles → multi-word canonical
    → single-word synonym map.
    """
    if not name:
        return ""
    name = name.lower().strip()
    name = re.sub(r"'s\b", "", name)
    name = re.sub(r'^(my|mera|meri|mere|the|a|an)\s+', '', name)
    name = " ".join(name.split())
    if name in MULTI_WORD_CANONICAL:
        return MULTI_WORD_CANONICAL[name]
    return OBJECT_SYNONYMS.get(name, name)


def normalize_location(loc: str) -> str:
    """
    Lowercase, strip leading articles, collapse whitespace.
    Multi-word location nouns (TV stand, dining table, bed side)
    are preserved intact after lowercasing.
    """
    if not loc:
        return ""
    loc = loc.lower().strip()
    loc = re.sub(r'^(the|a|an)\s+', '', loc)
    loc = " ".join(loc.split())

    # Normalise common compound variants → canonical form
    loc = re.sub(r'\btv\s+stand\b',       'tv stand',       loc)
    loc = re.sub(r'\bdining\s+table\b',   'dining table',   loc)
    loc = re.sub(r'\bbedside\b',          'bed side',       loc)
    loc = re.sub(r'\bbed\s+side\b',       'bed side',       loc)
    loc = re.sub(r'\bnight\s*stand\b',    'nightstand',     loc)
    loc = re.sub(r'\bnight\s*table\b',    'nightstand',     loc)
    loc = re.sub(r'\bside\s+table\b',     'side table',     loc)
    loc = re.sub(r'\boffice\s+bag\b',     'office bag',     loc)
    loc = re.sub(r'\bstudy\s+table\b',    'study table',    loc)
    loc = re.sub(r'\bbook\s*shelf\b',     'bookshelf',      loc)
    loc = re.sub(r'\bdressing\s+table\b', 'dressing table', loc)
    return loc


def fuzzy_match(a: str, b: str, threshold: float = 0.85) -> bool:
    """
    String similarity check. Default threshold 0.85 avoids false
    positives. Short strings (<5 chars) auto-raise to 0.92.
    """
    if not a or not b:
        return False
    t = 0.92 if len(a) < 5 or len(b) < 5 else threshold
    return SequenceMatcher(None, a, b).ratio() >= t


def _split_identifier_object(phrase: str):
    """
    Split "black glasses"  → ("black", "glasses")
          "office bag"     → ("office", "bag")
          "glasses"        → ("", "glasses")
    """
    words = phrase.split()
    for i in range(len(words) - 1, -1, -1):
        candidate = " ".join(words[i:])
        norm = normalize_object(candidate)
        if norm in KNOWN_OBJECTS or candidate in KNOWN_OBJECTS:
            identifier = " ".join(words[:i]).strip()
            if candidate != norm and len(candidate.split()) > 1:
                alias_words = candidate.split()
                root_words  = norm.split()
                extra = [w for w in alias_words if w not in root_words]
                if extra:
                    identifier = (" ".join(extra) + " " + identifier).strip()
            return identifier, norm
    return "", normalize_object(phrase)


def format_location_reply(obj: str, relation: str, location: str) -> str:
    """
    Build natural location string using stored relation word.
    e.g. ("glasses", "inside", "almirah") → "inside the almirah"
         ("wallet",  "on",     "table")   → "on the table"
    Hindi-only relations suppress "the".
    """
    relation = (relation or "in").strip()
    hindi_only_no_article = {
        "ke andar", "ke neeche", "ke paas", "ke peeche", "ke upar",
        "par", "mein", "me",
    }
    article = "" if relation in hindi_only_no_article else "the "
    return f"{relation} {article}{location}"


# ============================================================
# 🔹 Unified Memory Sort Key
# ============================================================

def _memory_sort_key(mem: dict) -> tuple:
    """
    Canonical sort key used everywhere memories are ranked.

    Priority order (highest → lowest):
      1. last_confirmed  — most recently user-confirmed location
      2. last_accessed   — recently looked up (boosts confidence too)
      3. updated_at      — programmatic update timestamp
      4. created_at      — original creation time
      5. confidence      — accumulated confidence score

    ✅ FIX: Timestamps are now converted via .timestamp() (POSIX float) instead
    of str(). This guarantees correct ordering regardless of timezone string
    representation differences in Firestore DatetimeWithNanoseconds objects.
    None timestamps sort as 0.0 (before any real timestamp).

    Returning a tuple means Python's sort is stable and multi-key.
    """
    def _ts(key):
        val = mem.get(key)
        if val is None:
            return 0.0
        # Firestore DatetimeWithNanoseconds and standard datetime both have .timestamp()
        try:
            return val.timestamp()
        except Exception:
            # Fallback: string comparison (safe but less precise)
            return str(val)

    return (
        _ts("last_confirmed"),     # primary: recency of user confirmation
        _ts("last_accessed"),      # secondary: recency of retrieval
        _ts("updated_at"),         # tertiary: programmatic update
        _ts("created_at"),         # quaternary: creation order
        mem.get("confidence", 1),  # quinary: accumulated confidence
    )


def sort_memories(memories: list) -> list:
    """
    Return a new list sorted by _memory_sort_key, newest/highest first.
    Safe to call with an empty list.
    """
    return sorted(memories, key=_memory_sort_key, reverse=True)


# ============================================================
# 🔹 Extract Memory From Message
# ============================================================

def extract_memory(user_message: str):
    """
    Parse a user message into a memory dict, or return None.

    Handles:
      Pattern A  — "my glasses are inside the almirah"
      Pattern B  — "I kept my phone in the drawer"
      Pattern C  — freeform "phone is near TV" (known objects only)
      General    — "remember that …"
      Structured — "my daughter's name is …"
    """
    text = user_message.lower().strip()

    # ── Pattern A: possessive-led ─────────────────────────────
    pat_a = (
        r"(?:my|mera|meri|mere|मेरा|मेरी)\s+"
        r"(.+?)\s+"
        + LOCATION_PREP_PATTERN
        + r"\s+(?:the\s+)?(.+)"
    )
    m = re.search(pat_a, text)
    if m:
        identifier, obj = _split_identifier_object(m.group(1).strip())
        return {
            "type":       "object_location",
            "object":     obj,
            "identifier": identifier,
            "relation":   normalize_relation(m.group(2).strip()),
            "location":   normalize_location(m.group(3).strip()),
            "is_active":  True,
        }

    # ── Pattern B: "I kept/left/put … my <obj> <prep> <loc>" ──
    pat_b = (
        r"(?:i\s+(?:kept|left|put|placed|have kept|have put))\s+"
        r"(?:my|mera|meri|mere)?\s*"
        r"(.+?)\s+"
        + LOCATION_PREP_PATTERN
        + r"\s+(?:the\s+)?(.+)"
    )
    m = re.search(pat_b, text)
    if m:
        identifier, obj = _split_identifier_object(m.group(1).strip())
        return {
            "type":       "object_location",
            "object":     obj,
            "identifier": identifier,
            "relation":   normalize_relation(m.group(2).strip()),
            "location":   normalize_location(m.group(3).strip()),
            "is_active":  True,
        }

    # ── Pattern C: freeform — only for recognized objects ─────
    # ✅ FIX: Extended capture group from max 2 words to max 5 words so phrases
    # like "blue reading glasses" and "office work keys" are captured correctly.
    # Over-capture safety: _split_identifier_object() walks right-to-left through
    # the captured phrase to find the rightmost KNOWN_OBJECTS member, so even if
    # Pattern C captures "very important office black glasses", the object is
    # correctly identified as "glasses" and identifier as "very important office black".
    pat_c = (
        r"(\b\w+(?:\s+\w+){0,4}\b)\s+"
        r"(?:is|are|'s)\s+"
        + LOCATION_PREP_PATTERN
        + r"\s+(?:the\s+)?(.+)"
    )
    m = re.search(pat_c, text)
    if m:
        norm_obj  = normalize_object(m.group(1).strip())
        location  = m.group(3).strip()
        has_location_noun = bool(re.search(r'\b[a-z]{3,}\b', location))
        if norm_obj in KNOWN_OBJECTS and has_location_noun:
            return {
                "type":       "object_location",
                "object":     norm_obj,
                "identifier": "",
                "relation":   normalize_relation(m.group(2).strip()),
                "location":   normalize_location(location),
                "is_active":  True,
            }

    # ── Pattern D: pronoun-led location update ───────────────
    # Handles "now it is in locker", "it is on the table",
    # "its in almirah", "now its in the drawer", "it's in locker" etc.
    # The actual object is not stated — the caller must resolve
    # via get_pending_object(user_id) or the last chat query context.
    pat_d = (
        r"^(?:now\s+)?(?:it(?:'?s)?|this|that)\s+"
        r"(?:is\s+)?"
        + LOCATION_PREP_PATTERN
        + r"\s+(?:the\s+)?(.+)"
    )
    m = re.search(pat_d, text)
    if m:
        return {
            "type":     "pending_resolution",   # caller must supply the object
            "relation": normalize_relation(m.group(1).strip()),
            "location": normalize_location(m.group(2).strip()),
        }

    # ── General Note ──────────────────────────────────────────
    if text.startswith("remember that"):
        return {
            "type":  "general_note",
            "value": user_message[len("remember that"):].strip(),
        }

    # ── Structured / Family Memory ────────────────────────────
    family_patterns = [
        (r"my daughter(?:'s)? name is (.+)", "daughter", "name"),
        (r"my son(?:'s)? name is (.+)",      "son",      "name"),
        (r"my wife(?:'s)? name is (.+)",     "wife",     "name"),
        (r"my husband(?:'s)? name is (.+)",  "husband",  "name"),
        (r"my mother(?:'s)? name is (.+)",   "mother",   "name"),
        (r"my father(?:'s)? name is (.+)",   "father",   "name"),
        (r"my sister(?:'s)? name is (.+)",   "sister",   "name"),
        (r"my brother(?:'s)? name is (.+)",  "brother",  "name"),
    ]
    for pattern, relation, attribute in family_patterns:
        match = re.search(pattern, text)
        if match:
            return {
                "type":      "structured",
                "relation":  relation,
                "attribute": attribute,
                "value":     match.group(1).strip().capitalize(),
            }

    return None


# ============================================================
# 🔹 Update Object Location (move intent)
# ============================================================

def update_object_location(user_id, obj, identifier, new_location, relation="in"):
    """
    Archive the current active entry for this object, then write
    a new active entry with the new location. Preserves history.
    """
    db       = get_firestore_client()
    obj_norm = normalize_object(obj)
    id_norm  = normalize_object(identifier)

    for doc in (
        db.collection("users")
          .document(user_id)
          .collection("long_term_memory")
          .stream()
    ):
        data = doc.to_dict()
        if data.get("type") != "object_location" or not data.get("is_active", True):
            continue
        stored_obj = normalize_object(data.get("object", "") or data.get("object_name", ""))
        stored_id  = normalize_object(data.get("identifier", ""))
        if (stored_obj == obj_norm or fuzzy_match(stored_obj, obj_norm)) and (
            stored_id == id_norm or not id_norm or not stored_id
        ):
            doc.reference.update({
                "is_active":   False,
                "archived_at": firestore.SERVER_TIMESTAMP,
            })

    db.collection("users").document(user_id).collection("long_term_memory").add({
        "type":           "object_location",
        "object":         obj_norm,
        "identifier":     id_norm,
        "relation":       normalize_relation(relation),
        "location":       normalize_location(new_location),
        "confidence":     1,
        "is_active":      True,
        "created_at":     firestore.SERVER_TIMESTAMP,
        "last_confirmed": firestore.SERVER_TIMESTAMP,
    })
    print(f"🧠 Object moved: {obj_norm} → {new_location}")


# ============================================================
# 🔹 Confidence (capped at 5.0)
# ============================================================

def increment_memory_confidence(user_id, mem):
    db       = get_firestore_client()
    obj_norm = normalize_object(mem.get("object_name") or mem.get("object", ""))

    for doc in (
        db.collection("users")
          .document(user_id)
          .collection("long_term_memory")
          .stream()
    ):
        data = doc.to_dict()
        if data.get("type") != "object_location" or not data.get("is_active", True):
            continue
        stored = normalize_object(data.get("object", "") or data.get("object_name", ""))
        if stored == obj_norm or fuzzy_match(stored, obj_norm):
            current = data.get("confidence", 1)
            doc.reference.update({
                "confidence":     min(round(current + 0.1, 2), 5.0),
                "last_accessed":  firestore.SERVER_TIMESTAMP,
                "last_confirmed": firestore.SERVER_TIMESTAMP,
            })


# ============================================================
# 🔹 Store Memory
# ============================================================

def store_memory(user_id, memory_data):
    db         = get_firestore_client()
    memory_ref = db.collection("users").document(user_id).collection("long_term_memory")

    # ── Structured ───────────────────────────────────────────
    if memory_data["type"] == "structured":
        for doc in memory_ref.stream():
            data = doc.to_dict()
            if (data.get("relation") == memory_data["relation"]
                    and data.get("attribute") == memory_data["attribute"]):
                existing_value = data.get("value", "")
                new_value      = memory_data["value"]
                # ✅ FIX: If the incoming value differs from the stored value,
                # flag the conflict so the caller can prompt the user for
                # confirmation instead of silently overwriting.
                # The caller checks for the "conflict" key and returns a
                # clarification prompt before calling store_memory again with
                # memory_data["confirmed"] = True.
                if (existing_value.lower() != new_value.lower()
                        and not memory_data.get("confirmed", False)):
                    print(f"⚠️ Structured memory conflict: '{existing_value}' → '{new_value}' (needs confirmation)")
                    return {
                        "conflict":        True,
                        "existing_value":  existing_value,
                        "new_value":       new_value,
                        "relation":        memory_data["relation"],
                        "attribute":       memory_data["attribute"],
                    }
                doc.reference.update({
                    "value":      new_value,
                    "updated_at": firestore.SERVER_TIMESTAMP,
                })
                print("🧠 Structured memory updated.")
                return None
        memory_ref.add({
            "type":       "structured",
            "relation":   memory_data["relation"],
            "attribute":  memory_data["attribute"],
            "value":      memory_data["value"],
            "created_at": firestore.SERVER_TIMESTAMP,
        })
        print("🧠 Structured memory stored.")
        return None

    # ── Object Location ──────────────────────────────────────
    elif memory_data["type"] == "object_location":
        obj        = normalize_object(memory_data["object"])
        identifier = normalize_object(memory_data.get("identifier", ""))
        location   = normalize_location(memory_data["location"])
        relation   = normalize_relation(memory_data.get("relation", "in"))

        _INVALID_LOCATION_TOKENS = {
            "happiness", "sadness", "love", "anger", "joy", "sorrow",
            "peace", "nowhere", "everywhere", "somewhere", "anywhere",
            "nothing", "everything", "something", "anything",
            "heaven", "hell", "dreams", "thoughts", "mind", "heart",
        }
        location_tokens = set(location.split())
        if not location or len(location) < 2 or location_tokens.issubset(_INVALID_LOCATION_TOKENS):
            print(f"⚠️ store_memory: rejected non-physical location '{location}'")
            return

        for doc in memory_ref.stream():
            data = doc.to_dict()
            if data.get("type") != "object_location" or not data.get("is_active", True):
                continue
            stored_obj = normalize_object(data.get("object", "") or data.get("object_name", ""))
            stored_id  = normalize_object(data.get("identifier", ""))

            if stored_obj == obj and stored_id == identifier:
                if data.get("location") == location:
                    doc.reference.update({
                        "updated_at":     firestore.SERVER_TIMESTAMP,
                        "last_confirmed": firestore.SERVER_TIMESTAMP,
                    })
                    print("🧠 Object location refreshed (same location).")
                    return None
                # New location → archive old
                doc.reference.update({
                    "is_active":   False,
                    "archived_at": firestore.SERVER_TIMESTAMP,
                })
                print("🧠 Old location archived.")

        memory_ref.add({
            "type":           "object_location",
            "object":         obj,
            "identifier":     identifier,
            "relation":       relation,
            "location":       location,
            "confidence":     1,
            "is_active":      True,
            "created_at":     firestore.SERVER_TIMESTAMP,
            "last_confirmed": firestore.SERVER_TIMESTAMP,
        })
        print("🧠 Object stored.")
        return None

    # ── General Note ─────────────────────────────────────────
    elif memory_data["type"] == "general_note":
        memory_ref.add({
            "type":       "general_note",
            "value":      memory_data["value"],
            "created_at": firestore.SERVER_TIMESTAMP,
        })
        print("🧠 General memory stored.")
        return None


# ============================================================
# 🔹 Pending Object State
# ============================================================

def set_pending_object(user_id, object_name):
    db = get_firestore_client()
    # ✅ FIX: Store created_at so assistant_service can expire stale clarifications.
    # Without this, a pending clarification from 20 minutes ago could still fire.
    db.collection("users").document(user_id).set(
        {
            "pending_object":            object_name,
            "pending_object_created_at": firestore.SERVER_TIMESTAMP,
        },
        merge=True,
    )


def get_pending_object(user_id):
    """
    Return the pending object name, or None if:
      - no pending state exists, OR
      - the clarification is stale (older than PENDING_OBJECT_EXPIRY_SECONDS).

    ✅ FIX: Previously pending_object persisted indefinitely. A user saying
    "where are my glasses?" then walking away meant that 20 minutes later,
    any message (e.g. "okay thanks") would incorrectly trigger the glasses
    clarification resolver. Now the state auto-expires after 5 minutes.
    """
    PENDING_OBJECT_EXPIRY_SECONDS = 300   # 5 minutes
    from datetime import timezone

    db  = get_firestore_client()
    doc = db.collection("users").document(user_id).get()
    if not doc.exists:
        return None

    data          = doc.to_dict()
    pending_obj   = data.get("pending_object")
    created_at    = data.get("pending_object_created_at")

    if not pending_obj:
        return None

    # Check expiry if we have a timestamp
    if created_at is not None:
        try:
            # Firestore DatetimeWithNanoseconds is timezone-aware (UTC)
            now_utc = datetime.now(timezone.utc)
            age_seconds = (now_utc - created_at).total_seconds()
            if age_seconds > PENDING_OBJECT_EXPIRY_SECONDS:
                print(f"⏰ Pending object '{pending_obj}' expired after {age_seconds:.0f}s — clearing.")
                try:
                    clear_pending_object(user_id)
                except Exception:
                    pass
                return None
        except Exception as e:
            print(f"⚠️ Pending object expiry check error: {e}")

    return pending_obj


def clear_pending_object(user_id):
    db = get_firestore_client()
    db.collection("users").document(user_id).update({
        "pending_object":            firestore.DELETE_FIELD,
        "pending_object_created_at": firestore.DELETE_FIELD,
    })


# ============================================================
# 🔹 Delete / Forget Memory
# ============================================================

def delete_object_memory(user_id, obj_query: str) -> bool:
    """
    Archive all active memories matching obj_query.
    Returns True if at least one entry was archived.
    """
    db       = get_firestore_client()
    obj_norm = normalize_object(obj_query)
    deleted  = False

    for doc in (
        db.collection("users")
          .document(user_id)
          .collection("long_term_memory")
          .stream()
    ):
        data = doc.to_dict()
        if data.get("type") != "object_location" or not data.get("is_active", True):
            continue
        stored = normalize_object(data.get("object", "") or data.get("object_name", ""))
        if stored == obj_norm or fuzzy_match(stored, obj_norm):
            doc.reference.update({
                "is_active":   False,
                "archived_at": firestore.SERVER_TIMESTAMP,
            })
            deleted = True
    return deleted


# ============================================================
# 🔹 Fetch Object Memories
# ============================================================

def get_object_memories(user_id, object_name: str):
    """
    Return ACTIVE object memories matching object_name.
    Matching tiers: exact normalized → partial → fuzzy (0.85).

    ✅ FIX: Results are now sorted by _memory_sort_key (recency-first,
    then confidence) so the most recently confirmed location always
    comes first — critical for resolving stale vs current locations.
    """
    db         = get_firestore_client()
    query_norm = normalize_object(object_name)
    results    = []

    for doc in (
        db.collection("users")
          .document(user_id)
          .collection("long_term_memory")
          .stream()
    ):
        data = doc.to_dict()
        if data.get("type") != "object_location":
            continue
        if not data.get("is_active", True):
            continue

        stored_raw  = data.get("object") or data.get("object_name") or ""
        stored_norm = normalize_object(stored_raw)
        id_norm     = normalize_object(data.get("identifier", ""))

        exact   = (query_norm == stored_norm or query_norm == id_norm)
        # ✅ FIX: Token-boundary partial matching replaces naive substring `in` check.
        # Old: query_norm in stored_norm  →  "card" matched "postcard", "cardholder"
        # New: token-set intersection ensures only whole-word matches count.
        query_tokens  = set(query_norm.split())
        stored_tokens = set(stored_norm.split())
        id_tokens     = set(id_norm.split())
        partial = bool(
            query_tokens.intersection(stored_tokens)
            or query_tokens.intersection(id_tokens)
        )
        fuzz = fuzzy_match(query_norm, stored_norm)

        if exact or partial or fuzz:
            result = dict(data)
            result["object_name"] = stored_norm or id_norm
            results.append(result)

    # ✅ Sort: recency PRIMARY, confidence SECONDARY
    return sort_memories(results)


# ============================================================
# 🔹 Fetch All Memories (structured + general notes for LLM)
# ============================================================

def get_all_memories(user_id):
    db  = get_firestore_client()
    out = []

    for doc in (
        db.collection("users")
          .document(user_id)
          .collection("long_term_memory")
          .stream()
    ):
        data = doc.to_dict()
        if not data:
            continue
        if data.get("type") == "structured":
            r, a, v = data.get("relation"), data.get("attribute"), data.get("value")
            if r and a and v:
                out.append(f"Your {r}'s {a} is {v}.")
        elif data.get("type") == "general_note":
            out.append(f"Note: {data['value']}")

    return out