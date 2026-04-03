from flask import Flask, jsonify
from flask_cors import CORS
import os

from database.firebase_config import initialize_firebase
from routes.prediction_routes import prediction_bp
from routes.chatbot_routes import chatbot_bp


def create_app():
    app = Flask(__name__)
    CORS(app)

    # Safe Firebase init
    try:
        initialize_firebase()
        print("✅ Firebase connected")
    except Exception as e:
        print("❌ Firebase failed:", e)

    app.register_blueprint(prediction_bp)
    app.register_blueprint(chatbot_bp)

    @app.route("/")
    def home():
        return jsonify({
            "message": "Welcome to Memoir Backend API",
            "status": "Running"
        })

    @app.route("/healthz")
    def health():
        return "OK", 200

    print("\n===== REGISTERED ROUTES =====")
    print(app.url_map)
    print("=============================\n")

    return app


app = create_app()


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 10000))
    app.run(host="0.0.0.0", port=port)