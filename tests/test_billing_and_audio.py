import importlib
import json
import os
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import patch


class BillingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.config_file = os.path.join(self.temp.name, "users.json")
        import user_config
        self.user_config = importlib.reload(user_config)
        self.file_patch = patch.object(
            self.user_config, "USER_CONFIGS_FILE", self.config_file
        )
        self.file_patch.start()
        self.user_config._configs = {}

    def tearDown(self):
        self.file_patch.stop()
        self.temp.cleanup()

    def test_credit_is_consumed_and_refunded(self):
        allowed, charged = self.user_config.consume_download_credit(41)
        self.assertTrue(allowed)
        self.assertTrue(charged)
        self.assertEqual(self.user_config.get_user_credits(41), 2)
        self.user_config.refund_credit(41)
        self.assertEqual(self.user_config.get_user_credits(41), 3)

    def test_daily_reward_can_only_be_claimed_once_per_24_hours(self):
        now = datetime(2026, 8, 4, tzinfo=timezone.utc)
        first = self.user_config.claim_daily_reward(42, now=now)
        second = self.user_config.claim_daily_reward(
            42, now=now + timedelta(hours=23)
        )
        third = self.user_config.claim_daily_reward(
            42, now=now + timedelta(hours=24)
        )
        self.assertTrue(first["claimed"])
        self.assertFalse(second["claimed"])
        self.assertTrue(third["claimed"])
        self.assertEqual(third["credits"], 7)

    def test_payment_records_method_and_receipt(self):
        payment = self.user_config.add_pending_payment(
            43, "TX-777", method="khalti", receipt_path="receipts/43.jpg"
        )
        self.assertEqual(payment["method"], "khalti")
        self.assertEqual(payment["receipt_path"], "receipts/43.jpg")
        with open(self.config_file, encoding="utf-8") as handle:
            saved = json.load(handle)
        self.assertEqual(saved["43"]["pending_payments"][0]["tx_id"], "TX-777")


class AudioOptionsTests(unittest.TestCase):
    def test_audio_download_embeds_metadata_and_thumbnail(self):
        from downloader import build_ydl_opts

        with patch("downloader.get_ffmpeg_path", return_value="ffmpeg"):
            opts = build_ydl_opts(
                self.temp_dir(), audio_only=True, audio_quality="192k"
            )
        keys = [item["key"] for item in opts["postprocessors"]]
        self.assertEqual(
            keys, ["FFmpegExtractAudio", "FFmpegMetadata", "EmbedThumbnail"]
        )
        self.assertTrue(opts["writethumbnail"])

    def temp_dir(self):
        return tempfile.gettempdir()


if __name__ == "__main__":
    unittest.main()
