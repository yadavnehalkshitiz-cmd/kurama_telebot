from pathlib import Path
import re
import unittest


class MobileConfigurationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).parents[1]
        cls.gradle = (
            root / "kurama_mobile" / "android" / "app" / "build.gradle.kts"
        ).read_text(encoding="utf-8")
        cls.main = (root / "kurama_mobile" / "lib" / "main.dart").read_text(
            encoding="utf-8"
        )
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
