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
