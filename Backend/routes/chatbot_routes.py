from flask import Blueprint, request, jsonify
from services.assistant_service import generate_response

chatbot_bp = Blueprint("chatbot_bp", __name__)


@chatbot_bp.route("/chat", methods=["POST"])
def chat():
    try:
        data = request.get_json()

        user_id = data.get("user_id")
        message = data.get("message")
        profile_text = data.get("profile_text", "")

        # ✅ Validation
        if not user_id or not message:
            return jsonify({"error": "Missing user_id or message"}), 400

        # ✅ Generate AI response (chat history + Firestore write handled inside service)
        result = generate_response(
            user_id,
            message,
            flutter_profile_text=profile_text
        )

        # ✅ FIX: Removed the duplicate Firestore write that was here.
        # generate_response() in assistant_service.py is the single authoritative
        # writer for chat history. Writing again here caused:
        #   - Every reply saved twice (or three times including Flutter client)
        #   - get_conversation_history() fed duplicate turns to the LLM
        #   - History window filled 2-3x faster, causing confused/looping replies
        # If you need to log test_results, add a dedicated /save-test-result endpoint.

        return jsonify(result), 200

    except Exception as e:
        return jsonify({
            "error": "Internal server error",
            "details": str(e)
        }), 500