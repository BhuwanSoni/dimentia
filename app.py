from flask import Flask, request, jsonify
import firebase_admin
from firebase_admin import credentials, firestore
import spacy
from datetime import datetime, timezone

# --- 1. SETUP ---
try:
    cred = credentials.Certificate("firebase_key.json")
    firebase_admin.initialize_app(cred)
    db = firestore.client()
    print("Firebase initialized successfully.")
except Exception as e:
    print(f"CRITICAL: Firebase initialization failed. Error: {e}")
    db = None

try:
    nlp = spacy.load("en_core_web_sm")
    print("spaCy model loaded successfully.")
except IOError:
    print("CRITICAL: spaCy model 'en_core_web_sm' not found.")
    nlp = None

app = Flask(__name__)

# --- 2. HELPER FUNCTION (NLP) ---

def analyze_text_for_storage(text):
    if not nlp:
        return None

    doc = nlp(text.lower())
    item = None
    value = None
    root_verb = None

    for token in doc:
        if token.dep_ in ('nsubj', 'dobj') and not item:
            item = token.lemma_

    for token in doc:
        if token.dep_ == 'ROOT':
            root_verb = token
            break
            
    if item and root_verb and root_verb.i < len(doc) - 1:
        value = doc[root_verb.i + 1:].text.strip()
    
    # Only return a tuple if both parts were found
    if item and value:
        return item, value
    
    # Otherwise, return None
    return None

# --- 3. API ENDPOINTS ---

@app.route('/')
def home():
    return "Welcome to the ElderEase Backend API! The server is running."

@app.route('/memory', methods=['POST'])
def store_memory_item():
    if not db or not nlp:
        return jsonify({"error": "Server is not configured correctly. Check logs."}), 500

    data = request.json
    user_id = data.get("userId")
    text = data.get("text")

    if not user_id or not text:
        return jsonify({"error": "Request must include 'userId' and 'text'."}), 400

    # --- THIS IS THE FIX ---
    # 1. Store the result in one variable first.
    analysis_result = analyze_text_for_storage(text)

    # 2. Check if the result is valid before unpacking.
    if not analysis_result:
        return jsonify({"error": "I couldn't understand the item and its location from your sentence."}), 400
    
    # 3. Now it's safe to unpack.
    item_key, item_value = analysis_result
    # --- END OF FIX ---

    doc_id = f"{user_id}_{item_key}"
    doc_ref = db.collection("memory_items").document(doc_id)

    memory_data = {
        "userId": user_id,
        "itemKey": item_key,
        "itemValue": item_value,
        "originalQuery": text,
        "lastUpdatedAt": datetime.now(timezone.utc)
    }
    
    doc_ref.set(memory_data)

    return jsonify({
        "status": "success",
        "message": f"Got it! I'll remember that your '{item_key}' is '{item_value}'."
    }), 201

@app.route('/memory', methods=['GET'])
def retrieve_memory_item():
    if not db or not nlp:
        return jsonify({"error": "Server is not configured correctly. Check logs."}), 500

    user_id = request.args.get("userId")
    item_key = request.args.get("item")

    if not user_id or not item_key:
        return jsonify({"error": "Request must include 'userId' and 'item' as URL parameters."}), 400
        
    item_key = item_key.lower().strip()
    doc_id = f"{user_id}_{item_key}"
    doc_ref = db.collection("memory_items").document(doc_id)
    doc = doc_ref.get()

    if doc.exists:
        return jsonify(doc.to_dict()), 200
    else:
        return jsonify({"error": f"Sorry, I don't have any information about '{item_key}' for you."}), 404



if __name__ == '__main__':
    app.run(debug=True)