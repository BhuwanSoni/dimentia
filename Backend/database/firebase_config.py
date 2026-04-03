import firebase_admin
from firebase_admin import credentials, firestore
import os

# Global Firestore instance
_db = None


def initialize_firebase():
    """
    Initialize Firebase Admin SDK.
    Prevents multiple initializations.
    """

    global _db

    if not firebase_admin._apps:
        try:
            # Path to your firebase key
            base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
            cred_path = os.path.join(base_dir, "firebase_key.json")

            cred = credentials.Certificate(cred_path)
            firebase_admin.initialize_app(cred)

            print("✅ Firebase initialized successfully.")

        except Exception as e:
            print("❌ Firebase initialization failed:", e)
            raise

    _db = firestore.client()
    return _db


def get_firestore_client():
    """
    Returns Firestore client.
    Automatically initializes if not already done.
    """

    global _db

    if _db is None:
        _db = initialize_firebase()

    return _db
