"""Tests for the mobile API contract (api_server.py).

Covers the fixes that broke the mobile app's API client:
- `/api/health` must stay public (connectivity probe).
- Authenticated endpoints must reject missing/bad API keys (401).
- Completed task status must include the real `filename` so the app saves
  the correct extension (mp3/mp4/...).
- The file endpoint must serve bytes with a `Content-Disposition` filename.
- The legacy `/api/user/submit_payment` duplicate must be gone.
"""

import importlib
import os
import shutil
import tempfile
import time
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

import api_server
import user_config

AUTH_KEY = "test-api-key-123"


class MobileApiTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.created_task_ids = []

        # Isolate user-config persistence
        self.config_file = os.path.join(self.temp.name, "users.json")
        uc = importlib.reload(user_config)
        api_server.user_config = uc
        self.file_patch = patch.object(
            api_server.user_config, "USER_CONFIGS_FILE", self.config_file
        )
        self.file_patch.start()
        api_server.user_config._configs = {}

        # Enable auth and isolate the task store
        self._original_key = api_server.API_AUTH_KEY
        api_server.API_AUTH_KEY = AUTH_KEY
        self._original_admin = api_server.API_ADMIN_KEY
        api_server.API_ADMIN_KEY = None
        self._original_tasks = api_server.download_tasks
        api_server.download_tasks = {}
        self._original_max = api_server.MAX_CONCURRENT_DOWNLOADS
        api_server.MAX_CONCURRENT_DOWNLOADS = 5
        self._original_tasks_file = api_server._TASKS_FILE
        api_server._TASKS_FILE = os.path.join(self.temp.name, "tasks.json")

        self.client = TestClient(api_server.app)
        self.headers = {"Authorization": f"Bearer {AUTH_KEY}"}

    def tearDown(self):
        api_server.API_AUTH_KEY = self._original_key
        api_server.API_ADMIN_KEY = self._original_admin
        api_server.download_tasks = self._original_tasks
        api_server.MAX_CONCURRENT_DOWNLOADS = self._original_max
        api_server._TASKS_FILE = self._original_tasks_file
        self.file_patch.stop()
        for task_id in self.created_task_ids:
            task_dir = os.path.join(api_server.TEMP_FOLDER, "mobile_api", task_id)
            shutil.rmtree(task_dir, ignore_errors=True)
        self.temp.cleanup()

    # ── Helpers ──────────────────────────────────────────

    def _make_completed_task(self, task_id="abc-123", name="song.mp3"):
        task_dir = os.path.join(api_server.TEMP_FOLDER, "mobile_api", task_id)
        os.makedirs(task_dir, exist_ok=True)
        filepath = os.path.join(task_dir, name)
        with open(filepath, "wb") as handle:
            handle.write(b"fake media bytes")
        self.created_task_ids.append(task_id)
        api_server.download_tasks[task_id] = {
            "status": "completed",
            "progress": 100,
            "filepath": filepath,
            "file_size": os.path.getsize(filepath),
            "error": None,
            "platform": "YouTube",
            "url": "https://youtube.com/watch?v=abc",
            "thumbnail": "https://img.youtube.com/vi/abc/maxresdefault.jpg",
            "title": "Song",
            "created_at": 0,
            "format": "audio",
            "user_id": 1,
            "speed_bytes_per_second": 0,
            "speed_label": None,
            "eta_seconds": None,
        }
        return filepath

    def _inject_task(self, task_id, status="pending", created_at=None):
        api_server.download_tasks[task_id] = {
            "status": status,
            "progress": 50 if status == "downloading" else 0,
            "filepath": None,
            "file_size": 0,
            "error": None,
            "platform": "YouTube",
            "url": f"https://youtube.com/watch?v={task_id}",
            "title": "Task",
            "created_at": created_at or time.time(),
            "format": "video",
            "user_id": 1,
            "speed_bytes_per_second": 0,
            "speed_label": None,
            "eta_seconds": None,
        }

    # ── Health & auth ────────────────────────────────────

    def test_health_is_public(self):
        resp = self.client.get("/api/health")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json()["status"], "ok")

    def test_authenticated_endpoints_reject_missing_or_bad_key(self):
        missing = self.client.get("/api/platforms")
        self.assertEqual(missing.status_code, 401)
        bad = self.client.get(
            "/api/platforms", headers={"Authorization": "Bearer wrong-key"}
        )
        self.assertEqual(bad.status_code, 401)

    def test_platforms_ok_with_valid_key(self):
        resp = self.client.get("/api/platforms", headers=self.headers)
        self.assertEqual(resp.status_code, 200)
        names = [p["name"] for p in resp.json()["platforms"]]
        self.assertIn("YouTube", names)

    def test_health_reports_configuration(self):
        resp = self.client.get("/api/health")
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertTrue(data["api_key_configured"])
        self.assertIsInstance(data["active_downloads"], int)
        self.assertIsInstance(data["uptime_seconds"], int)

    def test_concurrency_cap_rejects_when_busy(self):
        api_server.MAX_CONCURRENT_DOWNLOADS = 1
        api_server.download_tasks["busy-task"] = {
            "status": "downloading",
            "progress": 10,
            "filepath": None,
            "file_size": 0,
            "error": None,
            "platform": "YouTube",
            "url": "https://youtube.com/watch?v=busy",
            "title": None,
            "created_at": 0,
            "format": "video",
            "user_id": 1,
            "speed_bytes_per_second": 0,
            "speed_label": None,
            "eta_seconds": None,
        }
        resp = self.client.post(
            "/api/download",
            headers=self.headers,
            json={
                "url": "https://youtube.com/watch?v=another",
                "user_id": 1,
            },
        )
        self.assertEqual(resp.status_code, 429)
        # A rejected request must not consume a credit.
        self.assertEqual(api_server.user_config.get_user_credits(1), 3)

    # ── Task status & file delivery ──────────────────────

    def test_status_includes_filename_when_completed(self):
        self._make_completed_task()
        resp = self.client.get("/api/download/abc-123", headers=self.headers)
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(data["status"], "completed")
        self.assertEqual(data["filename"], "song.mp3")
        self.assertGreater(data["file_size"], 0)

    def test_status_includes_thumbnail_for_player_artwork(self):
        self._make_completed_task()
        resp = self.client.get("/api/download/abc-123", headers=self.headers)
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(
            resp.json()["thumbnail"],
            "https://img.youtube.com/vi/abc/maxresdefault.jpg",
        )

    def test_download_request_accepts_thumbnail(self):
        """The app passes the artwork URL when starting a download."""
        req = api_server.DownloadRequest(
            url="https://youtube.com/watch?v=abc",
            user_id=1,
            thumbnail="https://img.youtube.com/vi/abc/maxresdefault.jpg",
        )
        self.assertEqual(
            req.thumbnail, "https://img.youtube.com/vi/abc/maxresdefault.jpg"
        )
        self.assertIsNone(api_server.DownloadRequest(
            url="https://youtube.com/watch?v=abc", user_id=1
        ).thumbnail)

    def test_file_endpoint_serves_bytes_with_content_disposition(self):
        self._make_completed_task()
        resp = self.client.get("/api/download/abc-123/file", headers=self.headers)
        self.assertEqual(resp.status_code, 200)
        self.assertIn("song.mp3", resp.headers.get("content-disposition", ""))
        self.assertEqual(resp.content, b"fake media bytes")

    def test_file_endpoint_rejects_unknown_task(self):
        resp = self.client.get("/api/download/nope/file", headers=self.headers)
        self.assertEqual(resp.status_code, 404)

    def test_status_rejects_unknown_task(self):
        resp = self.client.get("/api/download/nope", headers=self.headers)
        self.assertEqual(resp.status_code, 404)

    # ── Retry & persistence ─────────────────────────────

    def test_retry_failed_task_resets_and_respawns(self):
        original = api_server.background_download
        api_server.background_download = lambda *a, **k: None  # no network
        try:
            self._inject_task("retry-me", status="failed")
            api_server.download_tasks["retry-me"]["error"] = "boom"
            resp = self.client.post(
                "/api/download/retry-me/retry", headers=self.headers
            )
            self.assertEqual(resp.status_code, 200)
            self.assertEqual(resp.json()["status"], "retried")
            task = api_server.download_tasks["retry-me"]
            self.assertEqual(task["status"], "pending")
            self.assertIsNone(task["error"])
            self.assertEqual(task["progress"], 0)
        finally:
            api_server.background_download = original

    def test_retry_rejects_active_and_unknown_tasks(self):
        self._inject_task("active", status="downloading")
        blocked = self.client.post(
            "/api/download/active/retry", headers=self.headers
        )
        self.assertEqual(blocked.status_code, 409)
        missing = self.client.post(
            "/api/download/nope/retry", headers=self.headers
        )
        self.assertEqual(missing.status_code, 404)

    def test_download_request_stores_playlist_flag(self):
        original = api_server.background_download
        api_server.background_download = lambda *a, **k: None  # no network
        try:
            resp = self.client.post(
                "/api/download",
                headers=self.headers,
                json={
                    "url": "https://youtube.com/playlist?list=abc",
                    "user_id": 1,
                    "playlist": True,
                },
            )
            self.assertEqual(resp.status_code, 200)
            tid = resp.json()["task_id"]
            self.assertTrue(api_server.download_tasks[tid]["playlist"])
            self.assertIn(
                "video_quality", api_server.download_tasks[tid]
            )  # needed by retry
        finally:
            api_server.background_download = original

    def test_tasks_persist_and_interrupted_marked_failed(self):
        self._make_completed_task("keep-me", name="song.mp3")
        self._inject_task("mid-flight", status="downloading")
        api_server._save_tasks()
        api_server.download_tasks = {}
        api_server._load_tasks()
        self.assertEqual(
            api_server.download_tasks["keep-me"]["status"], "completed"
        )
        self.assertEqual(
            api_server.download_tasks["mid-flight"]["status"], "failed"
        )
        self.assertIn(
            "Retry", api_server.download_tasks["mid-flight"]["error"]
        )

    def test_recovery_refunds_interrupted_credit(self):
        """A task interrupted by a restart refunds its credit so the retry
        doesn't charge the user twice."""
        api_server.download_tasks["mid"] = {
            "status": "downloading",
            "progress": 10,
            "filepath": None,
            "file_size": 0,
            "error": None,
            "platform": "YouTube",
            "url": "https://youtube.com/watch?v=x",
            "title": None,
            "created_at": time.time(),
            "format": "video",
            "user_id": 5,
            "speed_bytes_per_second": 0,
            "speed_label": None,
            "eta_seconds": None,
            "credit_charged": True,
        }
        api_server.user_config.consume_download_credit(5)  # 3 -> 2
        api_server._save_tasks()
        api_server.download_tasks = {}
        api_server._load_tasks()
        self.assertEqual(api_server.download_tasks["mid"]["status"], "failed")
        # Refunded back to the original balance.
        self.assertEqual(api_server.user_config.get_user_credits(5), 3)

    # ── SSE realtime stream ─────────────────────────────

    def test_sse_stream_emits_status_event(self):
        self._make_completed_task("sse-1", name="clip.mp4")
        with self.client.stream(
            "GET", "/api/download/sse-1/stream", headers=self.headers
        ) as resp:
            self.assertEqual(resp.status_code, 200)
            content_type = resp.headers.get("content-type", "")
            self.assertTrue(content_type.startswith("text/event-stream"))
            body = "".join(list(resp.iter_text()))
        self.assertIn("event: status", body)
        self.assertIn('"status": "completed"', body)

    def test_sse_stream_requires_auth(self):
        self._make_completed_task("sse-2", name="clip.mp4")
        resp = self.client.get("/api/download/sse-2/stream")
        self.assertEqual(resp.status_code, 401)

    # ── Range requests (resume support) ──────────────────

    def test_file_endpoint_advertises_range_support(self):
        filepath = self._make_completed_task("range-1", name="clip.mp4")
        size = os.path.getsize(filepath)
        resp = self.client.get(
            "/api/download/range-1/file", headers=self.headers
        )
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.headers.get("accept-ranges"), "bytes")
        self.assertEqual(int(resp.headers.get("content-length")), size)
        self.assertEqual(resp.content, b"fake media bytes")

    def test_file_endpoint_serves_partial_range_206(self):
        filepath = self._make_completed_task("range-2", name="clip.mp4")
        size = os.path.getsize(filepath)
        resp = self.client.get(
            "/api/download/range-2/file",
            headers={**self.headers, "Range": "bytes=4-9"},
        )
        self.assertEqual(resp.status_code, 206)
        self.assertEqual(
            resp.headers.get("content-range"), f"bytes 4-9/{size}"
        )
        self.assertEqual(resp.headers.get("content-length"), "6")
        self.assertEqual(resp.content, b"fake media bytes"[4:10])

    def test_file_endpoint_serves_open_ended_range_206(self):
        """`Range: bytes=N-` (the exact resume case) returns the tail."""
        filepath = self._make_completed_task("range-3", name="clip.mp4")
        size = os.path.getsize(filepath)
        resp = self.client.get(
            "/api/download/range-3/file",
            headers={**self.headers, "Range": "bytes=5-"},
        )
        self.assertEqual(resp.status_code, 206)
        self.assertEqual(
            resp.headers.get("content-range"), f"bytes 5-{size - 1}/{size}"
        )
        self.assertEqual(resp.content, b"fake media bytes"[5:])

    def test_file_endpoint_rejects_unsatisfiable_range_416(self):
        filepath = self._make_completed_task("range-4", name="clip.mp4")
        size = os.path.getsize(filepath)
        resp = self.client.get(
            "/api/download/range-4/file",
            headers={**self.headers, "Range": "bytes=999-"},
        )
        self.assertEqual(resp.status_code, 416)
        self.assertEqual(
            resp.headers.get("content-range"), f"bytes */{size}"
        )

    def test_file_endpoint_range_without_auth_is_401(self):
        self._make_completed_task("range-5", name="clip.mp4")
        resp = self.client.get(
            "/api/download/range-5/file",
            headers={"Range": "bytes=0-"},
        )
        self.assertEqual(resp.status_code, 401)

    # ── Payments ─────────────────────────────────────────

    def test_legacy_underscore_payment_endpoint_is_removed(self):
        resp = self.client.post(
            "/api/user/submit_payment",
            headers=self.headers,
            json={"user_id": 1, "tx_id": "TX-1"},
        )
        self.assertEqual(resp.status_code, 404)

    def test_payment_endpoint_validates_method(self):
        resp = self.client.post(
            "/api/user/submit-payment",
            headers=self.headers,
            data={"user_id": "1", "tx_id": "TX-9", "method": "bitcoin"},
        )
        self.assertEqual(resp.status_code, 400)

    # ── Admin endpoints ─────────────────────────────────

    def test_admin_tasks_requires_auth(self):
        resp = self.client.get("/api/admin/tasks")
        self.assertEqual(resp.status_code, 401)

    def test_admin_key_separates_when_configured(self):
        api_server.API_ADMIN_KEY = "admin-secret-42"
        try:
            main = self.client.get("/api/admin/tasks", headers=self.headers)
            self.assertEqual(main.status_code, 401)
            admin = self.client.get(
                "/api/admin/tasks",
                headers={"Authorization": "Bearer admin-secret-42"},
            )
            self.assertEqual(admin.status_code, 200)
        finally:
            api_server.API_ADMIN_KEY = None

    def test_admin_tasks_lists_with_counts(self):
        self._make_completed_task("t1", name="a.mp3")
        self._inject_task("t2", status="downloading")
        resp = self.client.get("/api/admin/tasks", headers=self.headers)
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(data["total"], 2)
        self.assertEqual(data["counts"]["completed"], 1)
        self.assertEqual(data["counts"]["downloading"], 1)
        self.assertEqual(data["active"], 1)
        self.assertEqual({t["task_id"] for t in data["tasks"]}, {"t1", "t2"})

    def test_admin_delete_task_purges_file(self):
        filepath = self._make_completed_task("purge-me", name="clip.mp4")
        self.assertTrue(os.path.exists(filepath))
        resp = self.client.delete(
            "/api/admin/tasks/purge-me", headers=self.headers
        )
        self.assertEqual(resp.status_code, 200)
        self.assertNotIn("purge-me", api_server.download_tasks)
        self.assertFalse(os.path.exists(filepath))

    def test_admin_delete_unknown_task_returns_404(self):
        resp = self.client.delete(
            "/api/admin/tasks/does-not-exist", headers=self.headers
        )
        self.assertEqual(resp.status_code, 404)

    def test_admin_delete_downloading_requires_force(self):
        self._inject_task("dl-1", status="downloading")
        blocked = self.client.delete(
            "/api/admin/tasks/dl-1", headers=self.headers
        )
        self.assertEqual(blocked.status_code, 409)
        forced = self.client.delete(
            "/api/admin/tasks/dl-1?force=true", headers=self.headers
        )
        self.assertEqual(forced.status_code, 200)
        gone = self.client.get("/api/download/dl-1", headers=self.headers)
        self.assertEqual(gone.status_code, 404)

    def test_admin_bulk_purge_removes_stuck_downloads(self):
        now = time.time()
        self._inject_task("stuck", status="downloading", created_at=now - 7200)
        self._inject_task("fresh", status="downloading", created_at=now)
        resp = self.client.post(
            "/api/admin/tasks/purge",
            headers=self.headers,
            json={"older_than_seconds": 300, "stuck_after_seconds": 3600},
        )
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json()["purged"], 1)
        self.assertNotIn("stuck", api_server.download_tasks)
        self.assertIn("fresh", api_server.download_tasks)

    def test_admin_bulk_purge_old_terminal_keeps_fresh(self):
        now = time.time()
        self._inject_task("old-done", status="completed", created_at=now - 1000)
        self._inject_task("fresh", status="downloading", created_at=now)
        resp = self.client.post(
            "/api/admin/tasks/purge",
            headers=self.headers,
            json={"older_than_seconds": 600, "stuck_after_seconds": 3600},
        )
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(data["purged"], 1)
        self.assertIn("old-done", data["task_ids"])
        self.assertNotIn("old-done", api_server.download_tasks)
        self.assertIn("fresh", api_server.download_tasks)

    # ── Daily reward ─────────────────────────────────────

    def test_daily_reward_conflict_shape_is_actionable(self):
        first = self.client.post("/api/user/7/claim-daily", headers=self.headers)
        self.assertEqual(first.status_code, 200)
        self.assertTrue(first.json()["claimed"])

        second = self.client.post("/api/user/7/claim-daily", headers=self.headers)
        self.assertEqual(second.status_code, 409)
        detail = second.json()["detail"]
        self.assertIn("message", detail)
        self.assertFalse(detail["claimed"])


if __name__ == "__main__":
    unittest.main()
