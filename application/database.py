import firebase_admin
from firebase_admin import credentials, firestore

# Initialize without explicit keys (uses Cloud Run's Service Account)
if not firebase_admin._apps:
    firebase_admin.initialize_app()

db = firestore.client()
