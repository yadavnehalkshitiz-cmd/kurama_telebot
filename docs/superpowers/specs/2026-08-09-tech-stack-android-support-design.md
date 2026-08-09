# Tech Stack and Android Support Design

## Goal

Present the repository's real technology stack clearly and make the mobile
app's stated Android 9+ support floor true in the build configuration.

## Repository Presentation

Add a concise **Tech Stack & Languages** section to the root README:

- **Primary languages:** Dart for the Flutter mobile app and Python for the
  Telegram bot/API.
- **Mobile:** Flutter, with Kotlin Android and Swift iOS platform integration.
- **Backend:** FastAPI, python-telegram-bot, yt-dlp, and Uvicorn.
- **Android build:** Gradle, Android Gradle Plugin, and JVM 17. JVM 17 is a
  build target, not a primary project language.
- **Delivery:** Docker, GitHub Actions, and Render.

Do not add decorative badge clutter or hide legitimate platform source with
GitHub Linguist overrides. GitHub's current language breakdown already
correctly identifies Dart and Python as the dominant languages.

## Android Support

Set the Android application minimum SDK explicitly to API 28, which corresponds
to Android 9. Existing target and compile SDK behavior remains unchanged.

## Security

Keep the production API credential out of source control. The mobile app reads
`KURAMA_API_KEY` from `String.fromEnvironment`, supplied with a build-time
`--dart-define` or by a saved in-app server configuration.

## Verification

Run the complete Flutter test suite, Flutter analysis, and a release APK build.
Inspect the resulting Gradle configuration/artifact and confirm the source tree
contains no hardcoded production API credential.
