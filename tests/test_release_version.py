from pathlib import Path
import re
import unittest


class ReleaseVersionTests(unittest.TestCase):
    def test_flutter_version_has_semver_plus_build(self):
        pubspec = (
            Path(__file__).parents[1] / "kurama_mobile" / "pubspec.yaml"
        ).read_text(encoding="utf-8")

        # Expect a version like: 1.2.0+4
        import re
        self.assertIsNotNone(re.search(r"version:\s*\d+\.\d+\.\d+\+\d+", pubspec))


if __name__ == "__main__":
    unittest.main()
