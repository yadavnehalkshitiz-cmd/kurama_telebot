from pathlib import Path
import unittest


class FlutterWorkflowTests(unittest.TestCase):
    def test_android_job_does_not_regenerate_committed_runner(self):
        workflow = (
            Path(__file__).parents[1] / ".github" / "workflows" / "flutter_build.yml"
        ).read_text(encoding="utf-8")

        self.assertNotIn("flutter create --platforms=android .", workflow)


if __name__ == "__main__":
    unittest.main()
