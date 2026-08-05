# Release Build Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make tagged GitHub releases produce a Windows ZIP and a permanently signed Android APK while preserving safe pull-request validation.

**Architecture:** Pin the Windows job to the Visual Studio 2022 runner, teach Gradle to consume an ignored `key.properties` file, and reconstruct signing material from GitHub Actions secrets only for version tags. Generate one permanent local keystore, install its values as repository secrets, and verify both release artifacts with their native toolchains.

**Tech Stack:** GitHub Actions YAML, Flutter 3.44.8, Gradle Kotlin DSL, Python `unittest`, Java `keytool`, Android `apksigner`, Visual Studio Build Tools 2022.

## Global Constraints

- Never commit `key.properties`, `.jks`, `.keystore`, or generated plaintext credentials.
- Use `windows-2022` until the Windows plugins compile with Visual Studio 2026.
- Pull-request builds may use debug signing; version-tag builds must require all release-signing secrets.
- Preserve the existing rule that CI does not regenerate the committed Android runner.
- Keep publishing limited to tags matching `v*`.

---

### Task 1: Pin the Windows build toolchain

**Files:**
- Modify: `tests/test_ci_workflow.py`
- Modify: `.github/workflows/flutter_build.yml:65`

**Interfaces:**
- Consumes: the existing `build_windows` workflow job.
- Produces: a Windows CI job running on the supported `windows-2022` image.

- [ ] **Step 1: Write the failing test**

Add this method to `FlutterWorkflowTests`:

```python
def test_windows_job_pins_visual_studio_2022_runner(self):
    workflow = (
        Path(__file__).parents[1] / ".github" / "workflows" / "flutter_build.yml"
    ).read_text(encoding="utf-8")

    self.assertIn("runs-on: windows-2022", workflow)
    self.assertNotIn("runs-on: windows-latest", workflow)
```

- [ ] **Step 2: Run the test and verify RED**

Run: `python -m unittest tests.test_ci_workflow.FlutterWorkflowTests.test_windows_job_pins_visual_studio_2022_runner -v`

Expected: FAIL because the workflow still contains `runs-on: windows-latest`.

- [ ] **Step 3: Implement the minimal workflow change**

Change the Windows job to:

```yaml
runs-on: windows-2022
```

- [ ] **Step 4: Run the workflow tests and verify GREEN**

Run: `python -m unittest tests.test_ci_workflow -v`

Expected: both workflow tests pass.

- [ ] **Step 5: Commit**

```powershell
git add -- tests/test_ci_workflow.py .github/workflows/flutter_build.yml
git commit -m "ci: pin Windows build to Visual Studio 2022"
```

### Task 2: Configure Gradle release signing

**Files:**
- Create: `tests/test_android_signing.py`
- Modify: `kurama_mobile/android/app/build.gradle.kts:1-34`

**Interfaces:**
- Consumes: `kurama_mobile/android/key.properties` with `storeFile`, `storePassword`, `keyAlias`, and `keyPassword`.
- Produces: a Gradle `release` signing configuration when that file exists, with debug fallback for secretless pull-request builds.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_android_signing.py`:

```python
from pathlib import Path
import unittest


class AndroidSigningTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.gradle = (
            Path(__file__).parents[1]
            / "kurama_mobile"
            / "android"
            / "app"
            / "build.gradle.kts"
        ).read_text(encoding="utf-8")

    def test_release_signing_reads_ignored_key_properties(self):
        self.assertIn('rootProject.file("key.properties")', self.gradle)
        for key in ("storeFile", "storePassword", "keyAlias", "keyPassword"):
            self.assertIn(f'getProperty("{key}")', self.gradle)

    def test_release_signing_uses_release_key_when_available(self):
        self.assertIn('create("release")', self.gradle)
        self.assertIn('signingConfigs.getByName("release")', self.gradle)
        self.assertIn('signingConfigs.getByName("debug")', self.gradle)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the tests and verify RED**

Run: `python -m unittest tests.test_android_signing -v`

Expected: FAIL because Gradle always uses the debug signing configuration.

- [ ] **Step 3: Implement key property loading and release signing**

Add imports and top-level setup:

```kotlin
import java.io.FileInputStream
import java.util.Properties

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseSigning = keystorePropertiesFile.exists()

if (hasReleaseSigning) {
    FileInputStream(keystorePropertiesFile).use(keystoreProperties::load)
}
```

Inside `android`, add:

```kotlin
signingConfigs {
    if (hasReleaseSigning) {
        create("release") {
            storeFile = file(keystoreProperties.getProperty("storeFile"))
            storePassword = keystoreProperties.getProperty("storePassword")
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
        }
    }
}
```

Replace the release signing assignment with:

```kotlin
signingConfig = if (hasReleaseSigning) {
    signingConfigs.getByName("release")
} else {
    signingConfigs.getByName("debug")
}
```

- [ ] **Step 4: Run the signing tests and verify GREEN**

Run: `python -m unittest tests.test_android_signing -v`

Expected: both signing tests pass.

- [ ] **Step 5: Commit**

```powershell
git add -- tests/test_android_signing.py kurama_mobile/android/app/build.gradle.kts
git commit -m "build: configure Android release signing"
```

### Task 3: Require signing secrets for tagged releases

**Files:**
- Modify: `tests/test_ci_workflow.py`
- Modify: `.github/workflows/flutter_build.yml:20-60`

**Interfaces:**
- Consumes: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD` repository secrets.
- Produces: `kurama_mobile/android/app/kuramabot-release.jks` and `kurama_mobile/android/key.properties` only during tagged CI builds.

- [ ] **Step 1: Write the failing tests**

Add methods that assert all four secret expressions appear, the configuration steps use `startsWith(github.ref, 'refs/tags/v')`, the keystore is base64-decoded, and a cleanup step uses `if: always()` to remove both signing files.

```python
def test_tagged_android_build_configures_release_signing(self):
    workflow = self.workflow_text()
    for secret in (
        "ANDROID_KEYSTORE_BASE64",
        "ANDROID_KEYSTORE_PASSWORD",
        "ANDROID_KEY_ALIAS",
        "ANDROID_KEY_PASSWORD",
    ):
        self.assertIn(f"secrets.{secret}", workflow)
    self.assertIn("base64 --decode", workflow)
    self.assertIn("app/kuramabot-release.jks", workflow)
    self.assertIn("key.properties", workflow)

def test_android_signing_material_is_always_removed(self):
    workflow = self.workflow_text()
    self.assertIn("Remove Android signing material", workflow)
    self.assertIn("if: always()", workflow)
    self.assertIn("rm -f android/app/kuramabot-release.jks android/key.properties", workflow)
```

Refactor the existing workflow reader into:

```python
@staticmethod
def workflow_text():
    return (
        Path(__file__).parents[1] / ".github" / "workflows" / "flutter_build.yml"
    ).read_text(encoding="utf-8")
```

- [ ] **Step 2: Run the tests and verify RED**

Run: `python -m unittest tests.test_ci_workflow -v`

Expected: the new signing-secret assertions fail.

- [ ] **Step 3: Add tagged-release secret validation and reconstruction**

Before the APK build, add tag-only Bash steps that reject empty secrets, decode the keystore into `android/app/kuramabot-release.jks`, and write `android/key.properties` with the four required values. Use environment mappings from `${{ secrets.* }}` so secret values never appear directly in the workflow script.

- [ ] **Step 4: Add unconditional cleanup**

After artifact upload, add:

```yaml
- name: Remove Android signing material
  if: always()
  shell: bash
  working-directory: ./kurama_mobile
  run: rm -f android/app/kuramabot-release.jks android/key.properties
```

- [ ] **Step 5: Run all repository tests and verify GREEN**

Run: `python -m unittest discover -s tests -v`

Expected: all tests pass.

- [ ] **Step 6: Commit**

```powershell
git add -- tests/test_ci_workflow.py .github/workflows/flutter_build.yml
git commit -m "ci: sign tagged Android releases"
```

### Task 4: Generate and install the permanent signing key

**Files:**
- Generate, ignored: `kurama_mobile/android/app/kuramabot-release.jks`
- Generate, ignored: `kurama_mobile/android/key.properties`

**Interfaces:**
- Consumes: Java 17 `keytool` and authenticated GitHub CLI access.
- Produces: one permanent RSA-4096 signing key and the four repository secrets used by Task 3.

- [ ] **Step 1: Generate secrets without printing them**

Use PowerShell's cryptographic random generator to create independent 32-byte store and key passwords, write the ignored `key.properties`, and invoke `keytool -genkeypair` with alias `kuramabot`, JKS format, RSA-4096, SHA256withRSA, 10,000-day validity, and distinguished name `CN=KuramaBot, OU=Mobile, O=KuramaBot, L=Kathmandu, ST=Bagmati, C=NP`. Refuse to overwrite either file if it already exists.

- [ ] **Step 2: Verify the key**

Run `keytool -list -v` using the stored password and confirm alias `kuramabot`, a private-key entry, RSA-4096, and SHA-256 certificate fingerprints.

- [ ] **Step 3: Authenticate GitHub CLI**

Run `gh auth status`. If the stored token remains invalid, open `gh auth login --hostname github.com --git-protocol https --web`, wait for the user to complete GitHub's browser authorization, then rerun `gh auth status`.

- [ ] **Step 4: Install repository secrets**

Base64-encode the keystore bytes in memory and pipe them to `gh secret set ANDROID_KEYSTORE_BASE64 --repo yadavnehalkshitiz-cmd/kurama_telebot`. Parse the ignored properties file and pipe each value to its matching `gh secret set` command. Do not print any value.

- [ ] **Step 5: Confirm secret names**

Run: `gh secret list --repo yadavnehalkshitiz-cmd/kurama_telebot`

Expected: all four required names are present; values remain hidden.

### Task 5: Enable local Windows support and verify release artifacts

**Files:**
- Machine setting: `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock\AllowDevelopmentWithoutDevLicense`
- Generated, ignored: `kurama_mobile/windows/`
- Generated, ignored: `kurama_mobile/build/`

**Interfaces:**
- Consumes: Visual Studio Build Tools 2022, Flutter 3.44.8, Android SDK 36, NDK 28.2, and the permanent signing key.
- Produces: a verified Windows release directory and a release-signed Android APK.

- [ ] **Step 1: Enable Developer Mode**

Set `AllowDevelopmentWithoutDevLicense` to DWORD `1` with administrative approval, then read the registry value back and require it to equal `1`.

- [ ] **Step 2: Run repository and Flutter verification**

Run:

```powershell
python -m unittest discover -s tests -v
flutter test
flutter analyze --no-fatal-infos
```

Expected: zero test failures and zero analyzer errors.

- [ ] **Step 3: Build and inspect the Android release**

Run `flutter build apk --release --no-tree-shake-icons`, then run `apksigner verify --verbose --print-certs` on `build/app/outputs/flutter-apk/app-release.apk`. Require signature verification and require the signer DN to contain `CN=KuramaBot`, not `CN=Android Debug`.

- [ ] **Step 4: Generate and build the Windows runner**

Run `flutter create --platforms=windows .` followed by `flutter build windows --release`. Require `build/windows/x64/runner/Release/kurama_mobile.exe` and all plugin DLLs to exist.

- [ ] **Step 5: Clean diagnostic generated sources**

Restore tracked metadata changed by `flutter create` and remove only the generated untracked `windows/` directory and default `test/widget_test.dart` after validating exact absolute paths and rejecting reparse points. Keep ignored release artifacts and the ignored signing key files.

- [ ] **Step 6: Final verification**

Run the full Python test suite again, `git diff --check`, inspect `git status --short`, and review the complete diff. Confirm that no `.jks`, `.keystore`, `key.properties`, or plaintext password is tracked.

- [ ] **Step 7: Commit verification-safe changes if any remain**

Commit only tracked source, workflow, tests, and documentation. Never stage generated signing material or build outputs.
