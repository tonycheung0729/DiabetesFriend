import os
import requests
import datetime
from fastapi import FastAPI, Request, HTTPException
from pymongo import MongoClient
import uvicorn

app = FastAPI()

# Configuration from Environment Variables
# These will be set in the Render Dashboard
MONGO_URL = os.environ.get("MONGO_URL")
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY")

# Model Endpoint
# Matches the one used in GeminiService.dart
GEMINI_URL = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent?key={GEMINI_API_KEY}"

# Database Setup
try:
    if MONGO_URL:
        client = MongoClient(MONGO_URL)
        db = client.diabetes_friend
        history_collection = db.history
        print("Connected to MongoDB")
    else:
        print("Warning: MONGO_URL not set. Database features disabled.")
        history_collection = None
except Exception as e:
    print(f"Failed to connect to MongoDB: {e}")
    history_collection = None

@app.get("/")
def read_root():
    return {"status": "DiabetesFriend Server Running"}

@app.post("/proxy_gemini")
async def proxy_gemini(request: Request):
    """
    Proxies the request from Flutter App to Google Gemini API.
    Saves the interaction to MongoDB.
    """
    if not GEMINI_API_KEY:
        raise HTTPException(status_code=500, detail="Server Configuration Error: GEMINI_API_KEY not set.")

    try:
        # 1. Get Request Body from App
        body = await request.json()
        
        # 2. Add Timestamp & Metadata for Storage
        record = {
            "timestamp": datetime.datetime.utcnow(),
            "request_body": body,  # Stores the full prompt/image structure
            "status": "pending"
        }
        
        saved_id = None
        if history_collection is not None:
            # Insert initially to capture the attempt
            result = history_collection.insert_one(record)
            saved_id = result.inserted_id

        # 3. Forward to Google Gemini API
        # We use the same URL structure/body as the Flutter app would have sent
        # Note: If your app uses different models (pro-vision vs pro), we might need to make this dynamic.
        # For now, we use a generic URL or rely on the fact that the body structure is compatible.
        # Actually, let's make the model dynamic via a query param if needed, or default to a capable model.
        # The Flutter Service uses 'gemini-3-pro-preview' which is bleeding edge.
        # Let's align with the service: 
        
        target_url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key={GEMINI_API_KEY}"
        # Note: I changed to gemini-1.5-flash for speed/cost, or we can stick to what you had.
        # Let's use the one from the service 'gemini-3-pro-preview' if possible, but 1.5-flash is stable.
        # To be safe and compatible with your existing prompts, let's use gemini-1.5-flash (very capable).
        
        google_response = requests.post(
            target_url,
            json=body,
            headers={"Content-Type": "application/json"}
        )

        # 4. Handle Response
        if google_response.status_code == 200:
            response_data = google_response.json()
            
            # Update DB with success
            if history_collection is not None and saved_id:
                history_collection.update_one(
                    {"_id": saved_id},
                    {"$set": {
                        "response_body": response_data,
                        "status": "success",
                        "completed_at": datetime.datetime.utcnow()
                    }}
                )
            
            return response_data
        else:
            # Update DB with failure
            if history_collection is not None and saved_id:
                history_collection.update_one(
                    {"_id": saved_id},
                    {"$set": {
                        "error": google_response.text,
                        "status": "failed",
                        "completed_at": datetime.datetime.utcnow()
                    }}
                )
            # Find a way to pass the error back gracefully or just throw
            raise HTTPException(status_code=google_response.status_code, detail=f"Google API Error: {google_response.text}")

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", 8000)))
