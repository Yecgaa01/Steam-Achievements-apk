# Steam Achievements

Steam Achievements is a Flutter Android app for viewing Steam achievement progress with a trophy-style interface.

## Features

- Steam profile and owned games overview.
- Achievement details with hidden descriptions support.
- Achievement filtering and sorting.
- Recent games sorting using Steam last played data.
- Foreground sync for achievement progress.
- GitHub Release update checker/installer.

## Build

Requirements:

- Flutter SDK
- Android SDK
- JDK 17

Install dependencies:

```bash
flutter pub get
```

Analyze:

```bash
flutter analyze
```

Build release APK:

```bash
flutter build apk --release
```

## Release signing

This repository does not include release signing secrets.

Create `android/key.properties` locally:

```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=steam-achievements
storeFile=../keystore/steam-achievements-release.jks
```

Keep the keystore and `key.properties` private. Do not commit them.

## GitHub updater

The in-app updater checks the latest release from:

```text
Yecgaa01/Steam-Achievements-apk
```

The APK asset must be named:

```text
release.apk
```

## Notes

This app is not affiliated with Valve or Steam.
