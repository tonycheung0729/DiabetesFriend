# DiabetesFriend Server

This is the proxy server for the DiabetesFriend App. It allows the app to work in regions where Google is blocked (by acting as a middleman) and backs up all chat history to MongoDB.

## 1. Setup

### Prerequisites
1.  **Render Account** (for hosting).
2.  **MongoDB Atlas Account** (for database).
3.  **Google Gemini API Key**.

### Files
*   `main.py`: The server logic.
*   `requirements.txt`: List of required Python libraries.

## 2. Deployment (How to put it online)

1.  **Upload to GitHub**:
    *   Create a new repository on GitHub (e.g., `my-diabetes-server`).
    *   Upload these files (`main.py`, `requirements.txt`) to it.

2.  **Deploy on Render**:
    *   Go to Dashboard -> New Web Service.
    *   Connect your GitHub repo.
    *   **Runtime**: Python 3.
    *   **Start Command**: `uvicorn main:app --host 0.0.0.0 --port $PORT`
    *   **Environment Variables** (Add these in the Dashboard):
        *   `MONGO_URL`: `mongodb+srv://admin:YOUR_PASSWORD@diaapp.uwp3kcp.mongodb.net/?appName=DiaApp` (Replace `YOUR_PASSWORD` with your real password).
        *   `GEMINI_API_KEY`: Your raw Google Gemini API key (starts with AIza...).

## 3. Connect App

Once deployed, Render will give you a URL (e.g., `https://my-diabetes-server.onrender.com`).

Update your Flutter app's `gemini_service.dart`:
Change the `_baseUrl` to:
`https://my-diabetes-server.onrender.com/proxy_gemini`
