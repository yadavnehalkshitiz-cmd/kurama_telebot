from pathlib import Path
import unittest


class ReleaseVersionTests(unittest.TestCase):
    def test_flutter_version_matches_next_release(self):
        pubspec = (
            Path(__file__).parents[1] / "kurama_mobile" / "pubspec.yaml"
        ).read_text(encoding="utf-8")

        self.assertIn("version: 1.1.1+3", pubspec)


if __name__ == "__main__":
    unittest.main()
