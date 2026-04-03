from flask import Flask, jsonify
from flask_cors import CORS

# Firebase
from database.firebase_config import initialize_firebase

from routes.prediction_routes import prediction_bp
from routes.chatbot_routes import chatbot_bp

def create_app():
    app = Flask(__name__)
    CORS(app)

    # Initialize Firebase
    initialize_firebase()

    # Register Blueprints
    app.register_blueprint(prediction_bp)
    app.register_blueprint(chatbot_bp)

    # Health Check Route
    @app.route("/")
    def home():
        return jsonify({
            "message": "Welcome to Memoir Backend API",
            "status": "Running"
        })

    # Debug: Print all routes
    print("\n===== REGISTERED ROUTES =====")
    print(app.url_map)
    print("=============================\n")

    return app


app = create_app()


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)