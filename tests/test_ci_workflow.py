from pathlib import Path
import unittest


class FlutterWorkflowTests(unittest.TestCase):
    @staticmethod
    def workflow_text():
        return (
            Path(__file__).parents[1] / ".github" / "workflows" / "flutter_build.yml"
        ).read_text(encoding="utf-8")

    def test_android_job_does_not_regenerate_committed_runner(self):
        workflow = self.workflow_text()

        self.assertNotIn("flutter create --platforms=android .", workflow)

    def test_windows_job_pins_visual_studio_2022_runner(self):
        workflow = self.workflow_text()

        self.assertIn("runs-on: windows-2022", workflow)
        self.assertNotIn("runs-on: windows-latest", workflow)

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
        self.assertIn(
            "rm -f android/app/kuramabot-release.jks android/key.properties",
            workflow,
        )


if __name__ == "__main__":
    unittest.main()
