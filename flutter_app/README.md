# Streak Tracker (Flutter)

Cross-platform Android/iOS version of the habits tracker.

## Run and test

```powershell
flutter pub get
flutter test
flutter run
```

## Android

Create an APK with `flutter build apk --release`, or an app bundle for Google Play with
`flutter build appbundle --release`. Configure a permanent release signing key before distributing updates.

## iPhone / TestFlight

The iOS project must be signed and built on a Mac:

1. Install Flutter and Xcode on the Mac.
2. Open `ios/Runner.xcworkspace` in Xcode.
3. Select your Apple Developer team and set a unique bundle identifier.
4. Connect an iPhone and test the app once.
5. Choose **Product > Archive**, then upload to App Store Connect.
6. In App Store Connect, add the build to TestFlight and invite the tester by email or public link.

The minimum iOS version is 15.5 because on-device book-cover text recognition uses Google ML Kit.
