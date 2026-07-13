# HTML Runner Pro 🐟
**Version 1.6.7+2** — Made by Chirag Shylendra / Fish Gang Co.

A Holo-themed Flutter app for Android to create, organise, and run HTML projects locally. Zero ads. Forever free. Made in India.

## ✨ What's new in this build
- **Fish Gang Auth** — Google Sign-In replaced with Fish Gang Account (Firebase REST API, no SDK or google-services.json needed). Register at fish-gang.netlify.app.
- **Theme.Holo.Dark / Theme.Holo.Light** — Full Holo theme system. Defaults to dark. Light togglable via settings.
- **Permissions screen** — Storage/media permissions requested on first launch via a dedicated screen, not mid-session popups.
- **File import** — Now accepts any file type. HTML files open in the IDE; all others open via Android's system app chooser.
- **IDE line numbers fixed** — Gutter rewritten with `Transform.translate` scroll sync. No more misalignment or white-out at bottom.
- **SD card install** — `android:installLocation="preferExternal"` so Android can move the app to SD card.
- **Fat APK** — Single APK covering armeabi-v7a (Redmi Go) and arm64-v8a (DOMO Slate).

## 📂 Project Structure
```
lib/
  main.dart          — entire app (single file)
android/
  app/
    build.gradle     — minSdk 21, targetSdk 33, abiFilters arm+arm64
    src/main/
      AndroidManifest.xml
      res/values/styles.xml        — LaunchTheme (fixes blank launch screen)
      res/values-night/styles.xml  — dark variant
codemagic.yaml       — CI: flutter build apk --release (fat APK)
pubspec.yaml
```

## 🛠 Building from Source
```bash
flutter pub get
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

## 🏗 Codemagic CI
Add `codemagic.yaml` to repo root. Codemagic will detect it automatically and use the `android-release` workflow.

## 🔑 Fish Gang Auth
Uses Firebase Identity Toolkit REST API against the `fish-gang-website` Firebase project.
No `google-services.json` required — auth is pure HTTP via the `http` package.

## ⚖️ License & Attribution
MIT License.
**Redistribution requirement:** Credit must be given to the original author: **Chirag Shylendra** (Fish Gang Co.).
