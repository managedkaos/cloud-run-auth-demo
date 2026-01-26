from fastapi import FastAPI, Request, Form, Depends, Response, HTTPException
from fastapi.responses import RedirectResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from fastapi.staticfiles import StaticFiles
from database import db
from auth import get_current_user
from pydantic import BaseModel

app = FastAPI()
app.mount("/static", StaticFiles(directory="static"), name="static")
templates = Jinja2Templates(directory="templates")

class SessionRequest(BaseModel):
    token: str

@app.get("/")
async def root():
    return RedirectResponse(url="/dashboard")

@app.get("/login")
async def login(request: Request):
    return templates.TemplateResponse("login.html", {"request": request})

@app.post("/auth/session")
async def create_session(request: Request, session_data: SessionRequest):
    # In a real production app, you would create a session cookie using firebase_admin.auth.create_session_cookie
    # For this demo, we are setting the ID token as a cookie directly as requested.
    response = JSONResponse(content={"status": "success"})
    # limit max_age to 1 hour or less for ID tokens
    response.set_cookie(key="session", value=session_data.token, httponly=True, secure=True)
    return response

@app.get("/logout")
async def logout(response: Response):
    resp = RedirectResponse(url="/login")
    resp.delete_cookie("session")
    return resp

@app.get("/dashboard")
async def dashboard(request: Request, user=Depends(get_current_user)):
    if not user:
        return RedirectResponse(url="/login")

    # READ: Get items from Firestore for this specific user
    items_ref = db.collection("items").where("uid", "==", user["uid"])
    items = [doc.to_dict() | {"id": doc.id} for doc in items_ref.stream()]

    return templates.TemplateResponse("dashboard.html", {"request": request, "items": items, "user": user})

@app.post("/items/create")
async def create_item(name: str = Form(...), user=Depends(get_current_user)):
    if not user:
        return RedirectResponse(url="/login", status_code=303)

    # CREATE: Add to Firestore
    db.collection("items").add({
        "name": name,
        "uid": user["uid"]
    })
    return RedirectResponse(url="/dashboard", status_code=303)

@app.get("/items/{item_path}/edit")
async def edit_item(request: Request, item_path: str, user=Depends(get_current_user)):
    if not user:
        return RedirectResponse(url="/login")

    doc_ref = db.collection("items").document(item_path)
    doc = doc_ref.get()

    if not doc.exists:
        raise HTTPException(status_code=404, detail="Item not found")

    item_data = doc.to_dict()
    if item_data.get("uid") != user["uid"]:
         raise HTTPException(status_code=403, detail="Not authorized")

    return templates.TemplateResponse("edit_item.html", {"request": request, "item": item_data, "item_id": item_path})

@app.post("/items/{item_path}/update")
async def update_item(item_path: str, name: str = Form(...), user=Depends(get_current_user)):
    if not user:
        raise HTTPException(status_code=401)

    doc_ref = db.collection("items").document(item_path)
    doc = doc_ref.get()

    if not doc.exists:
        raise HTTPException(status_code=404, detail="Item not found")

    if doc.to_dict().get("uid") != user["uid"]:
         raise HTTPException(status_code=403, detail="Not authorized")

    doc_ref.update({"name": name})
    return RedirectResponse(url="/dashboard", status_code=303)

@app.post("/items/{item_path}/delete")
async def delete_item(item_path: str, user=Depends(get_current_user)):
    if not user:
        raise HTTPException(status_code=401)

    doc_ref = db.collection("items").document(item_path)
    doc = doc_ref.get()

    if not doc.exists:
        raise HTTPException(status_code=404, detail="Item not found")

    if doc.to_dict().get("uid") != user["uid"]:
         raise HTTPException(status_code=403, detail="Not authorized")

    doc_ref.delete()
    return RedirectResponse(url="/dashboard", status_code=303)

@app.exception_handler(404)
async def custom_404_handler(request: Request, exc: HTTPException):
    return templates.TemplateResponse("404.html", {"request": request}, status_code=404)
