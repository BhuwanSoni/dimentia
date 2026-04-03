from flask import Blueprint, request, jsonify
from services.prediction_service import predict_and_store

prediction_bp = Blueprint("prediction_bp", __name__)

@prediction_bp.route("/predict", methods=["POST"])
def predict():
    try:
        data = request.get_json()

        if not data:
            return jsonify({"error": "No JSON body provided"}), 400

        user_id = data.get("user_id")
        questionnaire_data = data.get("questionnaire")

        if not user_id:
            return jsonify({"error": "Missing user_id"}), 400

        if not questionnaire_data:
            return jsonify({"error": "Missing questionnaire"}), 400

        result = predict_and_store(user_id, questionnaire_data)

        return jsonify(result), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500
