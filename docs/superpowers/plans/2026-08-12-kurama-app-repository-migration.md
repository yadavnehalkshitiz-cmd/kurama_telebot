# Kurama App Repository Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Safely repurpose `yadavnehalkshitiz-cmd/kurama_bot` as `yadavnehalkshitiz-cmd/kurama_app`, migrate the committed Flutter client and app backend into a separate sibling checkout, and produce independently tested Android, Windows and backend pipelines without changing the installed Android app's update identity.

**Architecture:** The renamed repository becomes an app-only monorepo with `mobile/`, `backend/`, `tests/`, `deployment/`, `docs/` and independent workflows. Migration uses committed source snapshots rather than the dirty working tree, while the target's two legacy commits remain reachable through an archive branch and tag. This plan establishes Phase 0 only; authentication/Supabase, public API authorization, downloader upgrades and advanced browser work are separate dependent plans.

**Tech Stack:** Flutter/Dart, Android Gradle/Kotlin, Windows Flutter runner, Python 3.11, FastAPI, yt-dlp, unittest, Docker, GitHub Actions and GitHub CLI.

## Global Constraints

- Source repository: `yadavnehalkshitiz-cmd/kurama_telebot`; source snapshot: `427ac0966321af56cd5bc3fffe26b81134028223`.
- Target repository before rename: `yadavnehalkshitiz-cmd/kurama_bot`; legacy snapshot: `a5e96a0126bc7ff3729300c02c3ceeb1e842bdaa`.
- Preserve target history as branch `archive/legacy-kurama-bot` and tag `legacy-kurama-bot-2026-08-12` before renaming.
- Use sibling folder `C:\Users\ay835\Documents\anitigravity\kurama_app`; never place the app repository inside `telebot`.
- Migrate committed files only. Never copy `.env`, cookies, downloads, logs, IDE metadata, local databases, `key.properties`, JKS files or other runtime data.
- Keep Android `applicationId = "com.kuramabot.kurama_mobile"`, `namespace = "com.kuramabot.kurama_mobile"`, minimum API 28, and the existing permanent signing key so installed copies remain upgradeable.
- Keep Dart package name `kurama_mobile` and existing on-device `KuramaBot` storage paths during Phase 0 to avoid breaking imports or orphaning user downloads.
- Change the visible product/release name to `Kurama App`; repository naming does not require a new Android application ID.
- The app repository must not import Telegram packages or require the Telegram bot process.
- The backend continues using the current temporary shared API-key contract only for Phase 0 compatibility; Phase 1 replaces it with Supabase user JWT validation before public production rollout.
- Windows CI remains pinned to `windows-2022`; Android signing uses the same four GitHub secret names already used by `kurama_telebot`.
- Do not remove app files from `kurama_telebot` until `kurama_app` builds and tests successfully on GitHub and the follow-on cleanup plan is approved.

---

## File Structure

```text
kurama_app/
├── .github/workflows/
│   ├── backend_ci.yml             Python tests and container build
│   └── flutter_build.yml          Android/Windows build and tagged release
├── backend/
│   ├── api_server.py              FastAPI routes and download task lifecycle
│   ├── config.py                  App-backend-only environment configuration
│   ├── downloader.py              App-owned yt-dlp orchestration
│   ├── user_config.py             Temporary Phase 0 local account/credit store
│   ├── utils.py                   Platform recognition and formatting helpers
│   └── requirements.txt           Backend-only Python dependencies
├── deployment/
│   ├── Dockerfile                 Backend-only production image
│   └── .env.example               Secret names and safe development defaults
├── docs/
│   ├── MIGRATION.md               Immutable source/target provenance
│   └── RELEASES.md                Signing and update-compatibility runbook
├── mobile/                        Existing Flutter project, package name unchanged
├── scripts/
│   └── verify_repository_boundary.ps1
├── tests/
│   ├── test_android_signing.py
│   ├── test_backend_boundary.py
│   ├── test_billing_and_audio.py
│   ├── test_branding.py
│   ├── test_ci_workflow.py
│   ├── test_migration_manifest.py
│   ├── test_mobile_api.py
│   ├── test_mobile_configuration.py
│   ├── test_release_version.py
│   └── test_repository_contract.py
├── .gitignore
└── README.md
```

## Task 1: Archive and Rename the Existing Target Repository

**Files:**
- Remote metadata: `yadavnehalkshitiz-cmd/kurama_bot`
- Remote branch: `archive/legacy-kurama-bot`
- Remote tag: `legacy-kurama-bot-2026-08-12`

**Interfaces:**
- Consumes: target commit `a5e96a0126bc7ff3729300c02c3ceeb1e842bdaa`.
- Produces: repository URL `https://github.com/yadavnehalkshitiz-cmd/kurama_app` with recoverable legacy references.

- [ ] **Step 1: Verify the exact pre-migration state**

```powershell
$gh = 'C:\Program Files\GitHub CLI\gh.exe'
& $gh repo view yadavnehalkshitiz-cmd/kurama_bot --json nameWithOwner,defaultBranchRef,url
& $gh api repos/yadavnehalkshitiz-cmd/kurama_bot/commits/main --jq '.sha'
& $gh repo view yadavnehalkshitiz-cmd/kurama_app --json nameWithOwner 2>$null
```

Expected: `kurama_bot` default branch is `main`, its SHA is `a5e96a0126bc7ff3729300c02c3ceeb1e842bdaa`, and `kurama_app` does not exist.

- [ ] **Step 2: Create the recovery branch and lightweight tag**

```powershell
$gh = 'C:\Program Files\GitHub CLI\gh.exe'
$repo = 'yadavnehalkshitiz-cmd/kurama_bot'
$sha = 'a5e96a0126bc7ff3729300c02c3ceeb1e842bdaa'
& $gh api -X POST "repos/$repo/git/refs" -f ref='refs/heads/archive/legacy-kurama-bot' -f sha=$sha
& $gh api -X POST "repos/$repo/git/refs" -f ref='refs/tags/legacy-kurama-bot-2026-08-12' -f sha=$sha
```

Expected: both API calls return refs pointing to the exact legacy SHA.

- [ ] **Step 3: Verify recovery refs before renaming**

```powershell
$gh = 'C:\Program Files\GitHub CLI\gh.exe'
$repo = 'yadavnehalkshitiz-cmd/kurama_bot'
& $gh api "repos/$repo/git/ref/heads/archive/legacy-kurama-bot" --jq '.object.sha'
& $gh api "repos/$repo/git/ref/tags/legacy-kurama-bot-2026-08-12" --jq '.object.sha'
```

Expected: both outputs equal `a5e96a0126bc7ff3729300c02c3ceeb1e842bdaa`. Stop before rename if either differs.

- [ ] **Step 4: Rename and describe the repository**

```powershell
$gh = 'C:\Program Files\GitHub CLI\gh.exe'
& $gh api -X PATCH repos/yadavnehalkshitiz-cmd/kurama_bot -f name='kurama_app' -f description='Kurama App — privacy-focused multi-platform media downloader'
```

Expected: response `full_name` is `yadavnehalkshitiz-cmd/kurama_app`.

- [ ] **Step 5: Verify redirect, default branch and archive refs**

```powershell
$gh = 'C:\Program Files\GitHub CLI\gh.exe'
& $gh repo view yadavnehalkshitiz-cmd/kurama_app --json nameWithOwner,url,defaultBranchRef,description
& $gh api repos/yadavnehalkshitiz-cmd/kurama_app/git/ref/heads/archive/legacy-kurama-bot --jq '.object.sha'
& $gh api repos/yadavnehalkshitiz-cmd/kurama_app/git/ref/tags/legacy-kurama-bot-2026-08-12 --jq '.object.sha'
```

Expected: new URL resolves, default branch remains `main`, and both recovery refs retain the legacy SHA.

## Task 2: Create a Clean Sibling Checkout and Migration Contract

**Files:**
- Create: `C:\Users\ay835\Documents\anitigravity\kurama_app\.gitignore`
- Create: `C:\Users\ay835\Documents\anitigravity\kurama_app\README.md`
- Create: `C:\Users\ay835\Documents\anitigravity\kurama_app\docs\MIGRATION.md`
- Create: `C:\Users\ay835\Documents\anitigravity\kurama_app\tests\test_migration_manifest.py`
- Create: `C:\Users\ay835\Documents\anitigravity\kurama_app\tests\test_repository_contract.py`
- Create: `C:\Users\ay835\Documents\anitigravity\kurama_app\scripts\verify_repository_boundary.ps1`
- Delete on migration branch only: `README.md`, `telebot/` inherited from legacy `main`

**Interfaces:**
- Consumes: renamed repository and both exact source SHAs.
- Produces: branch `codex/phase-0-app-separation` with an explicit clean-repository contract.

- [ ] **Step 1: Clone into the verified empty sibling path and create the migration branch**

```powershell
$target = 'C:\Users\ay835\Documents\anitigravity\kurama_app'
if (Test-Path -LiteralPath $target) { throw "Target already exists: $target" }
git clone https://github.com/yadavnehalkshitiz-cmd/kurama_app.git $target
git -C $target switch -c codex/phase-0-app-separation
```

Expected: clone succeeds and branch is based on legacy main.

- [ ] **Step 2: Remove only the archived legacy working-tree content**

```powershell
$target = 'C:\Users\ay835\Documents\anitigravity\kurama_app'
git -C $target rm -r -- telebot README.md
```

Expected: only the six legacy tracked paths are staged for removal; the archive branch/tag remain remote and untouched.

- [ ] **Step 3: Write the failing migration-manifest test**

```python
# tests/test_migration_manifest.py
from pathlib import Path
import unittest


class MigrationManifestTests(unittest.TestCase):
    def test_manifest_records_both_exact_sources(self):
        text = (Path(__file__).parents[1] / "docs" / "MIGRATION.md").read_text(
            encoding="utf-8"
        )
        self.assertIn("yadavnehalkshitiz-cmd/kurama_telebot", text)
        self.assertIn("427ac0966321af56cd5bc3fffe26b81134028223", text)
        self.assertIn("yadavnehalkshitiz-cmd/kurama_bot", text)
        self.assertIn("a5e96a0126bc7ff3729300c02c3ceeb1e842bdaa", text)
        self.assertIn("archive/legacy-kurama-bot", text)
        self.assertIn("legacy-kurama-bot-2026-08-12", text)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 4: Run the test and confirm the missing manifest failure**

Run: `python -m unittest tests.test_migration_manifest -v`

Expected: ERROR because `docs/MIGRATION.md` does not exist.

- [ ] **Step 5: Create the migration manifest and repository README**

```markdown
<!-- docs/MIGRATION.md -->
# Migration Provenance

Kurama App was separated on 2026-08-12 from committed source only.

- App source: `yadavnehalkshitiz-cmd/kurama_telebot` at `427ac0966321af56cd5bc3fffe26b81134028223`
- Repurposed target: `yadavnehalkshitiz-cmd/kurama_bot` at `a5e96a0126bc7ff3729300c02c3ceeb1e842bdaa`
- Legacy recovery branch: `archive/legacy-kurama-bot`
- Legacy recovery tag: `legacy-kurama-bot-2026-08-12`

The migration excludes environment files, cookies, downloads, logs, IDE files,
local databases, Android key properties and keystores.
```

```markdown
<!-- README.md -->
# Kurama App

Kurama App is the standalone Android and Windows media downloader. This
repository owns the Flutter client, app backend, tests and release automation.

The Telegram product remains independently maintained in
`yadavnehalkshitiz-cmd/kurama_telebot`; neither product imports or launches the
other.

## Layout

- `mobile/` — Flutter Android and Windows client
- `backend/` — FastAPI download service
- `deployment/` — backend container and environment contract
- `tests/` — cross-component and migration tests
- `docs/` — operations, release and architecture notes
```

- [ ] **Step 6: Add ignore and boundary rules**

```gitignore
# .gitignore
.env
.env.*
!.env.example
.idea/
.vscode/
.dart_tool/
.flutter-plugins*
.packages
build/
**/build/
__pycache__/
.pytest_cache/
*.py[cod]
*.log
cookies/
cookies*.txt
downloads/
saved_videos/
temp_mobile/
user_configs.json
*.db
*.sqlite*
**/key.properties
**/*.jks
**/*.keystore
```

```python
# tests/test_repository_contract.py
from pathlib import Path
import unittest


ROOT = Path(__file__).parents[1]


class RepositoryContractTests(unittest.TestCase):
    def test_forbidden_runtime_files_are_not_tracked(self):
        forbidden_names = {
            ".env", "cookies.txt", "key.properties", "kuramabot-release.jks",
            "user_configs.json", "ffmpeg.exe",
        }
        found = [p for p in ROOT.rglob("*") if p.is_file() and p.name in forbidden_names]
        self.assertEqual([], found)

    def test_telegram_entrypoints_are_absent(self):
        for relative in ("bot.py", "handlers.py", "keyboards.py", "senders.py", "run_bot.py"):
            self.assertFalse((ROOT / relative).exists(), relative)
            self.assertFalse((ROOT / "backend" / relative).exists(), relative)


if __name__ == "__main__":
    unittest.main()
```

```powershell
# scripts/verify_repository_boundary.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$forbidden = @('.env', 'cookies.txt', 'key.properties', 'kuramabot-release.jks', 'user_configs.json', 'ffmpeg.exe')
$found = Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.Name -in $forbidden }
if ($found) { throw "Forbidden runtime files found: $($found.FullName -join ', ')" }
$tracked = git -C $root ls-files
$badTracked = $tracked | Where-Object { $_ -match '(^|/)(\.idea|downloads|cookies|saved_videos|temp_mobile)/|(^|/)\.env$|key\.properties$|\.(jks|keystore)$' }
if ($badTracked) { throw "Forbidden tracked paths found: $($badTracked -join ', ')" }
Write-Output 'Repository boundary verified.'
```

- [ ] **Step 7: Run the repository contract tests**

Run: `python -m unittest tests.test_migration_manifest tests.test_repository_contract -v`

Expected: all tests pass.

- [ ] **Step 8: Commit the clean migration contract**

```powershell
git add -- .gitignore README.md docs/MIGRATION.md scripts/verify_repository_boundary.ps1 tests/test_migration_manifest.py tests/test_repository_contract.py
git commit -m "chore: establish Kurama App repository boundary"
```

## Task 3: Migrate the Committed Flutter Client Without Breaking Updates

**Files:**
- Create: `mobile/**` from source `kurama_mobile/**`
- Modify: `mobile/android/app/src/main/AndroidManifest.xml`
- Modify: `mobile/lib/main.dart`
- Modify: `mobile/pubspec.yaml`
- Create/modify: `tests/test_mobile_configuration.py`
- Create/modify: `tests/test_android_signing.py`
- Create/modify: `tests/test_release_version.py`

**Interfaces:**
- Consumes: committed Flutter tree at source SHA and the permanent Android identity.
- Produces: buildable `mobile/` tree with visible name `Kurama App` and unchanged package/application identity.

- [ ] **Step 1: Export the committed Flutter tree, never the dirty working tree**

```powershell
$source = 'C:\Users\ay835\Documents\anitigravity\telebot'
$target = 'C:\Users\ay835\Documents\anitigravity\kurama_app'
$archive = 'C:\tmp\kurama-mobile-427ac096.zip'
$extract = 'C:\tmp\kurama-mobile-427ac096'
git -C $source archive --format=zip --output=$archive 427ac0966321af56cd5bc3fffe26b81134028223 kurama_mobile
Expand-Archive -LiteralPath $archive -DestinationPath $extract
Move-Item -LiteralPath "$extract\kurama_mobile" -Destination "$target\mobile"
```

Expected: `mobile/pubspec.yaml` exists and none of the ignored local signing files were included.

- [ ] **Step 2: Write identity tests before changing labels**

```python
# tests/test_mobile_configuration.py
from pathlib import Path
import unittest


ROOT = Path(__file__).parents[1]


class MobileConfigurationTests(unittest.TestCase):
    def test_android_update_identity_is_preserved(self):
        gradle = (ROOT / "mobile/android/app/build.gradle.kts").read_text(encoding="utf-8")
        self.assertIn('applicationId = "com.kuramabot.kurama_mobile"', gradle)
        self.assertIn('namespace = "com.kuramabot.kurama_mobile"', gradle)
        self.assertIn("minSdk = 28", gradle)

    def test_dart_package_identity_is_preserved(self):
        pubspec = (ROOT / "mobile/pubspec.yaml").read_text(encoding="utf-8")
        self.assertIn("name: kurama_mobile", pubspec)

    def test_visible_android_name_is_kurama_app(self):
        manifest = (ROOT / "mobile/android/app/src/main/AndroidManifest.xml").read_text(encoding="utf-8")
        self.assertIn('android:label="Kurama App"', manifest)

    def test_api_key_has_no_compiled_production_default(self):
        main = (ROOT / "mobile/lib/main.dart").read_text(encoding="utf-8")
        self.assertIn("String.fromEnvironment('KURAMA_API_KEY')", main)
        self.assertNotRegex(main, r"const\s+prodKey\s*=\s*'[^']+'")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 3: Run the identity test and verify only the visible-name assertion fails**

Run: `python -m unittest tests.test_mobile_configuration -v`

Expected: application ID, namespace, package and minSdk assertions pass; label assertion fails with the current `KuramaBot` value.

- [ ] **Step 4: Change user-visible product text without changing package/storage identity**

```text
mobile/android/app/src/main/AndroidManifest.xml:
  android:label="Kurama App"

mobile/lib/main.dart:
  title: 'Kurama App'

mobile/pubspec.yaml:
  description: Kurama App — privacy-focused multi-platform media downloader.
```

Do not replace `com.kuramabot.kurama_mobile`, `name: kurama_mobile`, Dart package imports, or existing `KuramaBot` on-device storage directories in this task.

- [ ] **Step 5: Relocate structural tests and update their root paths**

Copy `test_android_signing.py` and `test_release_version.py` from the committed source archive. Replace only their path segment `kurama_mobile` with `mobile`; the test written in Step 2 retains the API 28 and build-time-key assertions.

```powershell
$source = 'C:\Users\ay835\Documents\anitigravity\telebot'
$target = 'C:\Users\ay835\Documents\anitigravity\kurama_app'
$archive = 'C:\tmp\kurama-mobile-tests-427ac096.zip'
$extract = 'C:\tmp\kurama-mobile-tests-427ac096'
git -C $source archive --format=zip --output=$archive 427ac0966321af56cd5bc3fffe26b81134028223 tests/test_android_signing.py tests/test_release_version.py
Expand-Archive -LiteralPath $archive -DestinationPath $extract
Move-Item -LiteralPath "$extract\tests\test_android_signing.py" -Destination "$target\tests"
Move-Item -LiteralPath "$extract\tests\test_release_version.py" -Destination "$target\tests"
```

- [ ] **Step 6: Run Flutter and structural tests**

```powershell
python -m unittest tests.test_mobile_configuration tests.test_android_signing tests.test_release_version -v
& 'C:\tmp\flutter-sdk\bin\flutter.bat' test
```

Run the Flutter command with working directory `mobile/`.

Expected: all Python tests and all Flutter tests pass.

- [ ] **Step 7: Commit the migrated client**

```powershell
git add -- mobile tests/test_mobile_configuration.py tests/test_android_signing.py tests/test_release_version.py
git commit -m "feat: migrate Kurama Flutter client"
```

## Task 4: Generate and Verify the Kurama Launcher Icons

**Files:**
- Modify: `mobile/pubspec.yaml`
- Modify: `mobile/pubspec.lock`
- Regenerate: `mobile/android/app/src/main/res/mipmap-*/ic_launcher.png`
- Create: `mobile/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`
- Create: `mobile/android/app/src/main/res/drawable-*/ic_launcher_foreground.png`
- Create: `tests/test_branding.py`

**Interfaces:**
- Consumes: `mobile/assets/images/logo.png` with SHA-256 `57226B60FEF610C43D041DD2981D33F5AE85FB33C864108FAD9C44EBE3DD6CB8`.
- Produces: legacy and adaptive Android launcher resources that visibly use the Kurama fox logo.

- [ ] **Step 1: Write a failing branding regression test**

```python
# tests/test_branding.py
from hashlib import sha256
from pathlib import Path
import unittest


ROOT = Path(__file__).parents[1]
OLD_FLUTTER_ICON_HASHES = {
    "6A7C8F0D703E3682108F9662F813302236240D3F8F638BB391E32BFB96055FEF",
    "C7C0C0189145E4E32A401C61C9BDC615754B0264E7AFAE24E834BB81049EAF81",
    "E14AA40904929BF313FDED22CF7E7FFCBF1D1AAC4263B5EF1BE8BFCE650397AA",
    "4D470BF22D5C17D84EDC5F82516D1BA8A1C09559CD761CEFB792F86D9F52B540",
    "3C34E1F298D0C9EA3455D46DB6B7759C8211A49E9EC6E44B635FC5C87DFB4180",
}


class BrandingTests(unittest.TestCase):
    def test_master_logo_is_the_approved_asset(self):
        logo = ROOT / "mobile/assets/images/logo.png"
        self.assertEqual(
            "57226B60FEF610C43D041DD2981D33F5AE85FB33C864108FAD9C44EBE3DD6CB8",
            sha256(logo.read_bytes()).hexdigest().upper(),
        )

    def test_generated_icons_are_not_flutter_defaults(self):
        icons = sorted((ROOT / "mobile/android/app/src/main/res").glob("mipmap-*/ic_launcher.png"))
        self.assertGreaterEqual(len(icons), 5)
        for icon in icons:
            self.assertNotIn(sha256(icon.read_bytes()).hexdigest().upper(), OLD_FLUTTER_ICON_HASHES)

    def test_adaptive_icon_resource_exists(self):
        self.assertTrue((ROOT / "mobile/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml").is_file())


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test and confirm default-icon/adaptive-resource failures**

Run: `python -m unittest tests.test_branding -v`

Expected: master logo passes; launcher icon and adaptive-resource assertions fail.

- [ ] **Step 3: Configure deterministic launcher generation**

Add to `mobile/pubspec.yaml`:

```yaml
dev_dependencies:
  flutter_launcher_icons: ^0.14.4

flutter_launcher_icons:
  android: true
  ios: false
  image_path: assets/images/logo.png
  adaptive_icon_background: "#09080D"
  adaptive_icon_foreground: assets/images/logo.png
  min_sdk_android: 28
```

- [ ] **Step 4: Generate the committed Android resources**

```powershell
& 'C:\tmp\flutter-sdk\bin\flutter.bat' pub get
& 'C:\tmp\flutter-sdk\bin\flutter.bat' pub run flutter_launcher_icons
```

Run both commands from `mobile/`.

Expected: the five legacy mipmaps and API 26 adaptive icon resources are regenerated.

- [ ] **Step 5: Verify icons programmatically and visually**

Run: `python -m unittest tests.test_branding -v`

Expected: all branding tests pass. Also render/open `mipmap-xxxhdpi/ic_launcher.png` and confirm it shows the Kurama fox, not the Flutter mark.

- [ ] **Step 6: Commit branding resources**

```powershell
git add -- mobile/pubspec.yaml mobile/pubspec.lock mobile/android/app/src/main/res tests/test_branding.py
git commit -m "fix: apply Kurama App launcher branding"
```

## Task 5: Extract an App-Only FastAPI Backend

**Files:**
- Create: `backend/api_server.py` from committed source
- Create: `backend/config.py` from committed source, stripped to app-owned settings
- Create: `backend/downloader.py` from committed source, without Telegram compression
- Create: `backend/user_config.py` from committed source with user terminology
- Create: `backend/utils.py` from committed source
- Create: `backend/requirements.txt`
- Create/modify: `tests/test_mobile_api.py`
- Create/modify: `tests/test_billing_and_audio.py`
- Create: `tests/test_backend_boundary.py`

**Interfaces:**
- Consumes: current `/api/health`, `/api/fetch-info`, `/api/download`, status, stream, file, profile and payment route behavior.
- Produces: `backend.api_server:app`-equivalent runtime started as `uvicorn api_server:app` with no Telegram package/import/entrypoint.

- [ ] **Step 1: Export only the committed backend-owned source and tests**

```powershell
$source = 'C:\Users\ay835\Documents\anitigravity\telebot'
$target = 'C:\Users\ay835\Documents\anitigravity\kurama_app'
$archive = 'C:\tmp\kurama-backend-427ac096.zip'
$extract = 'C:\tmp\kurama-backend-427ac096'
git -C $source archive --format=zip --output=$archive 427ac0966321af56cd5bc3fffe26b81134028223 api_server.py config.py downloader.py user_config.py utils.py tests/test_mobile_api.py tests/test_billing_and_audio.py
Expand-Archive -LiteralPath $archive -DestinationPath $extract
New-Item -ItemType Directory -Path "$target\backend" -Force | Out-Null
Move-Item -LiteralPath "$extract\api_server.py" -Destination "$target\backend"
Move-Item -LiteralPath "$extract\config.py" -Destination "$target\backend"
Move-Item -LiteralPath "$extract\downloader.py" -Destination "$target\backend"
Move-Item -LiteralPath "$extract\user_config.py" -Destination "$target\backend"
Move-Item -LiteralPath "$extract\utils.py" -Destination "$target\backend"
Move-Item -LiteralPath "$extract\tests\test_mobile_api.py" -Destination "$target\tests"
Move-Item -LiteralPath "$extract\tests\test_billing_and_audio.py" -Destination "$target\tests"
```

Expected: only the five app/backend modules and two behavioral tests are copied; no bot entrypoint is present.

- [ ] **Step 2: Write the failing backend-boundary test**

```python
# tests/test_backend_boundary.py
from pathlib import Path
import ast
import unittest


ROOT = Path(__file__).parents[1]
BACKEND = ROOT / "backend"


class BackendBoundaryTests(unittest.TestCase):
    def test_requirements_exclude_telegram(self):
        requirements = (BACKEND / "requirements.txt").read_text(encoding="utf-8").lower()
        self.assertNotIn("python-telegram-bot", requirements)

    def test_backend_does_not_import_telegram_or_bot_modules(self):
        forbidden = {"telegram", "bot", "handlers", "keyboards", "senders", "run_bot"}
        found = []
        for path in BACKEND.glob("*.py"):
            tree = ast.parse(path.read_text(encoding="utf-8-sig"), filename=str(path))
            for node in ast.walk(tree):
                if isinstance(node, ast.Import):
                    found.extend(alias.name.split(".")[0] for alias in node.names if alias.name.split(".")[0] in forbidden)
                elif isinstance(node, ast.ImportFrom) and node.module:
                    root = node.module.split(".")[0]
                    if root in forbidden:
                        found.append(root)
        self.assertEqual([], found)

    def test_backend_config_has_no_telegram_runtime_settings(self):
        config = (BACKEND / "config.py").read_text(encoding="utf-8-sig")
        for name in ("TELEGRAM_BOT_TOKEN", "TELEGRAM_LIMIT", "ADMIN_CHAT_ID", "LAPTOP_FOLDER"):
            self.assertNotIn(name, config)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 3: Run the boundary test and confirm requirements/config failures**

Run: `python -m unittest tests.test_backend_boundary -v`

Expected: ERROR for missing `backend/requirements.txt` and FAIL for Telegram-only settings still present in copied config.

- [ ] **Step 4: Create backend-only requirements**

```text
yt-dlp>=2026.7.4
python-dotenv>=1.0.0
fastapi>=0.110.0
uvicorn[standard]>=0.29.0
python-multipart>=0.0.9
```

- [ ] **Step 5: Remove Telegram-only configuration and downloader code**

From `backend/config.py`, remove `TOKEN`, `TELEGRAM_LIMIT`, `LAPTOP_FOLDER` and `ADMIN_CHAT_ID`; keep the app temp, cookies, download presets, platform rules, proxy, API, billing and timeout settings. Set `BASE_DIR` to the backend directory and keep runtime directories ignored.

From `backend/downloader.py`, remove the unused `asyncio` import and `compress_for_telegram()` function. Keep `build_ydl_opts()`, `_apply_platform_overrides()`, `fetch_info()` and `download_single()` signatures unchanged.

```python
# Required backend/config.py API after extraction
API_AUTH_KEY: str | None
API_ADMIN_KEY: str | None
API_HOST: str
API_PORT: int
TEMP_FOLDER: str
COOKIES_FOLDER: str
USER_CONFIGS_FILE: str
PLATFORM_RULES: list[tuple]
PLATFORM_COOKIE_MAP: dict[str, str]
CHROME_UA: str
MOBILE_UA: str
VIDEO_QUALITIES: dict[str, str]
MOBILE_QUALITIES: dict[str, str]
AUDIO_QUALITIES: dict[str, str]
AUDIO_BITRATES: dict[str, str]
YTDLP_PROXY: str | None
YTDLP_INSECURE: bool
SOCKET_TIMEOUT: int
EXTRACT_TIMEOUT: int
TWITTER_BEARER_TOKEN: str
INSTAGRAM_APP_ID: str
TWITCH_CLIENT_ID: str
ALLOWED_ORIGINS: list[str]
MAX_URL_LENGTH: int
TASK_TTL: int
INITIAL_FREE_CREDITS: int
MONTHLY_SUB_PRICE_NPR: int
ESEWA_ID: str
KHALTI_ID: str
BANK_DETAILS: str
```

- [ ] **Step 6: Change temporary account-store terminology without changing behavior**

Mechanically rename `chat_id` parameters/local keys to `user_id` inside the app copy of `backend/user_config.py`. Do not alter its public function names or credit/payment behavior, because `backend/api_server.py` and the migrated tests consume those functions.

Signatures retained for Phase 0 compatibility:

- `get_user_credits(user_id: int) -> int`
- `consume_download_credit(user_id: int) -> tuple[bool, bool]`
- `refund_credit(user_id: int) -> int`
- `claim_daily_reward(user_id: int, *, now: datetime | None = None, amount: int = 2) -> dict`
- `add_pending_payment(user_id: int, tx_id: str, amount: int = 500, *, method: str = "other", receipt_path: str | None = None) -> dict`

- [ ] **Step 7: Point migrated tests at `backend/`**

Add this exact preamble before importing `api_server`, `config`, `downloader` or `user_config` in both migrated tests:

```python
from pathlib import Path
import sys

BACKEND = Path(__file__).parents[1] / "backend"
sys.path.insert(0, str(BACKEND))
```

Update temporary file patches to use imported `backend/config.py` values; retain all current API authorization, download lifecycle, billing and audio-option assertions.

- [ ] **Step 8: Install backend dependencies and run tests**

```powershell
python -m pip install -r backend/requirements.txt
python -m unittest tests.test_backend_boundary tests.test_mobile_api tests.test_billing_and_audio -v
```

Expected: all migrated backend behavioral tests and boundary tests pass.

- [ ] **Step 9: Commit the independent backend**

```powershell
git add -- backend tests/test_backend_boundary.py tests/test_mobile_api.py tests/test_billing_and_audio.py
git commit -m "feat: extract independent Kurama App backend"
```

## Task 6: Add Backend Deployment and CI

**Files:**
- Create: `deployment/Dockerfile`
- Create: `deployment/.env.example`
- Create: `.github/workflows/backend_ci.yml`
- Modify: `tests/test_ci_workflow.py`

**Interfaces:**
- Consumes: `backend/api_server.py`, `backend/requirements.txt` and backend test suite.
- Produces: backend-only Docker image and GitHub validation job.

- [ ] **Step 1: Copy the committed workflow test as the baseline**

```powershell
$source = 'C:\Users\ay835\Documents\anitigravity\telebot'
$target = 'C:\Users\ay835\Documents\anitigravity\kurama_app'
$archive = 'C:\tmp\kurama-ci-test-427ac096.zip'
$extract = 'C:\tmp\kurama-ci-test-427ac096'
git -C $source archive --format=zip --output=$archive 427ac0966321af56cd5bc3fffe26b81134028223 tests/test_ci_workflow.py
Expand-Archive -LiteralPath $archive -DestinationPath $extract
Move-Item -LiteralPath "$extract\tests\test_ci_workflow.py" -Destination "$target\tests"
```

- [ ] **Step 2: Write failing CI/deployment assertions**

```python
# Add to tests/test_ci_workflow.py
def test_backend_workflow_tests_and_builds_container(self):
    workflow = (self.root / ".github/workflows/backend_ci.yml").read_text(encoding="utf-8")
    self.assertIn("python -m unittest discover -s tests -v", workflow)
    self.assertIn("PYTHONPATH", workflow)
    self.assertIn("docker build -f deployment/Dockerfile .", workflow)

def test_backend_container_starts_only_the_api(self):
    dockerfile = (self.root / "deployment/Dockerfile").read_text(encoding="utf-8")
    self.assertIn('CMD ["uvicorn", "api_server:app"', dockerfile)
    self.assertNotIn("run_bot.py", dockerfile)
    self.assertNotIn("bot.py", dockerfile)
```

Ensure `setUp()` defines `self.root = Path(__file__).parents[1]`.

- [ ] **Step 3: Run CI tests and confirm missing-file failures**

Run: `python -m unittest tests.test_ci_workflow -v`

Expected: failures because the backend workflow and deployment Dockerfile do not exist.

- [ ] **Step 4: Create the backend-only Dockerfile**

```dockerfile
FROM python:3.11-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY backend/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt
COPY backend/ ./

ENV PYTHONUNBUFFERED=1
EXPOSE 8000
CMD ["uvicorn", "api_server:app", "--host", "0.0.0.0", "--port", "8000"]
```

- [ ] **Step 5: Create the safe environment contract**

```dotenv
# deployment/.env.example
KURAMA_API_KEY=
KURAMA_ADMIN_KEY=
API_HOST=0.0.0.0
API_PORT=8000
CORS_ALLOWED_ORIGINS=http://localhost:3000
TASK_TTL=3600
MAX_CONCURRENT_DOWNLOADS=5
PLAYLIST_MAX_ENTRIES=60
INITIAL_FREE_CREDITS=3
MONTHLY_SUB_PRICE_NPR=500
USER_CONFIGS_FILE=/data/user_configs.json
```

- [ ] **Step 6: Create backend CI**

```yaml
name: Backend CI

on:
  push:
    branches: [main, codex/phase-0-app-separation]
  pull_request:
    branches: [main]

jobs:
  test_backend:
    runs-on: ubuntu-latest
    env:
      PYTHONPATH: backend
      KURAMA_API_KEY: ci-test-key-that-is-not-used-in-production
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-python@v6
        with:
          python-version: '3.11'
          cache: pip
          cache-dependency-path: backend/requirements.txt
      - run: python -m pip install -r backend/requirements.txt
      - run: python -m unittest discover -s tests -v
      - run: docker build -f deployment/Dockerfile .
```

- [ ] **Step 7: Run tests and build the container locally**

```powershell
$env:PYTHONPATH='backend'
$env:KURAMA_API_KEY='local-phase-0-test-key'
python -m unittest discover -s tests -v
docker build -f deployment/Dockerfile .
```

Expected: tests pass and Docker build exits zero. If Docker is unavailable locally, GitHub CI remains the required container verification gate.

- [ ] **Step 8: Commit backend deployment automation**

```powershell
git add -- deployment .github/workflows/backend_ci.yml tests/test_ci_workflow.py
git commit -m "ci: validate Kurama App backend"
```

## Task 7: Migrate Android/Windows Release Automation and Signing

**Files:**
- Create/modify: `.github/workflows/flutter_build.yml`
- Create: `docs/RELEASES.md`
- Modify: `tests/test_ci_workflow.py`

**Interfaces:**
- Consumes: `mobile/` build, permanent local JKS and its ignored `key.properties` from the source checkout.
- Produces: Android/Windows artifacts named `Kurama-App-*` and signed Android updates compatible with existing installations.

- [ ] **Step 1: Copy the committed workflow without overwriting the expanded CI tests**

```powershell
$source = 'C:\Users\ay835\Documents\anitigravity\telebot'
$target = 'C:\Users\ay835\Documents\anitigravity\kurama_app'
New-Item -ItemType Directory -Path "$target\.github\workflows" -Force | Out-Null
$archive = 'C:\tmp\kurama-flutter-workflow-427ac096.zip'
$extract = 'C:\tmp\kurama-flutter-workflow-427ac096'
git -C $source archive --format=zip --output=$archive 427ac0966321af56cd5bc3fffe26b81134028223 .github/workflows/flutter_build.yml
Expand-Archive -LiteralPath $archive -DestinationPath $extract
Move-Item -LiteralPath "$extract\.github\workflows\flutter_build.yml" -Destination "$target\.github\workflows"
```

- [ ] **Step 2: Write failing app-path/artifact assertions**

```python
# Add to tests/test_ci_workflow.py
def test_flutter_workflow_uses_app_repository_paths_and_names(self):
    workflow = self.workflow_text()
    self.assertNotIn("kurama_mobile/", workflow)
    self.assertIn("working-directory: ./mobile", workflow)
    self.assertIn("mobile/build/app/outputs/flutter-apk/app-release.apk", workflow)
    self.assertIn("Kurama-App-Android-APK", workflow)
    self.assertIn("Kurama-App-Windows.zip", workflow)

def test_windows_runner_remains_reproducible(self):
    workflow = self.workflow_text()
    self.assertIn("runs-on: windows-2022", workflow)
    self.assertNotIn("runs-on: windows-latest", workflow)
```

Update `workflow_text()` to read `.github/workflows/flutter_build.yml` from the new repository root.

- [ ] **Step 3: Run workflow tests and confirm old-path/name failures**

Run: `python -m unittest tests.test_ci_workflow -v`

Expected: new path/artifact assertions fail while existing Windows/signing/action-version assertions pass.

- [ ] **Step 4: Update workflow paths and release branding**

Apply these exact replacements in `.github/workflows/flutter_build.yml`:

```text
./kurama_mobile              -> ./mobile
kurama_mobile/build          -> mobile/build
KuramaBot-Android-APK        -> Kurama-App-Android-APK
KuramaBot-Windows-App        -> Kurama-App-Windows-App
KuramaBot-Windows.zip        -> Kurama-App-Windows.zip
KuramaBot-${{ github.ref_name }}.apk -> Kurama-App-${{ github.ref_name }}.apk
KuramaBot ${{ github.ref_name }}     -> Kurama App ${{ github.ref_name }}
```

Keep `actions/checkout@v7`, `actions/setup-java@v5`, `windows-2022`, `if: always()` signing cleanup and all four signing secret names unchanged. Remove release instructions asking users to enter a shared API key; Phase 0 artifacts are engineering builds until Phase 1 auth is complete.

- [ ] **Step 5: Transfer the permanent signing material without printing it**

```powershell
$gh = 'C:\Program Files\GitHub CLI\gh.exe'
$repo = 'yadavnehalkshitiz-cmd/kurama_app'
$keyFile = 'C:\Users\ay835\Documents\anitigravity\telebot\kurama_mobile\android\app\kuramabot-release.jks'
$propertiesFile = 'C:\Users\ay835\Documents\anitigravity\telebot\kurama_mobile\android\key.properties'
if (!(Test-Path -LiteralPath $keyFile) -or !(Test-Path -LiteralPath $propertiesFile)) { throw 'Permanent signing material is missing.' }
$properties = ConvertFrom-StringData (Get-Content -LiteralPath $propertiesFile -Raw)
[Convert]::ToBase64String([IO.File]::ReadAllBytes($keyFile)) | & $gh secret set ANDROID_KEYSTORE_BASE64 --repo $repo
$properties.storePassword | & $gh secret set ANDROID_KEYSTORE_PASSWORD --repo $repo
$properties.keyAlias | & $gh secret set ANDROID_KEY_ALIAS --repo $repo
$properties.keyPassword | & $gh secret set ANDROID_KEY_PASSWORD --repo $repo
```

Expected: commands succeed without echoing secret values.

- [ ] **Step 6: Verify secret names and document update compatibility**

```powershell
& 'C:\Program Files\GitHub CLI\gh.exe' secret list --repo yadavnehalkshitiz-cmd/kurama_app --json name
```

Expected: exactly the four required Android secret names are present.

```markdown
<!-- docs/RELEASES.md -->
# Release and Update Compatibility

- Android application ID remains `com.kuramabot.kurama_mobile`.
- Android release builds use the permanent Kurama signing key.
- Never regenerate or replace that key for an update release.
- Version code must increase for every Android update.
- Tagged builds publish Android and Windows artifacts only after both build jobs pass.
- Phase 0 artifacts are engineering builds; public rollout waits for Phase 1 user authentication.
```

- [ ] **Step 7: Run workflow/signing tests and local release builds**

```powershell
python -m unittest tests.test_ci_workflow tests.test_android_signing tests.test_release_version -v
& 'C:\tmp\flutter-sdk\bin\flutter.bat' analyze
& 'C:\tmp\flutter-sdk\bin\flutter.bat' test
& 'C:\tmp\flutter-sdk\bin\flutter.bat' build apk --release --no-tree-shake-icons
```

Run Flutter commands from `mobile/`. Expected: all tests/analyzer pass and a functional local engineering APK is produced. Tagged CI is the required permanent-key verification because signing files are deliberately not copied into the new checkout.

- [ ] **Step 8: Commit release automation**

```powershell
git add -- .github/workflows/flutter_build.yml docs/RELEASES.md tests/test_ci_workflow.py
git commit -m "ci: migrate Kurama App release pipeline"
```

## Task 8: Verify, Publish and Merge Phase 0

**Files:**
- Verify all files in the target repository
- Remote branch: `codex/phase-0-app-separation`
- Pull request into: `main`

**Interfaces:**
- Consumes: all Phase 0 commits and GitHub signing secrets.
- Produces: green `kurama_app` main branch with independently buildable app/backend and intact legacy recovery refs.

- [ ] **Step 1: Run the repository boundary verifier**

Run: `powershell -ExecutionPolicy Bypass -File scripts/verify_repository_boundary.ps1`

Expected: `Repository boundary verified.`

- [ ] **Step 2: Run the complete clean test suite**

```powershell
$env:PYTHONPATH='backend'
$env:KURAMA_API_KEY='local-phase-0-test-key'
python -m unittest discover -s tests -v
& 'C:\tmp\flutter-sdk\bin\flutter.bat' pub get
& 'C:\tmp\flutter-sdk\bin\flutter.bat' analyze
& 'C:\tmp\flutter-sdk\bin\flutter.bat' test
& 'C:\tmp\flutter-sdk\bin\flutter.bat' build apk --release --no-tree-shake-icons
```

Run Flutter commands from `mobile/`. Expected: every command exits zero.

- [ ] **Step 3: Confirm only intentional files are tracked**

```powershell
git status -sb
git ls-files | Select-String -Pattern '(^|/)(\.env|\.idea|downloads|cookies|saved_videos|temp_mobile)(/|$)|key\.properties$|\.(jks|keystore)$'
```

Expected: clean branch and no output from the forbidden-path search.

- [ ] **Step 4: Push the migration branch and open a ready pull request**

```powershell
git push -u origin codex/phase-0-app-separation
& 'C:\Program Files\GitHub CLI\gh.exe' pr create --repo yadavnehalkshitiz-cmd/kurama_app --base main --head codex/phase-0-app-separation --title 'Build the independent Kurama App foundation' --body 'Archives the legacy repository state, migrates the committed Flutter client and app-only FastAPI backend, fixes launcher branding, preserves Android update signing, and adds independent Android/Windows/backend CI.'
```

Expected: the pull request URL is returned.

- [ ] **Step 5: Wait for and inspect all GitHub checks**

Run: `gh pr checks --watch --interval 20 --repo yadavnehalkshitiz-cmd/kurama_app`

Expected: backend CI, Android build/tests and Windows build all pass. Diagnose any failure from its logs before continuing.

- [ ] **Step 6: Merge only after all checks pass**

```powershell
& 'C:\Program Files\GitHub CLI\gh.exe' pr merge --repo yadavnehalkshitiz-cmd/kurama_app --merge --delete-branch
```

Expected: PR is merged into `main`; remote migration branch is deleted.

- [ ] **Step 7: Verify the final repository and recovery path**

```powershell
$gh = 'C:\Program Files\GitHub CLI\gh.exe'
& $gh repo view yadavnehalkshitiz-cmd/kurama_app --json nameWithOwner,url,defaultBranchRef
& $gh api repos/yadavnehalkshitiz-cmd/kurama_app/git/ref/heads/archive/legacy-kurama-bot --jq '.object.sha'
& $gh api repos/yadavnehalkshitiz-cmd/kurama_app/git/ref/tags/legacy-kurama-bot-2026-08-12 --jq '.object.sha'
& $gh run list --repo yadavnehalkshitiz-cmd/kurama_app --limit 5
```

Expected: default branch is green `main`; both archive refs still point to `a5e96a0126bc7ff3729300c02c3ceeb1e842bdaa`.

## Follow-On Plans After Phase 0

1. Phase 0B: clean `kurama_telebot` into a Telegram-only repository after app CI is proven green.
2. Phase 1: Supabase email/password and Google authentication, RLS schema, FastAPI JWT validation and removal of shared API-key input from the public app.
3. Phase 2: reliable download job queue, retries, integrity checks, notifications and user-owned history.
4. Phase 3: multi-tab browser, bookmarks/history/incognito, privacy shields and curated built-in modules.
5. Phase 4: credits, subscriptions, payments and auditable ledger.
6. Phase 5: public release hardening, observability, staged rollout and rollback drills.
