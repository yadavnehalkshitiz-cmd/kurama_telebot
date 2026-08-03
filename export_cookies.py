"""
export_cookies.py — Auto-export login cookies from Chrome to the cookies/ folder.
Run this script while Chrome is CLOSED for best results.
"""

import os
import sys
import sqlite3
import shutil
import json
import base64
import tempfile
from pathlib import Path
from datetime import datetime, timedelta

# Force UTF-8 output on Windows terminal
if sys.stdout.encoding != 'utf-8':
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

# ─── Try to import needed packages ───────────────────────────────────────────
try:
    import win32crypt
except ImportError:
    win32crypt = None

try:
    from Crypto.Cipher import AES
except ImportError:
    AES = None

SCRIPT_DIR = Path(__file__).parent
COOKIES_DIR = SCRIPT_DIR / "cookies"
COOKIES_DIR.mkdir(exist_ok=True)

CHROME_USER_DATA = Path(os.environ.get("LOCALAPPDATA", "")) / "Google" / "Chrome" / "User Data"
CHROME_LOCAL_STATE = CHROME_USER_DATA / "Local State"

PLATFORMS = {
    "instagram": [".instagram.com", "instagram.com"],
    "youtube":   [".youtube.com", "youtube.com"],
    "twitter":   [".twitter.com", "twitter.com", ".x.com", "x.com"],
    "facebook":  [".facebook.com", "facebook.com"],
    "tiktok":    [".tiktok.com", "tiktok.com"],
    "reddit":    [".reddit.com", "reddit.com"],
}


def get_chrome_encryption_key():
    """Retrieve AES encryption key Chrome uses for cookies (Windows only)."""
    if not CHROME_LOCAL_STATE.exists():
        return None
    try:
        with open(CHROME_LOCAL_STATE, "r", encoding="utf-8") as f:
            local_state = json.load(f)
        encrypted_key = base64.b64decode(local_state["os_crypt"]["encrypted_key"])
        # Strip DPAPI prefix "DPAPI"
        encrypted_key = encrypted_key[5:]
        if win32crypt:
            return win32crypt.CryptUnprotectData(encrypted_key, None, None, None, 0)[1]
    except Exception as e:
        print(f"  [!] Could not get Chrome key: {e}")
    return None


def decrypt_cookie_value(encrypted_value, key):
    """Decrypt a Chrome cookie value."""
    try:
        if encrypted_value[:3] == b'v10' or encrypted_value[:3] == b'v11':
            # AES-256-GCM (newer Chrome)
            if AES is None:
                return ""
            iv = encrypted_value[3:15]
            payload = encrypted_value[15:]
            cipher = AES.new(key, AES.MODE_GCM, nonce=iv)
            return cipher.decrypt(payload)[:-16].decode("utf-8")
        elif win32crypt:
            # DPAPI fallback (older Chrome)
            return win32crypt.CryptUnprotectData(encrypted_value, None, None, None, 0)[1].decode("utf-8")
    except Exception:
        pass
    return ""


def epoch_to_netscape_expiry(epoch_microseconds):
    """Convert Chrome's microsecond epoch to Unix timestamp."""
    if epoch_microseconds == 0:
        return 0
    # Chrome stores time as microseconds since Jan 1, 1601
    delta = timedelta(microseconds=epoch_microseconds)
    base = datetime(1601, 1, 1)
    unix_epoch = datetime(1970, 1, 1)
    return int((base + delta - unix_epoch).total_seconds())


def to_netscape_format(host, name, value, path, expiry, secure, httponly):
    """Format a cookie as a Netscape cookie file line."""
    include_subdomain = "TRUE" if host.startswith(".") else "FALSE"
    secure_flag = "TRUE" if secure else "FALSE"
    return f"{host}\t{include_subdomain}\t{path}\t{secure_flag}\t{expiry}\t{name}\t{value}"


def get_profile_cookies(profile_db, platform, domains, key):
    """Extract cookies for a specific profile and platform."""
    tmp_db = Path(tempfile.mktemp(suffix=".db"))
    try:
        shutil.copy2(profile_db, tmp_db)
    except Exception:
        return []

    cookies = []
    try:
        conn = sqlite3.connect(str(tmp_db))
        cursor = conn.cursor()
        
        base_domains = list({d.lstrip('.') for d in domains})
        conditions = " OR ".join(["host_key LIKE ?" for _ in base_domains])
        like_vals = [f"%{d}" for d in base_domains]
        
        cursor.execute(
            f"SELECT host_key, name, encrypted_value, path, expires_utc, is_secure, is_httponly "
            f"FROM cookies WHERE {conditions}",
            like_vals
        )
        rows = cursor.fetchall()
        conn.close()

        for host_key, name, encrypted_value, path, expires_utc, is_secure, is_httponly in rows:
            value = decrypt_cookie_value(encrypted_value, key) if key else ""
            if not value:
                continue
            expiry = epoch_to_netscape_expiry(expires_utc)
            cookies.append(to_netscape_format(host_key, name, value, path, expiry, is_secure, is_httponly))
    except Exception:
        pass
    finally:
        tmp_db.unlink(missing_ok=True)
    return cookies


def export_platform_cookies(platform, domains, key):
    """Scan all Chrome profiles for platform cookies."""
    all_platform_cookies = ["# Netscape HTTP Cookie File"]
    
    # Standard profile folders in Chrome
    profiles = ["Default"]
    if CHROME_USER_DATA.exists():
        # Add Profile 1, Profile 2, etc.
        for p in CHROME_USER_DATA.glob("Profile *"):
            if p.is_dir():
                profiles.append(p.name)

    found_any = False
    total_count = 0
    
    for profile in profiles:
        db_path = CHROME_USER_DATA / profile / "Network" / "Cookies"
        if not db_path.exists():
            continue
            
        cookies = get_profile_cookies(db_path, platform, domains, key)
        if cookies:
            all_platform_cookies.extend(cookies)
            total_count += len(cookies)
            found_any = True

    if not found_any:
        print(f"  [-] {platform:12s} -- Not logged in in any Chrome profile.")
        return False

    out_file = COOKIES_DIR / f"{platform}.txt"
    with open(out_file, "w", encoding="utf-8") as f:
        f.write("\n".join(all_platform_cookies))

    print(f"  [OK] {platform:12s} -- {total_count} cookies saved -> cookies/{platform}.txt")
    return True


def main():
    print("=" * 55)
    print("  KuramaBot Cookie Exporter")
    print("  Extracting from: Google Chrome")
    print("=" * 55)
    print()

    # Dependency check
    missing = []
    if win32crypt is None:
        missing.append("pywin32")
    if AES is None:
        missing.append("pycryptodome")
    if missing:
        print(f"[!] Missing packages: {', '.join(missing)}")
        print(f"    Run: .venv\\Scripts\\pip install {' '.join(missing)}")
        print()

    # Get decryption key
    print("[*] Reading Chrome encryption key...")
    key = get_chrome_encryption_key()
    if key:
        print("    Key retrieved successfully.\n")
    else:
        print("    Could not retrieve key — cookie values may be empty.\n")

    # Export each platform
    print("[*] Exporting cookies...\n")
    results = {}
    for platform, domains in PLATFORMS.items():
        results[platform] = export_platform_cookies(platform, domains, key)

    # Summary
    print()
    print("=" * 55)
    print("  Summary")
    print("=" * 55)
    success = [p for p, ok in results.items() if ok]
    failed  = [p for p, ok in results.items() if not ok]

    if success:
        print(f"\n  [OK] Exported: {', '.join(success)}")
    if failed:
        print(f"\n  [-]  Skipped:  {', '.join(failed)}")
        print(f"\n       For skipped platforms, make sure you are logged in")
        print(f"       on Chrome, close Chrome, and run this script again.")

    print()
    print(f"  Cookie files saved to: {COOKIES_DIR}")
    print()
    print("  Run the bot and type /cookies in Telegram to verify.")
    print("=" * 55)


if __name__ == "__main__":
    main()
