# Video Gallery Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a release APK while keeping Gallery export available only for completed video downloads.

**Architecture:** Add one pure format-capability helper to the existing media classification model and use it to conditionally build the download action menu. Guard the export handler with the same helper and route supported files only through `Gal.putVideo`; audio and document files retain the existing Share action.

**Tech Stack:** Flutter 3.41.9, Dart 3.11.5, `flutter_test`, `gal` 2.3.3, Gradle Kotlin DSL, Android Gradle Plugin 9.0.1, Kotlin Gradle Plugin 2.3.20.

## Global Constraints

- Completed video downloads show **Save to Gallery** and use `Gal.putVideo`.
- Audio and document downloads do not show **Save to Gallery**; their existing **Share** action remains available.
- Do not add an audio MediaStore dependency or edit cached third-party packages.
- Preserve all unrelated staged and unstaged user changes.
- Retain the existing AGP 9 fixes that apply `org.jetbrains.kotlin.android` to the app and to `audio_session`, `file_picker`, and `workmanager_android`.

---

### Task 1: Gate Gallery export by declared download format

**Files:**
- Modify: `kurama_mobile/test/models/media_file_type_test.dart`
- Modify: `kurama_mobile/lib/models/media_file_type.dart`
- Modify: `kurama_mobile/lib/screens/downloads_screen.dart:605-620,869-913`

**Interfaces:**
- Consumes: `DownloadTask.format`, whose supported values include `video`, `audio`, and `doc`.
- Produces: `bool supportsGalleryExport(String format)` and a video-only Gallery menu/handler.

- [ ] **Step 1: Write the failing capability test**

Append this group to `media_file_type_test.dart`:

```dart
group('supportsGalleryExport', () {
  test('allows video and rejects audio and documents', () {
    expect(supportsGalleryExport('video'), isTrue);
    expect(supportsGalleryExport(' VIDEO '), isTrue);
    expect(supportsGalleryExport('audio'), isFalse);
    expect(supportsGalleryExport('doc'), isFalse);
  });
});
```

- [ ] **Step 2: Run the focused test and verify RED**

Run: `flutter test test/models/media_file_type_test.dart`

Expected: FAIL because `supportsGalleryExport` is undefined.

- [ ] **Step 3: Add the minimal capability helper**

Append to `media_file_type.dart`:

```dart
bool supportsGalleryExport(String format) =>
    format.trim().toLowerCase() == 'video';
```

- [ ] **Step 4: Run the focused test and verify GREEN**

Run: `flutter test test/models/media_file_type_test.dart`

Expected: all media-file-type tests pass.

- [ ] **Step 5: Gate the action menu**

Import `../models/media_file_type.dart` in `downloads_screen.dart`, make the popup item list non-const, and conditionally include the constant Gallery item:

```dart
if (supportsGalleryExport(task.format))
  const PopupMenuItem(
    value: 'gallery',
    child: Text('Save to Gallery'),
  ),
```

- [ ] **Step 6: Remove unsupported Gallery calls**

At the start of `_saveToGallery`, after the missing-file guard, reject unsupported formats defensively:

```dart
if (!supportsGalleryExport(task.format)) {
  if (context.mounted) {
    _message(context, 'Gallery export is available for videos only. Use Share for this file.');
  }
  return;
}
```

Replace the `video`/`audio`/fallback dispatch with:

```dart
await Gal.putVideo(filePath);
```

- [ ] **Step 7: Re-run the focused test and analyzer**

Run:

```powershell
flutter test test/models/media_file_type_test.dart
flutter analyze --no-fatal-infos
```

Expected: the focused tests pass and analysis reports zero errors, including no reference to `Gal.putAudio`.

- [ ] **Step 8: Preserve the user's working tree**

Run `git diff --check` and inspect `git status -sb`. Do not commit the implementation because `downloads_screen.dart` already contains overlapping uncommitted user work; report the exact modified files instead.

### Task 2: Verify Android release output

**Files:**
- Verify: `kurama_mobile/android/app/build.gradle.kts`
- Verify: `kurama_mobile/android/build.gradle.kts`
- Generate: `kurama_mobile/build/app/outputs/flutter-apk/app-release.apk`

**Interfaces:**
- Consumes: the external Kotlin plugin declarations and the video-only Gallery source from Task 1.
- Produces: a fresh release APK from the user's shell Flutter SDK.

- [ ] **Step 1: Run the complete Flutter test suite**

Run: `flutter test`

Expected: all tests pass with zero failures.

- [ ] **Step 2: Build the release APK**

Run: `flutter build apk --release`

Expected: exit code 0 and output identifying `build/app/outputs/flutter-apk/app-release.apk`.

- [ ] **Step 3: Verify the artifact and working-tree scope**

Confirm the APK exists, has a fresh modification timestamp, and has nonzero size. Run `git diff --check`, inspect the diffs for the two Gradle files plus the three Gallery-export files, and verify no cached package source was modified.

- [ ] **Step 4: Preserve the user's working tree**

Do not commit implementation files because they overlap the user's active work. Report the APK path, size, build result, tests, analyzer result, and all source/config files changed by this fix.
