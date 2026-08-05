# Release Build Hardening Design

## Goal

Make KuramaBot's tagged GitHub releases reliably produce a Windows ZIP and a properly signed Android APK, while preserving pull-request build validation.

## Windows build

The Windows job will use the explicit `windows-2022` GitHub-hosted runner instead of `windows-latest`. The current `windows-latest` image uses Visual Studio 2026/MSVC 14.51, which rejects deprecated experimental coroutine headers used by the current Windows implementations of `flutter_inappwebview` and `local_auth`. Pinning the runner provides a stable Visual Studio 2022 toolchain until compatible plugin releases are available.

The workflow will continue generating the Windows runner before compiling because the repository does not commit a `windows/` platform directory.

## Android signing

A new permanent KuramaBot upload keystore will be generated because no existing production signing key exists. The keystore and a local credentials file will be ignored by Git and must never be committed. The credentials file will contain generated values for the store password, key password, and alias so the key can be backed up securely.

Gradle will load release signing values from `android/key.properties` when that file exists. Pull-request builds may fall back to debug signing so CI can compile untrusted contributions without release secrets. Tagged builds must not fall back: GitHub Actions will validate the required secrets, reconstruct the keystore and `key.properties`, and fail with a clear message before compilation if any release-signing secret is missing.

Required GitHub Actions secrets:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

The workflow will remove reconstructed signing files after the Android job, including on failure.

## Release behavior

Pull requests will run tests, analysis, an Android verification APK build, and the Windows build. They will not publish a GitHub Release.

Version tags matching `v*` will build the release-signed Android APK and the Windows ZIP. The publishing job will run only after both build jobs succeed.

## Local Windows support

Windows Developer Mode will be enabled on this workstation so Flutter can create plugin symlinks. This is a machine-level prerequisite and is independent of the GitHub Visual Studio 2026 failure.

## Tests and verification

Repository tests will assert that:

- the Windows job uses `windows-2022`;
- tagged builds validate and reconstruct all four Android signing secrets;
- the Gradle release build reads `key.properties` and uses the release signing configuration when present;
- Android platform generation remains disabled in CI.

Final verification will include the repository test suite, Flutter tests and analysis, a signed Android release build with certificate inspection, a Windows release build, artifact existence checks, and a clean Git status review.

## Key handling limitations

GitHub secrets cannot be configured until GitHub authentication is available. Local key generation and CI configuration can be completed first, but a tagged release must not be attempted until all four secrets are installed. The keystore and credentials need an external backup; losing the signing key can prevent future updates to installed applications.
