import firebase_admin
from firebase_admin import credentials, firestore
import os
import json

_db = None


def initialize_firebase():
    global _db

    if not firebase_admin._apps:
        try:
            # 🔥 Get JSON from environment variable
            firebase_json = os.getenv("FIREBASE_KEY")

            if not firebase_json:
                raise Exception("FIREBASE_KEY not found in environment")

            # 🔥 Convert string → dict
            cred_dict = json.loads(firebase_json)

            # 🔥 Initialize Firebase
            cred = credentials.Certificate(cred_dict)
            firebase_admin.initialize_app(cred)

            print("✅ Firebase initialized from ENV")

        except Exception as e:
            print("❌ Firebase initialization failed:", e)
            raise

    _db = firestore.client()
    return _db


def get_firestore_client():
    global _db

    if _db is None:
        _db = initialize_firebase()

    return _db