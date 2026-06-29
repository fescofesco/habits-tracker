# Habits Tracker

This is the native Android version of the streak app. It avoids PWA/browser background limitations by using Android local alarms and notifications.

## What is implemented

- Fast checkbox-first daily habit UI
- Native Android notification reminder using `AlarmManager`
- Voice comments via Android speech recognition
- Local storage on the phone with `SharedPreferences`
- Finished-book capture: photograph the cover, recognize its text on-device, and look up title/author through the non-Amazon Open Library API
- Reading totals for finished books and known page counts, with the original cover photo kept locally
- Optional Google Sheets sync through your existing Google Apps Script web app URL
- Birthday check through Google Apps Script Calendar access

## Habits included

- Reading
- Eating before 19:00
- Get up before 08:00
- Shut off phone at 22:00
- Do 10 pushups
- Real-life conversation with a stranger
- Plus: got her number
- Phone call to a close one
- Birthday message sent
- Birthday: called instead

## Build/install

1. Install Android Studio on your PC.
2. Open this repository in Android Studio.
3. Let Gradle sync.
4. Connect your Android phone with USB debugging enabled.
5. Press **Run**.

Android Studio will install the APK directly on your phone.

## Google Sheets / Calendar setup

1. Create/open your Google Sheet.
2. Copy its spreadsheet ID from the URL.
3. Open **Extensions → Apps Script**.
4. Paste `google_apps_script.gs`.
5. Replace:

```js
const SPREADSHEET_ID = 'PASTE_YOUR_GOOGLE_SHEET_ID_HERE';
```

6. Deploy as **Web app**.
7. Execute as: **Me**.
8. Who has access: **Anyone with the link**.
9. Copy the web app URL into the Android app field.

The first Calendar birthday check may ask for Google permissions in Apps Script.

## Notes

- For reliable notifications, disable battery optimization for the app if Android delays alarms.
- On Android 13+, allow notification permission when asked.
- On Android 12+, exact alarms may require system permission depending on device settings.
