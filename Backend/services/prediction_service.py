import os
import joblib
import numpy as np
from datetime import datetime
from database.firebase_config import get_firestore_client


# =========================================================
# Load Model Files (NO SCALER)
# =========================================================

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODEL_DIR = os.path.join(BASE_DIR, "model")

MODEL_PATH = os.path.join(MODEL_DIR, "dementia_model.pkl")
FEATURE_PATH = os.path.join(MODEL_DIR, "feature_names.pkl")
THRESHOLD_PATH = os.path.join(MODEL_DIR, "threshold.pkl")


try:
    loaded_model = joblib.load(MODEL_PATH)

    # 🔥 FIX: handle tuple model
    if isinstance(loaded_model, tuple):
        model = loaded_model[0]
        print("⚠️ Model was saved as tuple → extracted model")
    else:
        model = loaded_model

    feature_names = joblib.load(FEATURE_PATH)
    threshold = joblib.load(THRESHOLD_PATH)

    print("✅ Model loaded (NO SCALER)")
    print("📌 Features:", feature_names)
    print("🎯 Threshold:", threshold)

except Exception as e:
    print("❌ Error loading model:", e)
    model = None
    feature_names = None
    threshold = 0.5


# =========================================================
# Risk Level
# =========================================================

def calculate_risk_level(probability):
    if probability < 0.3:
        return "Low"
    elif probability < 0.7:
        return "Medium"
    else:
        return "High"


# =========================================================
# Prediction Function (NO SCALING)
# =========================================================

def predict_and_store(user_id, questionnaire_data):

    if model is None:
        return {"error": "Model not loaded properly."}

    try:

        # -------------------------------------------------
        # Validate features
        # -------------------------------------------------

        missing = [f for f in feature_names if f not in questionnaire_data]

        if missing:
            return {"error": f"Missing features: {missing}"}

        # -------------------------------------------------
        # Arrange features
        # -------------------------------------------------

        ordered_features = [
            float(questionnaire_data[f])
            for f in feature_names
        ]

        print("\n📥 Input:", questionnaire_data)
        print("📊 Ordered:", ordered_features)

        # -------------------------------------------------
        # Convert to numpy (NO SCALING)
        # -------------------------------------------------

        input_array = np.array(ordered_features).reshape(1, -1)

        # -------------------------------------------------
        # Predict
        # -------------------------------------------------

        if hasattr(model, "predict_proba"):
            probability = float(model.predict_proba(input_array)[0][1])
        else:
            probability = float(model.predict(input_array)[0])

        prediction = 1 if probability >= threshold else 0

        print("📈 Probability:", probability)
        print("🧠 Prediction:", prediction)

        # -------------------------------------------------
        # Risk level
        # -------------------------------------------------

        risk_level = calculate_risk_level(probability)

        result = {
            "prediction": prediction,
            "probability": round(probability, 4),
            "risk_level": risk_level,
            "timestamp": datetime.utcnow().isoformat()
        }

        # -------------------------------------------------
        # Store in Firestore
        # -------------------------------------------------

        db = get_firestore_client()

        db.collection("users") \
          .document(user_id) \
          .collection("predictions") \
          .add({
              **result,
              "questionnaire": questionnaire_data
          })

        print("✅ Stored\n")

        return result

    except Exception as e:
        print("❌ Error:", e)
        return {"error": str(e)}
