from flask import Blueprint, request, jsonify
from services.assistant_service import generate_response

chatbot_bp = Blueprint("chatbot_bp", __name__)


@chatbot_bp.route("/chat", methods=["POST"])
def chat():
    try:
        data = request.get_json()

        user_id      = data.get("user_id")
        message      = data.get("message")
        profile_text = data.get("profile_text", "")

        # ✅ Pass Flutter-sent local time and date so the assistant can answer
        # "what time is it?" and "what's today's date?" correctly without
        # relying on server UTC time.
        current_time = data.get("current_time", "")   # e.g. "03:45 PM"
        current_date = data.get("current_date", "")   # e.g. "Wednesday, May 13, 2026"

        # ✅ Validation
        if not user_id or not message:
            return jsonify({"error": "Missing user_id or message"}), 400

        # ✅ Generate AI response (chat history + Firestore write handled inside service)
        result = generate_response(
            user_id,
            message,
            flutter_profile_text=profile_text,
            current_time=current_time,
            current_date=current_date,
        )

        # ✅ NOTE: Do NOT write to Firestore here.
        # generate_response() in assistant_service.py is the single authoritative
        # writer for chat history. Writing again here would cause:
        #   - Every reply saved twice (or three times including Flutter client)
        #   - get_conversation_history() fed duplicate turns to the LLM
        #   - History window filling 2-3x faster → confused/looping replies

        return jsonify(result), 200

    except Exception as e:
        return jsonify({
            "error": "Internal server error",
            "details": str(e)
        }), 500