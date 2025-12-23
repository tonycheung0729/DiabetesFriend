# DiabetesFriend Developer Guide

This document provides a technical overview of the **DiabetesFriend** (糖友) application. It is intended for developers who will maintain, debug, or extend the project.

## 🏗️ Project Architecture
 
The application follows a simple **MVVM-like** architecture using `Provider` for state management and `Hive` for local persistence.
 
### Connectivity Modes
*   **Direct Mode** (Default): App talks directly to Google Gemini API. (Blocked in CN/HK).
*   **Proxy Mode** (Active): App talks to a custom **Python/FastAPI Proxy Server** hosted on **Vercel**, which forwards requests to Google. This allows usage in restricted regions and provides a **MongoDB** cloud backup.

### Directory Structure
```
lib/
├── main.dart                  # Entry point, Routing, UI Screens (Home & Detail)
├── models/
│   ├── food_entry.dart        # Data Model (Hive Object)
│   └── food_entry.g.dart      # Hive Adapter (Generated)
└── services/
    └── gemini_service.dart    # AI Integration (Points to Proxy URL)

DiabetesFriend_Server/         # Python Proxy Server Code
├── main.dart                  # FastAPI Server Logic
├── vercel.json                # Vercel Config
└── requirements.txt           # Python Dependencies
```

## 🧩 Key Components

### 1. State Management (`FoodProvider` in `main.dart`)
*   **Role**: Manages the list of `FoodEntry` objects and handles UI state (`isLoading`).
*   **Persistence**: Interacts directly with the Hive box `food_entries`.
*   **Logic**:
    *   `analyzeAndSave(File image)`: Orchestrates image analysis.
    *   `analyzeHealthAndSave(String symptoms)`: **[NEW]** Handles text-based symptom analysis.
    *   `generateMealPlanAndSave()`: Generates the 1-day meal plan.
    *   `sendChatMessage(...)`: Manages multi-turn chat.

### 2. AI Service (`GeminiService`)
*   **Role**: interface for AI calls.
*   **Architecture Change**: Now points to `https://diabetes-friend.vercel.app/proxy_gemini` instead of Google directly.
*   **Key Methods**:
    *   `analyzeHealth(String)`: Sends detailed medical prompt with user background (Type 2 + No Gallbladder).

### 3. Data Model (`FoodEntry`)
*   **Storage**: Stored in Hive (`Box<FoodEntry>`) + Cloud Backup (MongoDB via Proxy).
*   **Fields**:
    *   `imagePath`: Path to the local file. **Special Values**:
        *   `""` (Empty String): Text-Only Food entry.
        *   `"MEAL_PLAN"`: Meal Plan entry.
        *   `"HEALTH_QUERY"`: **[NEW]** Health/Symptom Diagnosis entry.
    *   `chatHistory`: `List<String>` conversation turns.

## 🛠️ Setup & specific Workflows

### 1. Prerequisites
*   Flutter SDK (Compatible with Dart 3+)
*   Valid Gemini API Key (Hardcoded in `GeminiService` - *Consider moving to `.env` for production*).

### 2. Code Generation
If you modify `lib/models/food_entry.dart` (Hive Object), you **MUST** run the build runner to regenerate the adapter:
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

### 3. Building for Release
```bash
flutter build apk --release
```

## 🐛 Common Issues & Troubleshooting

### **Crash: `NoSuchMethodError: The method '[]' was called on null`**
*   **Cause**: This usually happens when the Gemini API returns a blocked response (Safety Ratings) or an empty body.
*   **Fix**: The `GeminiService` now strictly checks `json['candidates'][0]['content']['parts']` availability before access. **Do not remove these null checks.**

### **Context Shadowing in Dialogs**
*   **Issue**: Using `Navigator.pop(context)` inside a `showModalBottomSheet` builder might close the wrong route if `BuildContext` is confused.
*   **Fix**: Ensure you use the correct context handles. In `_showImageSourceDialog`, we explicitly use the sheet's context context to close it before opening the picker.

### **Android Permissions**
*   **Images**: On Android 13+, `READ_MEDIA_IMAGES` is required. On older versions, `READ_EXTERNAL_STORAGE`. The `gal` package handles saving to the gallery, but ensure `AndroidManifest.xml` has proper `<uses-permission>` tags.

## 🚀 Future Improvements Checklist
- [ ] **Secure API Key**: Move the Gemini API key to a `.env` file using `flutter_dotenv`.
- [ ] **Refactor UI**: Split `main.dart` into separate files (`screens/home_screen.dart`, `screens/detail_screen.dart`, `providers/food_provider.dart`) for better maintainability.
- [ ] **Stream Responses**: Implement streaming for the `chatFood` method to improve perceived latency for long answers (like Meal Plans).

---
*Maintained by CodexAppDev Team*
