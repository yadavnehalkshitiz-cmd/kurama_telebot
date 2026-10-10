import unittest
from unittest.mock import AsyncMock, MagicMock, patch
import telegram.error

from handlers import _handle_format, _safe_edit, sessions, _recover_session


class TestDownloadFlow(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        sessions.clear()

    async def test_format_video_triggers_direct_download(self):
        chat_id = 999111
        sessions[chat_id] = {
            "url": "https://vt.tiktok.com/test/",
            "title": "TikTok Test Video",
            "platform": "TikTok",
            "icon": "🎵",
            "format": "video",
        }
        query = MagicMock()
        context = MagicMock()
        context.user_data = {}

        with patch("handlers._run_download", new_callable=AsyncMock) as mock_dl:
            await _handle_format(query, chat_id, "fmt_video", context)
            mock_dl.assert_awaited_once_with(chat_id, query, context)
            self.assertEqual(sessions[chat_id]["video_quality"], "best")
            self.assertEqual(sessions[chat_id]["destination"], "mobile")

    async def test_format_audio_triggers_direct_download(self):
        chat_id = 999222
        sessions[chat_id] = {
            "url": "https://vt.tiktok.com/test/",
            "title": "TikTok Test Video",
            "platform": "TikTok",
            "icon": "🎵",
            "format": "video",
        }
        query = MagicMock()
        context = MagicMock()
        context.user_data = {}

        with patch("handlers._run_download", new_callable=AsyncMock) as mock_dl:
            await _handle_format(query, chat_id, "fmt_audio", context)
            mock_dl.assert_awaited_once_with(chat_id, query, context)
            self.assertEqual(sessions[chat_id]["format"], "audio")
            self.assertEqual(sessions[chat_id]["audio_quality"], "best")
            self.assertEqual(sessions[chat_id]["destination"], "mobile")

    async def test_safe_edit_markdown_fallback(self):
        query = MagicMock()
        query.message.photo = True
        # First call with Markdown fails (e.g. Can't parse entities)
        query.edit_message_caption = AsyncMock(side_effect=[
            telegram.error.BadRequest("Can't parse entities"),
            True,
        ])
        await _safe_edit(query, "📌 *Unbalanced _markdown test")
        self.assertEqual(query.edit_message_caption.await_count, 2)
        # Second call should have parse_mode=None
        second_call_kwargs = query.edit_message_caption.await_args_list[1][1]
        self.assertIsNone(second_call_kwargs.get("parse_mode"))

    async def test_recover_session_from_user_data(self):
        chat_id = 999333
        query = MagicMock()
        context = MagicMock()
        stored_sess = {
            "url": "https://vt.tiktok.com/recovered/",
            "title": "Recovered Title",
            "platform": "TikTok",
            "icon": "🎵",
            "destination": "mobile",
        }
        context.user_data = {"session": stored_sess}

        recovered = await _recover_session(query, chat_id, context)
        self.assertIsNotNone(recovered)
        self.assertEqual(recovered["url"], "https://vt.tiktok.com/recovered/")
        self.assertIn(chat_id, sessions)


if __name__ == "__main__":
    unittest.main()
