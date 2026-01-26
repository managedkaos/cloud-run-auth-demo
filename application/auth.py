from fastapi import Request, HTTPException
from firebase_admin import auth

async def get_current_user(request: Request):
    session_token = request.cookies.get("session")
    if not session_token:
        return None
    try:
        # Verify the token sent from the frontend login
        # Note: In a production app with session cookies management, you might verify a session cookie
        # rather than a raw ID token if you were using create_session_cookie.
        # But per the user request, we are simple verifying the token passed as a cookie.
        decoded_token = auth.verify_id_token(session_token)
        return decoded_token
    except Exception:
        return None
