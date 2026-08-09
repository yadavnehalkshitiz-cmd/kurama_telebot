# Tech Stack and Android Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enforce Android 9+ support and present the repository's actual languages and technology stack clearly without publishing credentials.

**Architecture:** Add one repository-level configuration test that treats the README, Android minimum SDK, and API-key source policy as a single release contract. Update only the root README and Android app configuration; keep GitHub Linguist defaults because the existing language chart already identifies Dart and Python correctly.

**Tech Stack:** Flutter, Dart, Python, FastAPI, python-telegram-bot, yt-dlp, Kotlin, Swift, Gradle 9.1, Android Gradle Plugin 9.0.1, JVM 17, Python `unittest`, GitHub CLI.

## Global Constraints

- Android support begins at Android 9, API level 28.
- Dart and Python are the primary project languages.
- Kotlin and Swift are platform-integration languages; JVM 17 is an Android build target, not a primary language.
- Do not add badge clutter or GitHub Linguist overrides.
- Do not commit a production API credential; use `String.fromEnvironment('KURAMA_API_KEY')`.
- Preserve staged `.idea/` and `.artifacts/` files and untracked `setup_dev.ps1` outside the PR scope.

---

### Task 1: Define and implement the mobile repository contract

**Files:**
- Create: `tests/test_mobile_configuration.py`
- Modify: `README.md`
- Modify: `kurama_mobile/android/app/build.gradle.kts:29-37`
- Verify: `kurama_mobile/lib/main.dart:50-85`

**Interfaces:**
- Consumes: the root README, Gradle Kotlin DSL application configuration, and the mobile startup configuration.
- Produces: an enforced API 28 minimum, accurate stack documentation, and a source-level guard against hardcoded production API keys.

- [ ] **Step 1: Write the failing repository configuration tests**

Create `tests/test_mobile_configuration.py`:

```python
from pathlib import Path
import re
import unittest


class MobileConfigurationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).parents[1]
        cls.gradle = (root / "kurama_mobile" / "android" / "app" / "build.gradle.kts").read_text(encoding="utf-8")
        cls.main = (root / "kurama_mobile" / "lib" / "main.dart").read_text(encoding="utf-8")
        cls.readme = (root / "README.md").read_text(encoding="utf-8")

    def test_android_support_starts_at_api_28(self):
        self.assertIn("minSdk = 28", self.gradle)
        self.assertNotIn("minSdk = flutter.minSdkVersion", self.gradle)

    def test_readme_describes_the_actual_stack_and_languages(self):
        for text in (
            "## 🧰 Tech Stack & Languages",
            "Dart and Python are the primary languages",
            "Android 9+ (API 28)",
            "Kotlin",
            "Swift",
            "JVM 17",
        ):
            self.assertIn(text, self.readme)

    def test_production_api_key_is_supplied_at_build_time(self):
        self.assertIn("String.fromEnvironment('KURAMA_API_KEY')", self.main)
        self.assertIsNone(re.search(r"const\s+prodKey\s*=\s*'[^']+'", self.main))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the focused test and verify RED**

Run: `python -m unittest tests.test_mobile_configuration -v`

Expected: the Android API floor and README stack tests fail; the API-key test passes.

- [ ] **Step 3: Enforce Android 9+**

In `kurama_mobile/android/app/build.gradle.kts`, replace the default minimum SDK assignment with:

```kotlin
minSdk = 28
```

- [ ] **Step 4: Add the clean README stack section**

Insert this section after the introductory paragraph and first divider:

```markdown
## 🧰 Tech Stack & Languages

Dart and Python are the primary languages in KuramaBot. Kotlin and Swift are
used only for native mobile integration, while JVM 17 is the Android build
target rather than an application language.

| Area | Stack |
|------|-------|
| Mobile app | Flutter, Dart |
| Backend and bot | Python, FastAPI, python-telegram-bot, yt-dlp, Uvicorn |
| Android | Android 9+ (API 28), Kotlin, Gradle 9.1, AGP 9.0.1, JVM 17 |
| iOS | Swift |
| Delivery | Docker, GitHub Actions, Render |

---
```

- [ ] **Step 5: Run the focused test and verify GREEN**

Run: `python -m unittest tests.test_mobile_configuration -v`

Expected: all three tests pass.

- [ ] **Step 6: Run repository and Flutter verification**

Run:

```powershell
python -m unittest discover -s tests -v
flutter test
flutter analyze --no-fatal-infos
flutter build apk --release
```

Expected: all Python and Flutter tests pass, analysis has zero errors, and the release APK builds successfully.

- [ ] **Step 7: Verify security and scope**

Run a credential-pattern scan over tracked source, `git diff --check`, and inspect `git status -sb`. Confirm `.idea/`, `.artifacts/`, and `setup_dev.ps1` remain outside the implementation commit.

- [ ] **Step 8: Create the scoped implementation commit**

Stage the new test, then use `git commit --only` with `README.md`, `tests/test_mobile_configuration.py`, and the previously confirmed `kurama_mobile` paths. Use commit message:

```text
Improve mobile downloads and Android release build
```

### Task 2: Publish the draft pull request

**Files:**
- No additional repository files.

**Interfaces:**
- Consumes: branch `improve/api-and-player` with its design, plan, and scoped implementation commits.
- Produces: a pushed remote branch and a draft pull request targeting `main`.

- [ ] **Step 1: Push the branch**

Run: `git push -u origin improve/api-and-player`

Expected: the remote branch updates without force-pushing.

- [ ] **Step 2: Create the draft PR**

Create a draft PR against `main` with a title covering mobile download improvements and Android release fixes. The body must summarize the stack cleanup, Android 9+ floor, credential handling, Gallery behavior, AGP/Kotlin root causes, and all validation commands.

- [ ] **Step 3: Report the handoff**

Report the branch, implementation commit, PR URL, APK path/hash, test counts, analyzer status, and the excluded local files that remain untouched.
