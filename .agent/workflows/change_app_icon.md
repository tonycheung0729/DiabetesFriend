---
description: Workflow to change the Android/iOS app icon using flutter_launcher_icons
---

# Change App Icon Workflow

This guide details how to update the app icon using the original image file provided.

## 1. Prerequisites

Ensure you have the icon image file ready. 
For this project, the user stated path is: `C:\CodexAppDev\DiabetesFriend\DiabetesFriend_AppIcon\DiabetesFriend_AppiconImg.png`

## 2. Add Dependency

Add `flutter_launcher_icons` to your `dev_dependencies` in `pubspec.yaml` if not present.

```yaml
dev_dependencies:
  flutter_launcher_icons: "^0.13.1"
```

## 3. Configure Icon 

Add the configuration to `pubspec.yaml` (root level) or `flutter_launcher_icons.yaml`. 
For this project, we will add it to `pubspec.yaml`:

```yaml
flutter_icons:
  android: true
  ios: true
  image_path: "C:\\CodexAppDev\\DiabetesFriend\\DiabetesFriend_AppIcon\\DiabetesFriend_AppiconImg.png"
  min_sdk_android: 21 # Optional
```

*Note: Use double backslashes `\\` for Windows paths in YAML.*

## 4. Run Commands

Open the terminal in the project root (`C:\CodexAppDev\DiabetesFriend`) and run:

1.  **Get Dependencies**:
    ```powershell
    flutter pub get
    ```

2.  **Generate Icons**:
    ```powershell
    dart run flutter_launcher_icons
    ```
    *(This command will resize your image and generate all necessary mipmap folders for Android and Assets for iOS).*

3.  **Build App**:
    ```powershell
    flutter build apk
    ```

## 5. Verify

Install the new APK (`build/app/outputs/flutter-apk/糖友v0.7.apk`) and check the icon on your phone's home screen.
