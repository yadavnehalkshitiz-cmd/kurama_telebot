# Video Gallery Export Design

## Goal

Keep the new download export action buildable and truthful about what the
installed `gal` package supports.

## Behavior

- Completed video downloads show **Save to Gallery** and use
  `Gal.putVideo`.
- Audio and document downloads do not show **Save to Gallery**. Their existing
  **Share** action remains the supported export path.
- Missing-file, progress, success, and failure messages remain unchanged for
  video exports.

## Scope

This change does not add an Android MediaStore integration for audio, change
download storage, or modify cached third-party packages. The existing AGP 9
compatibility fixes remain limited to applying the external Kotlin plugin where
the project and affected plugins require it.

## Verification

1. Confirm the current release build fails on the nonexistent `Gal.putAudio`
   member.
2. Run Flutter analysis and tests after the UI/source change.
3. Run `flutter build apk --release` and confirm a fresh release APK is
   produced.
