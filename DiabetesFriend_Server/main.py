from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import StreamingResponse
from pymongo import MongoClient
import uvicorn
import json
import asyncio
import os
import datetime
import google.generativeai as genai
import traceback

# ---------------------------------------------------------
# SETUP
# ---------------------------------------------------------
app = FastAPI()

MONGO_URL = os.environ.get("MONGO_URL")
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY")

# Correct Model ID for Dec 2025 (Removed the .0)
TARGET_MODEL = "gemini-3-pro-preview"

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

# Configure SDK Globally
if GEMINI_API_KEY:
    genai.configure(api_key=GEMINI_API_KEY)
else:
    print("CRITICAL: GEMINI_API_KEY is not set.")

@app.get("/")
def read_root():
    return {"status": "DiabetesFriend Server Running", "model": TARGET_MODEL}

# ---------------------------------------------------------
# HELPER: CONVERT FLUTTER JSON TO SDK FORMAT
# ---------------------------------------------------------
def parse_flutter_body_to_sdk(body):
    """
    Converts the raw JSON from Flutter into the list format 
    expected by the Google GenAI SDK.
    """
    contents = body.get("contents", [])
    converted_contents = []
    
    for msg in contents:
        role = msg.get("role", "user")
        parts = []
        for p in msg.get("parts", []):
            if "text" in p:
                parts.append({"text": p["text"]})
            elif "inline_data" in p:
                parts.append({
                    "mime_type": p["inline_data"]["mime_type"],
                    "data": p["inline_data"]["data"]
                })
        if parts:
            converted_contents.append({"role": role, "parts": parts})
            
    if not converted_contents:
        raise ValueError("Parsed contents are empty. Check Flutter request format.")
        
    return converted_contents

# ---------------------------------------------------------
# ENDPOINT 1: UNARY (NON-STREAMING)
# ---------------------------------------------------------
@app.post("/proxy_gemini")
async def proxy_gemini(request: Request):
    if not GEMINI_API_KEY:
        raise HTTPException(status_code=500, detail="API Key not set.")

    try:
        body = await request.json()
        
        # 1. Save "Pending" to DB
        saved_id = None
        if history_collection is not None:
            record = {
                "timestamp": datetime.datetime.utcnow(),
                "request_body": body,
                "status": "pending"
            }
            result = history_collection.insert_one(record)
            saved_id = result.inserted_id

        # 2. Use SDK (Async) instead of Requests (Blocking)
        # This prevents the server from freezing while waiting for Google
        model = genai.GenerativeModel(TARGET_MODEL)
        converted_contents = parse_flutter_body_to_sdk(body)
        
        # Generate Async
        response = await model.generate_content_async(converted_contents)
        
        # 3. Extract Text safely
        response_text = ""
        try:
            response_text = response.text
        except ValueError:
            # This happens if the model blocked the response (Safety Filters)
            response_text = "Error: Response blocked by safety filters."

        # 4. Construct Response matching REST format for your Flutter App
        # Flutter expects: { "candidates": [ { "content": { "parts": [ { "text": "..." } ] } } ] }
        response_data = {
            "candidates": [
                {
                    "content": {
                        "parts": [
                            {"text": response_text}
                        ],
                        "role": "model"
                    }
                }
            ]
        }

        # 5. Update DB
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

    except Exception as e:
        traceback.print_exc()
        if history_collection is not None and saved_id:
             history_collection.update_one(
                {"_id": saved_id},
                {"$set": {"error": str(e), "status": "failed"}}
            )
        raise HTTPException(status_code=500, detail=str(e))

# ---------------------------------------------------------
# ENDPOINT 2: STREAMING
# ---------------------------------------------------------
@app.post("/proxy_gemini_stream")
async def proxy_gemini_stream(request: Request):
    if not GEMINI_API_KEY:
         raise HTTPException(status_code=500, detail="API Key not set.")

    try:
        body = await request.json()
        
        saved_id = None
        if history_collection is not None:
            record = {
                "timestamp": datetime.datetime.utcnow(),
                "request_body": body,
                "status": "pending_stream"
            }
            result = history_collection.insert_one(record)
            saved_id = result.inserted_id

        # Prepare Model
        converted_contents = parse_flutter_body_to_sdk(body)
        model = genai.GenerativeModel(TARGET_MODEL)

        async def generate():
            full_text_accumulator = ""
            try:
                # SDK Stream
                response_stream = await model.generate_content_async(converted_contents, stream=True)
                
                async for chunk in response_stream:
                    # FIX: Safety Check to prevent 500 crashes on blocked content
                    text_fragment = ""
                    try:
                        text_fragment = chunk.text
                    except ValueError:
                        # Chunk was blocked or empty
                        continue 

                    if text_fragment:
                        full_text_accumulator += text_fragment
                        yield f"data: {json.dumps({'text': text_fragment})}\n\n"
                        
            except Exception as stream_e:
                print(f"Streaming Error: {stream_e}")
                yield f"data: {json.dumps({'error': str(stream_e)})}\n\n"

            finally:
                 # Update DB with full text
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
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Proxy Error: {str(e)}")

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", 8000)))
