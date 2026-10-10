from pathlib import Path
import unittest


class BotWorkflowTests(unittest.TestCase):
    @staticmethod
    def workflow_text():
        return (
            Path(__file__).parents[1] / ".github" / "workflows" / "test.yml"
        ).read_text(encoding="utf-8")

    def test_workflow_runs_python_tests(self):
        workflow = self.workflow_text()
        self.assertIn("python -m unittest discover tests", workflow)
        self.assertIn("pip install -r requirements.txt", workflow)

    def test_workflow_does_not_contain_flutter_app_build(self):
        workflow = self.workflow_text()
        self.assertNotIn("flutter build", workflow)
        self.assertNotIn("build_android", workflow)
        self.assertNotIn("build_windows", workflow)


if __name__ == "__main__":
    unittest.main()
