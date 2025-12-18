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

## 2. Deployment (Vercel - Recommended)

1.  **Upload to GitHub**:
    *   Upload the server files (`main.py`, `requirements.txt`, `vercel.json`) to your GitHub repository.

2.  **Deploy on Vercel**:
    *   Go to [vercel.com](https://vercel.com/) and Sign Up/Login with GitHub.
    *   Click "Add New..." -> "Project".
    *   Import your `DiabetesFriend` repository.
    *   **Configure Project**:
        *   **Root Directory**: Click "Edit" and select `DiabetesFriend_Server`.
        *   **Environment Variables**:
            *   `MONGO_URL`: `mongodb+srv://admin:YOUR_PASSWORD@diaapp.uwp3kcp.mongodb.net/?appName=DiaApp`
            *   `GEMINI_API_KEY`: Your Google Gemini API Key.
    *   Click **Deploy**.

## 3. Connect App

Once deployed, copy the Domain (e.g., `https://diabetesfriend-server.vercel.app`).

Update your Flutter app's `gemini_service.dart`:
Change the `_baseUrl` to:
`https://your-app-url.vercel.app/proxy_gemini`
