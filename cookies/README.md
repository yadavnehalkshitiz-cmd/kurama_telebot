# 🍪 Cookies Folder

Place your platform cookie files here to enable downloads from sites that require login.

## Required filenames

| Platform   | Filename          |
|------------|-------------------|
| Instagram  | `instagram.txt`   |
| Twitter/X  | `twitter.txt`     |
| Facebook   | `facebook.txt`    |
| YouTube    | `youtube.txt`     |
| TikTok     | `tiktok.txt`      |
| Reddit     | `reddit.txt`      |

## How to export cookies (5 minutes)

1. **Install the Chrome extension**: [Get cookies.txt LOCALLY](https://chrome.google.com/webstore/detail/get-cookiestxt-locally/cclelndahbckbenkjhflpdbgdldlbecc)

2. **Log in** to the platform in Chrome (e.g., instagram.com)

3. **Click the extension icon** in your Chrome toolbar → click **Export**

4. **Save the file** to this `cookies/` folder with the exact filename above  
   (e.g., `cookies/instagram.txt`)

5. **Restart KuramaBot** — it will automatically use the cookies!

## Security Notes

- ⚠️ Cookie files contain your **login session** — treat them like passwords
- ✅ They are stored **only on your laptop** and never sent anywhere except the target platform
- ✅ The `cookies/` folder is listed in `.gitignore` so they won't be accidentally committed to Git
- 🔄 If downloads start failing again, your cookies may have expired — re-export them

## Check status in the bot

Use the `/cookies` command inside Telegram to see which cookie files are loaded.
