# Habits Tracker

One Flutter codebase powers both:

- the offline-capable Android app;
- the GitHub Pages web app, including Felix and Uncle modes.

Both clients synchronize through the same Google Apps Script endpoint and Google Sheet. Local edits are queued while offline and uploaded when a connection returns.

## Run locally

```powershell
cd flutter_app
flutter pub get
flutter run
```

## Verify

```powershell
cd flutter_app
flutter analyze
flutter test
flutter build apk
flutter build web --base-href "/habits-tracker/"
```

The Android APK is written to:

```text
flutter_app/build/app/outputs/flutter-apk/app-release.apk
```

## Web deployment

Pushes to `main` that change `flutter_app/` automatically build and deploy GitHub Pages through `.github/workflows/deploy-web.yml`.

Live site: <https://fescofesco.github.io/habits-tracker/>

## Google Apps Script

`google_apps_script.gs` is the backend source. Deploy it as a Google Apps Script web app with:

- Execute as: **Me**
- Access: **Anyone**

The API upserts one row per date and person, supports retrieving a day on another device, and returns birthday information. When this file changes, create a new Apps Script deployment version before using the updated clients.

## Android-specific features

The Flutter Android build provides local reminders, speech input, book-cover capture, call/SMS contact checks, and opt-in WhatsApp notification tracking. Android requires the user to approve the corresponding permissions and notification access.
