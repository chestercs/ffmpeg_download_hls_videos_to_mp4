# Download .m3u8 to mp4.bat 🎯
**Windows-only batch tool to download HLS (`.m3u8`) streams and remux them into MP4 — with optional custom HTTP headers (Referer/Cookie) and automatic ffmpeg installation via `winget`.**

---

## ✨ Features

- **Download & remux** any HLS `.m3u8` URL (or local `.m3u8` file) to **MP4**.
- **Optional HTTP headers**:
    - Add `Referer` and/or `Cookie` via prompts.
    - Passed as separate `-headers "Key: Value"` args for reliability on Windows CMD.
- **Automatic FFmpeg install (optional)**:
    - If `ffmpeg` isn’t found, the script can install it via **`winget`** (asks first).
- **Safe Windows batch**:
    - Prompts avoid `>` to prevent stray files.
    - Robust output filename with **timestamp** fallback.
    - Basic post-run verification (file exists & size > 1KB).
- **Web-friendly MP4**: `-movflags +faststart` for progressive playback.
- **AAC-in-TS fix**: Adds `-bsf:a aac_adtstoasc` automatically for proper MP4 muxing.

---

## ⚙️ Requirements

- **Windows 10/11** (Batch script `.bat`)
- **FFmpeg** (auto-install supported via **winget**)
    - Install `App Installer` from Microsoft Store to get `winget`, if missing.

---

## 📦 Installation

1. Save the script as **`download_m3u8_to_mp4.bat`**.
2. Place it anywhere (e.g., Desktop).
3. Ensure `ffmpeg` is available in PATH, *or* allow the script to install it via **winget**.

> Tip: Keep it in a folder where you have write access (it prompts for an output directory anyway).

---

## 🚀 Usage

Run by **double-click** or via **Command Prompt**.

### 1) Enter source
- Paste the **M3U8 URL** or a **local `.m3u8` file path**.

### 2) Optional HTTP headers
- You’ll be asked whether to add custom headers:
  ```
  Add custom HTTP headers?
    1) No headers   [Default]
    2) Yes (Referer and/or Cookie)
  Select (Default: 1):
  ```
- If you choose **2**, you can enter `Referer` and/or `Cookie`. Leave blank to skip either.

> Headers are passed as separate `-headers "Key: Value"` args to FFmpeg, which is **reliable on Windows**.

### 3) Output directory & filename
- **Output directory** defaults to `C:\Users\<you>\Downloads` (you can change it).
- **Output filename** should be given **without** `.mp4`.  
  If blank, a **timestamped** name is generated, e.g. `output_20250921_162656.mp4`.

### 4) Result
The script echoes:
- **Full output path**
- Success or an error message

---

## 🧪 Examples

### Simple download
- URL: `https://example.com/path/playlist.m3u8`
- No headers, default Downloads, auto filename

**Result:** `C:\Users\<you>\Downloads\output_YYYYMMDD_HHMMSS.mp4`

### Referer + Cookie
- URL requires both:
    - Referer: `https://example.com/player`
    - Cookie:  `sessionid=abc123; other=value`

The script will call FFmpeg roughly like:
```
ffmpeg -hide_banner -y ^
  -headers "Referer: https://example.com/player" ^
  -headers "Cookie: sessionid=abc123; other=value" ^
  -i "https://example.com/path/playlist.m3u8" ^
  -c copy -bsf:a aac_adtstoasc -movflags +faststart "C:\...\output_YYYYMMDD_HHMMSS.mp4"
```

---

## 🔍 How it works

- **FFmpeg detection/installation**:
    - Uses `where ffmpeg`; if missing, offers `winget install Gyan.FFmpeg`.
- **Headers**:
    - Built as **separate** arguments to avoid issues with multi-line variables in batch.
- **Download/remux**:
    - `-c copy` (no re-encode) to keep original quality and finish quickly.
    - `-bsf:a aac_adtstoasc` handles ADTS→ASC when remuxing AAC from TS into MP4.
    - `-movflags +faststart` moves `moov` atom to the front for web playback.
- **Output verification**:
    - After FFmpeg returns, the script checks that the file exists and is >1KB.

---

## ⚠️ Notes & Limitations

- **Windows only** (batch script).
- If your URL or cookies include **exclamation marks (`!`)**, they may conflict with *Delayed Expansion* in CMD.
    - In that rare case, remove `EnableDelayedExpansion` and convert `!var!` references to percent vars carefully, **or** share a sanitized URL and adapt escaping.
- DRM-protected streams or authentication flows beyond simple headers are **not** handled by this script.
- If your input is not HLS (`.m3u8`), use the companion script **`convert_or_cut__to_mp4.bat`** for general conversion/cutting.

---

## 🧾 License (MIT)

MIT License © Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the “Software”), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
