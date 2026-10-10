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


    async def test_handle_document_installs_cookies(self):
        from handlers import handle_document
        import os
        from config import COOKIES_FOLDER

        update = MagicMock()
        update.effective_chat.id = 999444
        doc = MagicMock()
        doc.file_name = "instagram.txt"
        doc.file_size = 1024
        doc.file_id = "doc_123"
        update.message.document = doc

        status_msg = MagicMock()
        status_msg.edit_text = AsyncMock()
        update.message.reply_text = AsyncMock(return_value=status_msg)

        context = MagicMock()
        tg_file = MagicMock()
        cookie_data = b"# Netscape HTTP Cookie File\n.instagram.com\tTRUE\t/\tTRUE\t1800000000\tsessionid\tabc123\n"
        tg_file.download_as_bytearray = AsyncMock(return_value=bytearray(cookie_data))
        context.bot.get_file = AsyncMock(return_value=tg_file)

        await handle_document(update, context)

        status_msg.edit_text.assert_awaited()
        call_text = status_msg.edit_text.await_args[0][0]
        self.assertIn("Instagram Cookies Installed", call_text)

        installed_path = os.path.join(COOKIES_FOLDER, "instagram.txt")
        self.assertTrue(os.path.exists(installed_path))
        with open(installed_path, "r", encoding="utf-8") as f:
            self.assertEqual(f.read(), cookie_data.decode("utf-8"))


if __name__ == "__main__":
    unittest.main()
