from database.firebase_config import get_firestore_client
from google.cloud import firestore
import re


# ==============================
# 🔹 Extract Memory From Message
# ==============================

import re
def update_object_location(user_id, obj, identifier, new_location):
    db = get_firestore_client()

    docs = db.collection("users") \
        .document(user_id) \
        .collection("long_term_memory") \
        .stream()

    for doc in docs:
        data = doc.to_dict()

        if data.get("type") != "object_location":
            continue

        if obj.lower() in data.get("object", "").lower():
            doc.reference.update({
                "location": new_location,
                "updated_at": firestore.SERVER_TIMESTAMP
            })  
def extract_memory(user_message):
    user_lower = user_message.lower().strip()

    # 🔥 Natural object memory (main fix)
    pattern = r"(?:my|mera|meri|mere)\s+(.+?)\s+(?:is|hai)\s+(?:in|on|at)\s+(?:the\s+)?(.+)"
    match = re.search(pattern, user_lower)

    if match:
        object_name = match.group(1).strip()
        location = match.group(2).strip()

        return {
            "type": "object_location",
            "object": object_name,   # ✅ FIXED KEY
            "identifier": "",
            "location": location
        }

    # 🔹 Advanced object (with identifier)
    pattern2 = r"(?:my)\s+(.+?)\s+(.+?)\s+(?:is|hai)\s+(?:in|on|at)\s+(?:the\s+)?(.+)"
    match2 = re.search(pattern2, user_lower)

    if match2:
        identifier = match2.group(1).strip()
        obj = match2.group(2).strip()
        location = match2.group(3).strip()

        return {
            "type": "object_location",
            "object": obj,
            "identifier": identifier,
            "location": location
        }

    # 🔹 Manual memory
    if user_lower.startswith("remember that"):
        value = user_message[len("remember that"):].strip()
        return {
            "type": "general_note",
            "value": value
        }

    # 🔹 Family memory
    patterns = [
        (r"my daughter's name is (.+)", "daughter", "name"),
        (r"my son's name is (.+)", "son", "name"),
        (r"my wife's name is (.+)", "wife", "name"),
        (r"my husband's name is (.+)", "husband", "name"),
    ]

    for pattern, relation, attribute in patterns:
        match = re.search(pattern, user_lower)
        if match:
            return {
                "type": "structured",
                "relation": relation,
                "attribute": attribute,
                "value": match.group(1).strip().capitalize()
            }

    return None
def increment_memory_confidence(user_id, mem):
    db = get_firestore_client()

    docs = db.collection("users") \
        .document(user_id) \
        .collection("long_term_memory") \
        .stream()

    for doc in docs:
        data = doc.to_dict()

        if data.get("type") != "object_location":
            continue

        if mem.get("object", "").lower() in data.get("object", "").lower():
            doc.reference.update({
                "confidence": firestore.Increment(0.1),
                "last_accessed": firestore.SERVER_TIMESTAMP
            })
# ==============================
# 🔹 Store Memory
# ==============================
def store_memory(user_id, memory_data):
    db = get_firestore_client()

    memory_ref = db.collection("users") \
                   .document(user_id) \
                   .collection("long_term_memory")

    # 🔹 Structured Memory
    if memory_data["type"] == "structured":
        memory_ref.add({
            "type": "structured",
            "relation": memory_data["relation"],
            "attribute": memory_data["attribute"],
            "value": memory_data["value"],
            "created_at": firestore.SERVER_TIMESTAMP
        })
        print("🧠 Structured memory stored.")
        return

    # 🔹 Object Memory
    elif memory_data["type"] == "object_location":
        obj = memory_data["object"]
        identifier = memory_data["identifier"]
        location = memory_data["location"]

        docs = memory_ref.stream()

        for doc in docs:
            data = doc.to_dict()

            if (
                data.get("type") == "object_location" and
                data.get("object", "").lower() == obj.lower() and
                data.get("identifier", "").lower() == identifier.lower()
            ):
                doc.reference.update({
                    "location": location,
                    "updated_at": firestore.SERVER_TIMESTAMP
                })
                print("🧠 Object updated.")
                return

        memory_ref.add({
            "type": "object_location",
            "object": obj,
            "identifier": identifier,
            "location": location,
            "confidence": 1,
            "created_at": firestore.SERVER_TIMESTAMP
        })

        print("🧠 Object stored.")
        return

    # 🔹 General Notes
    elif memory_data["type"] == "general_note":
        memory_ref.add({
            "type": "general_note",
            "value": memory_data["value"],
            "created_at": firestore.SERVER_TIMESTAMP
        })

        print("🧠 General memory stored.")
def set_pending_object(user_id, object_name):
    db = get_firestore_client()

    db.collection("users") \
      .document(user_id) \
      .set({
          "pending_object": object_name
      }, merge=True)


def get_pending_object(user_id):
    db = get_firestore_client()

    doc = db.collection("users") \
            .document(user_id) \
            .get()

    if doc.exists:
        return doc.to_dict().get("pending_object")

    return None


def clear_pending_object(user_id):
    db = get_firestore_client()

    db.collection("users") \
      .document(user_id) \
      .update({
          "pending_object": firestore.DELETE_FIELD
      })

# ==============================
# 🔹 Fetch Memory
# ==============================
def get_object_memories(user_id, object_name):
    db = get_firestore_client()

    docs = db.collection("users") \
        .document(user_id) \
        .collection("long_term_memory") \
        .stream()

    results = []
    object_name = object_name.lower()

    for doc in docs:
        data = doc.to_dict()

        if data.get("type") != "object_location":
            continue

        stored_obj = data.get("object", "").lower()

        # 🔥 PARTIAL MATCH FIX
        if object_name in stored_obj or stored_obj in object_name:
            results.append(data)

    return results
def get_all_memories(user_id):
    db = get_firestore_client()

    docs = db.collection("users") \
        .document(user_id) \
        .collection("long_term_memory") \
        .stream()

    memories = []

    for doc in docs:
        data = doc.to_dict()
        if not data:
            continue

        if data.get("type") == "structured":
            memories.append(
                f"Your {data['relation']}'s {data['attribute']} is {data['value']}."
            )

        elif data.get("type") == "general_note":
            memories.append(
                f"Note: {data['value']}"
            )

    return memories