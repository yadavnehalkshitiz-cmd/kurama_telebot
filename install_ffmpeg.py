import os
import zipfile
import urllib.request
import shutil
import sys

FFMPEG_URL = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
ZIP_NAME = "ffmpeg.zip"
EXTRACT_FOLDER = "ffmpeg_temp"

def install_ffmpeg():
    print(f"Downloading FFmpeg from {FFMPEG_URL}...")
    try:
        # Download the file
        urllib.request.urlretrieve(FFMPEG_URL, ZIP_NAME)
        print("Download complete.")

        # Extract the zip file
        print("Extracting...")
        with zipfile.ZipFile(ZIP_NAME, 'r') as zip_ref:
            zip_ref.extractall(EXTRACT_FOLDER)
        
        # Find ffmpeg.exe
        ffmpeg_exe_path = None
        for root, dirs, files in os.walk(EXTRACT_FOLDER):
            if "ffmpeg.exe" in files:
                ffmpeg_exe_path = os.path.join(root, "ffmpeg.exe")
                break
        
        if ffmpeg_exe_path:
            # Move ffmpeg.exe to script directory
            script_dir = os.path.dirname(os.path.abspath(__file__))
            destination = os.path.join(script_dir, "ffmpeg.exe")
            if os.path.exists(destination):
                print(f"ffmpeg.exe already exists at {destination}")
            else:
                # Cast to string safely to satisfy type checkers and ensure it's not None
                shutil.move(str(ffmpeg_exe_path), destination)
                print(f"ffmpeg.exe installed to {destination}")

            print("FFmpeg installation successful!")
        else:
            print("Error: Could not find ffmpeg.exe in the downloaded archive.")

        # Clean up
        print("Cleaning up temporary files...")
        if os.path.exists(ZIP_NAME):
            os.remove(ZIP_NAME)
        if os.path.exists(EXTRACT_FOLDER):
            shutil.rmtree(EXTRACT_FOLDER)

    except Exception as e:
        print(f"An error occurred: {e}")

if __name__ == "__main__":
    script_dir = os.path.dirname(os.path.abspath(__file__))
    if os.path.exists(os.path.join(script_dir, "ffmpeg.exe")):
        print(f"ffmpeg.exe is already present in {script_dir}.")
    else:
        install_ffmpeg()
