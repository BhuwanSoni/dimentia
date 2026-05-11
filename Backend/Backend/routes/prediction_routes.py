from flask import Blueprint, request, jsonify
from services.prediction_service import predict_and_store

prediction_bp = Blueprint("prediction_bp", __name__)


@prediction_bp.route("/predict", methods=["POST"])
def predict():
    try:
        data = request.get_json(force=True, silent=True)

        # ── Validate body ────────────────────────────────────────
        if not data:
            return jsonify({"error": "No JSON body provided"}), 400

        user_id            = data.get("user_id")
        questionnaire_data = data.get("questionnaire")

        if not user_id or not isinstance(user_id, str) or not user_id.strip():
            return jsonify({"error": "Missing or invalid user_id"}), 400

        if not questionnaire_data or not isinstance(questionnaire_data, dict):
            return jsonify({"error": "Missing or invalid questionnaire"}), 400

        # ── Run prediction ───────────────────────────────────────
        result = predict_and_store(user_id.strip(), questionnaire_data)

        # ── Surface service-level errors with correct HTTP code ──
        # BUG FIX: previously a service error (missing features, model not
        # loaded, etc.) was returned as HTTP 200, making it impossible for the
        # Flutter client to distinguish success from failure.
        if "error" in result:
            return jsonify(result), 422   # Unprocessable Entity

        return jsonify(result), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500
