from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import StreamingResponse
from pymongo import MongoClient
import uvicorn
import json
import asyncio
import google.generativeai as genai

app = FastAPI()

# Configuration from Environment Variables
# These will be set in the Render Dashboard
MONGO_URL = os.environ.get("MONGO_URL")
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY")

# Model Endpoint
# Matches the one used in GeminiService.dart
GEMINI_URL = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-3-pro-preview:generateContent?key={GEMINI_API_KEY}"

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
        
        target_url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-3-pro-preview:generateContent?key={GEMINI_API_KEY}"
        # Ensure this model ID is accessible to your API Key.
        
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

@app.post("/proxy_gemini_stream")
async def proxy_gemini_stream(request: Request):
    """
    Proxies request to Gemini using Server-Sent Events (SSE) via Official SDK.
    """
    if not GEMINI_API_KEY:
         raise HTTPException(status_code=500, detail="Server Configuration Error: GEMINI_API_KEY not set.")

    try:
        body = await request.json()
        
        # Log attempt
        record = {
            "timestamp": datetime.datetime.utcnow(),
            "request_body": body,
            "status": "pending_stream"
        }
        saved_id = None
        if history_collection is not None:
            result = history_collection.insert_one(record)
            saved_id = result.inserted_id

        # Configure SDK
        genai.configure(api_key=GEMINI_API_KEY)
        
        # Parse Body to SDK format
        contents = body.get("contents", [])
        
        converted_contents = []
        for msg in contents:
            role = msg.get("role", "user")
            parts = []
            for p in msg.get("parts", []):
                if "text" in p:
                    parts.append({"text": p["text"]})
                elif "inline_data" in p:
                    # SDK expects 'mime_type' and 'data' directly in a dict (not wrapped in inline_data)
                    parts.append({
                        "mime_type": p["inline_data"]["mime_type"],
                        "data": p["inline_data"]["data"]
                    })
            converted_contents.append({"role": role, "parts": parts})

        # Select Model
        # Reverting to 1.5-pro because 3.0 likely does not exist and causes crashes
        model = genai.GenerativeModel("gemini-3-pro-preview") 

        async def generate():
            full_text_accumulator = ""
            try:
                # SDK Stream (Async)
                response_stream = await model.generate_content_async(converted_contents, stream=True)
                
                async for chunk in response_stream:
                    if chunk.text:
                        text_fragment = chunk.text
                        full_text_accumulator += text_fragment
                        # Yield SSE
                        yield f"data: {json.dumps({'text': text_fragment})}\n\n"
                        
            except Exception as e:
                yield f"data: {json.dumps({'error': str(e)})}\n\n"
                print(f"Stream Generate Error: {e}")

            finally:
                 # Update DB
                 if history_collection is not None and saved_id:
                     history_collection.update_one(
                        {"_id": saved_id},
                        {"$set": {
                            "response_text": full_text_accumulator,
                            "status": "success_stream",
                            "completed_at": datetime.datetime.utcnow()
                        }}
                    )

        return StreamingResponse(generate(), media_type="text/event-stream")

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", 8000)))
