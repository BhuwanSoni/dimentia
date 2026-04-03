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
        .where("type", "==", "object_location") \
        .where("object", "==", obj) \
        .where("identifier", "==", identifier) \
        .stream()

    for doc in docs:
        doc.reference.update({
            "location": new_location,
            "confidence_score": 1.0,
            "last_updated": firestore.SERVER_TIMESTAMP
        })
def extract_memory(user_message):
    user_lower = user_message.lower().strip()

    # ======================================
    # 🔹 1. Advanced Object Location Memory
    # Example:
    # "Remember that my blue pen is in the drawer."
    # ======================================
    object_pattern = r"remember that my (.+?) (.+?) is (?:in|on) the (.+)"
    match = re.search(object_pattern, user_lower)

    if match:
        identifier = match.group(1).strip()
        obj = match.group(2).strip()
        location = match.group(3).strip()

        return {
            "type": "object_location",
            "object": obj,
            "identifier": identifier,
            "location": location
        }

    # ======================================
    # 🔹 2. Manual General Memory
    # Example:
    # "Remember that I take medicine at 8 PM."
    # ======================================
    if user_lower.startswith("remember that"):
        value = user_message[len("remember that"):].strip()
        return {
            "type": "general_note",
            "value": value
        }

    # ======================================
    # 🔹 3. Structured Family Memory
    # Example:
    # "My daughter's name is Priya."
    # ======================================
    patterns = [
        (r"my daughter's name is (.+)", "daughter", "name"),
        (r"my son's name is (.+)", "son", "name"),
        (r"my wife's name is (.+)", "wife", "name"),
        (r"my husband's name is (.+)", "husband", "name"),
    ]

    for pattern, relation, attribute in patterns:
        match = re.search(pattern, user_lower)
        if match:
            value = match.group(1).strip().capitalize()

            return {
                "type": "structured",
                "relation": relation,
                "attribute": attribute,
                "value": value
            }

    # ======================================
    # 🔹 4. No Memory Detected
    # ======================================
    return None
def increment_memory_confidence(user_id, mem):
    db = get_firestore_client()

    docs = db.collection("users") \
        .document(user_id) \
        .collection("long_term_memory") \
        .where("type", "==", "object_location") \
        .where("object", "==", mem["object"]) \
        .where("identifier", "==", mem["identifier"]) \
        .stream()

    for doc in docs:
        doc.reference.update({
            "confidence_score": firestore.Increment(0.1),
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

    # =====================================
    # 🔹 Structured Memory
    # =====================================
    if memory_data["type"] == "structured":
        relation = memory_data["relation"]
        attribute = memory_data["attribute"]
        value = memory_data["value"]

        existing_docs = memory_ref.stream()

        for doc in existing_docs:
            data = doc.to_dict()

            if (
                data.get("type") == "structured" and
                data.get("relation") == relation and
                data.get("attribute") == attribute and
                data.get("value", "").lower() == value.lower()
            ):
                print("🧠 Structured memory already exists.")
                return

        memory_ref.add({
    "type": "object_location",
    "object": obj,
    "identifier": identifier,
    "location": location,
    "confidence_score": 1.0,
    "last_accessed": firestore.SERVER_TIMESTAMP,
    "created_at": firestore.SERVER_TIMESTAMP
})  
        print("🧠 Structured memory stored.")
        return

    # =====================================
    # 🔹 Object Location Memory
    # =====================================
    elif memory_data["type"] == "object_location":
        obj = memory_data["object"]
        identifier = memory_data["identifier"]
        location = memory_data["location"]

        existing_docs = memory_ref.stream()

        for doc in existing_docs:
            data = doc.to_dict()

            if (
                data.get("type") == "object_location" and
                data.get("object") == obj and
                data.get("identifier") == identifier
            ):
                # 🔥 Update location instead of duplicating
                doc.reference.update({
                    "location": location,
                    "updated_at": firestore.SERVER_TIMESTAMP
                })
                print("🧠 Object location updated.")
                return

        memory_ref.add({
            "type": "object_location",
            "object": obj,
            "identifier": identifier,
            "location": location,
            "created_at": firestore.SERVER_TIMESTAMP
        })

        print("🧠 Object location stored.")
        return

    # =====================================
    # 🔹 General Notes
    # =====================================
    elif memory_data["type"] == "general_note":
        memory_ref.add({
            "type": "general_note",
            "value": memory_data["value"],
            "created_at": firestore.SERVER_TIMESTAMP
        })

        print("🧠 General memory stored.")
        return
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

    for doc in docs:
        data = doc.to_dict()

        if (
            data.get("type") == "object_location" and
            data.get("object") == object_name
        ):
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