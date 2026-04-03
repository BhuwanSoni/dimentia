from flask import Blueprint, request, jsonify
from services.assistant_service import generate_response
from database.firebase_config import get_firestore_client
from google.cloud import firestore

chatbot_bp = Blueprint("chatbot_bp", __name__)


@chatbot_bp.route("/chat", methods=["POST"])
def chat():

    try:
        data = request.get_json()

        user_id      = data.get("user_id")
        message      = data.get("message")
        profile_text = data.get("profile_text", "")  # 🔥 NEW: real-time profile from Flutter

        if not user_id or not message:
            return jsonify({"error": "Missing data"}), 400

        # 🔥 Generate AI response (now personalized with Flutter profile)
        result = generate_response(user_id, message, flutter_profile_text=profile_text)

        # 🔥 Fetch user data (for test result logging)
        db = get_firestore_client()

        user_doc = db.collection("users").document(user_id).get()

        if user_doc.exists:
            user_data = user_doc.to_dict()

            # 🔥 Save test result into chat history
            db.collection("users") \
              .document(user_id) \
              .collection("chats") \
              .add({
                  "type": "test_result",
                  "risk_level": user_data.get("risk_level"),
                  "mmse": user_data.get("MMSE"),
                  "timestamp": firestore.SERVER_TIMESTAMP
              })

        return jsonify(result), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500