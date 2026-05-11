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

MODEL_PATH     = os.path.join(MODEL_DIR, "dementia_model.pkl")
FEATURE_PATH   = os.path.join(MODEL_DIR, "feature_names.pkl")
THRESHOLD_PATH = os.path.join(MODEL_DIR, "threshold.pkl")

try:
    loaded_model = joblib.load(MODEL_PATH)

    # Handle model saved as a tuple
    if isinstance(loaded_model, tuple):
        model = loaded_model[0]
        print("⚠️  Model was saved as tuple → extracted model[0]")
    else:
        model = loaded_model

    feature_names = joblib.load(FEATURE_PATH)
    threshold     = joblib.load(THRESHOLD_PATH)

    print("✅ Model loaded (NO SCALER)")
    print("📌 Features :", feature_names)
    print("🎯 Threshold:", threshold)

except Exception as e:
    print("❌ Error loading model:", e)
    model         = None
    feature_names = None
    threshold     = 0.5


# =========================================================
# Risk Level
# =========================================================

def calculate_risk_level(probability: float) -> str:
    """
    Thresholds:
      < 0.30  → Low
      < 0.70  → Medium
      >= 0.70 → High
    """
    if probability < 0.3:
        return "Low"
    elif probability < 0.7:
        return "Medium"
    else:
        return "High"


# =========================================================
# Prediction Function (NO SCALING)
#
# GENDER ENCODING CONVENTION (must match training data):
#   0 = Male
#   1 = Female
#
# The Flutter client sends gender=0 for Male, gender=1 for
# Female.  Do NOT reverse this mapping here.
# =========================================================

def predict_and_store(user_id: str, questionnaire_data: dict) -> dict:

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
        # Arrange features in training order
        # -------------------------------------------------
        ordered_features = [
            float(questionnaire_data[f])
            for f in feature_names
        ]

        print("\n📥 Input   :", questionnaire_data)
        print("📊 Ordered :", ordered_features)

        # -------------------------------------------------
        # Convert to numpy array (NO SCALING)
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
        print("🧠 Prediction :", prediction)

        # -------------------------------------------------
        # Risk level
        # -------------------------------------------------
        risk_level = calculate_risk_level(probability)

        result = {
            "prediction":  prediction,
            "probability": round(probability, 4),
            "risk_level":  risk_level,
            "timestamp":   datetime.utcnow().isoformat(),
        }

        # -------------------------------------------------
        # Store in Firestore
        #
        # BUG FIX: Previously this service wrote to Firestore AND the Flutter
        # client ALSO wrote to Firestore after receiving the response.  That
        # caused every test to appear TWICE in Test History (two documents
        # with timestamps ~milliseconds apart).
        #
        # Fix: The server is the SINGLE writer.  The Flutter client must NOT
        # call userRef.collection("predictions").add(…) after receiving the
        # response.  See questionnaire_page.dart _calculateScore().
        # -------------------------------------------------
        db = get_firestore_client()

        db.collection("users") \
          .document(user_id) \
          .collection("predictions") \
          .add({
              **result,
              "questionnaire": questionnaire_data,
          })

        # Also update the top-level user document (last_test summary)
        db.collection("users") \
          .document(user_id) \
          .set({
              "probability": result["probability"],
              "risk_level":  risk_level,
              "last_test":   result["timestamp"],
          }, merge=True)

        print("✅ Stored in Firestore\n")

        return result

    except Exception as e:
        print("❌ Prediction error:", e)
        return {"error": str(e)}