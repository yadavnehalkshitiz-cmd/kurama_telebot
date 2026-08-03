import sqlite3
import shutil
import tempfile
import os
from pathlib import Path

CHROME_COOKIES_DB = Path(os.environ.get("LOCALAPPDATA", "")) / "Google" / "Chrome" / "User Data" / "Default" / "Network" / "Cookies"

def inspect_cookies():
    if not CHROME_COOKIES_DB.exists():
        print("DB not found")
        return

    tmp_db = Path(tempfile.mktemp(suffix=".db"))
    shutil.copy2(CHROME_COOKIES_DB, tmp_db)

    try:
        conn = sqlite3.connect(str(tmp_db))
        cursor = conn.cursor()
        
        print("Checking top 20 domains in the database:")
        cursor.execute("SELECT host_key, COUNT(*) as c FROM cookies GROUP BY host_key ORDER BY c DESC LIMIT 20")
        rows = cursor.fetchall()
        for row in rows:
            print(f"  {row[0]}: {row[1]}")
            
        print("\nChecking specifically for instagram/tiktok/twitter:")
        cursor.execute("SELECT host_key FROM cookies WHERE host_key LIKE '%instagram%' OR host_key LIKE '%tiktok%' OR host_key LIKE '%twitter%' OR host_key LIKE '%x.com%'")
        rows = cursor.fetchall()
        if not rows:
            print("  No matches found for those platforms.")
        for row in rows:
            print(f"  Match: {row[0]}")
            
        conn.close()
    except Exception as e:
        print(f"Error: {e}")
    finally:
        if tmp_db.exists():
            tmp_db.unlink()

if __name__ == "__main__":
    inspect_cookies()
