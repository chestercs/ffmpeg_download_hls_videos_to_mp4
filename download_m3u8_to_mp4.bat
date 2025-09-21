@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM =========================
REM 0) Check ffmpeg / optional winget install
REM =========================
where ffmpeg >nul 2>&1
if errorlevel 1 goto NOFFMPEG
goto FFOK

:NOFFMPEG
echo.
echo [!] ffmpeg was not found on this system.
set /p "ans=Install via winget? (Y/N, Default: N): "
if /i "%ans%"=="Y" goto INSTALL_FFMPEG
echo Aborted.
goto END

:INSTALL_FFMPEG
where winget >nul 2>&1
if errorlevel 1 (
  echo.
  echo [!] winget is not available. Please install "App Installer" from Microsoft Store.
  goto END
)
echo.
echo Installing ffmpeg with winget...
winget install --id Gyan.FFmpeg -e --source winget
if errorlevel 1 (
  echo.
  echo [!] Installation failed.
  goto END
)
where ffmpeg >nul 2>&1
if errorlevel 1 (
  echo.
  echo [!] ffmpeg installed, but PATH did not refresh in this window. Close and rerun.
  goto END
)

:FFOK

REM =========================
REM 1) Ask for M3U8 URL (or local .m3u8 path)
REM =========================
echo.
set /p "m3u8_url=Enter the M3U8 URL or local .m3u8 path: "
if "%m3u8_url%"=="" (
  echo [!] URL/path cannot be empty.
  goto END
)

REM =========================
REM 2) Optional HTTP headers (Referer, Cookie)
REM =========================
echo.
echo Add custom HTTP headers?
echo   1) No headers   [Default]
echo   2) Yes (Referer and/or Cookie)
set /p "hdr_sel=Select (Default: 1): "
if "%hdr_sel%"=="2" ( set "use_headers=1" ) else ( set "use_headers=0" )

set "H1="
set "H2="
if "%use_headers%"=="1" (
  echo.
  set /p "referer=Referer (optional, leave blank to skip): "
  set /p "cookie=Cookie  (optional, leave blank to skip): "
  if defined referer set H1=-headers "Referer: %referer%"
  if defined cookie  set H2=-headers "Cookie: %cookie%"
)

REM =========================
REM 3) Output directory (default: Downloads)
REM =========================
set "default_outdir=%USERPROFILE%\Downloads"
echo.
set /p "outdir=Output directory (Default: %default_outdir%): "
if "%outdir%"=="" set "outdir=%default_outdir%"
for %%A in ("%outdir%") do set "outdir=%%~A"
if not exist "%outdir%" (
  echo Creating directory: %outdir%
  mkdir "%outdir%" >nul 2>&1
  if errorlevel 1 (
    echo [!] Failed to create output directory.
    goto END
  )
)

REM =========================
REM 4) Output filename (without .mp4) + robust timestamp
REM =========================
echo.
echo Example filename: output_01   (do NOT type .mp4)
set /p "basename=Output filename (Default: auto timestamp): "
for %%A in ("%basename%") do set "basename=%%~A"

if "%basename%"=="" (
  for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "ts=%%I"
  if "!ts!"=="" (
    for /f "tokens=2 delims==." %%I in ('wmic os get localdatetime /value 2^>nul') do set "rawts=%%I"
    if defined rawts (
      set "ts=!rawts:~0,8!_!rawts:~8,6!"
    ) else (
      set "ts=%DATE: =0%_%TIME: =0%"
      set "ts=!ts::=!"
      set "ts=!ts:/=!"
      set "ts=!ts:.=!"
      for /f "tokens=1,2 delims=_" %%a in ("!ts!") do set "ts=%%a_%%b"
      set "ts=!ts:~0,15!"
    )
  )
  set "basename=output_!ts!"
)

if /i "%basename:~-4%"==".mp4" set "basename=%basename:~0,-4%"
if "%basename:~-1%"=="." set "basename=%basename:~0,-1%"

set "outfile=%outdir%\%basename%.mp4"

REM =========================
REM 5) Download / remux to MP4 (no escaping; just quote)
REM =========================
echo.
echo Source:  %m3u8_url%
echo Output:  %outfile%

REM Optional: show the exact command (debug)
REM echo ffmpeg -hide_banner -y %H1% %H2% -i "%m3u8_url%" -c copy -bsf:a aac_adtstoasc -movflags +faststart "%outfile%"

ffmpeg -hide_banner -y %H1% %H2% -i "%m3u8_url%" -c copy -bsf:a aac_adtstoasc -movflags +faststart "%outfile%"
set "rc=%errorlevel%"

REM Verify output (existence + minimal size)
if not exist "%outfile%" set "rc=1"
if exist "%outfile%" for %%Z in ("%outfile%") do if %%~zZ LSS 1024 set "rc=1"

if not "%rc%"=="0" goto FAIL
goto SUCCESS

:SUCCESS
echo.
echo [OK] Done.
echo Full path: %outfile%
goto END

:FAIL
echo.
echo [!] Error: download/remux failed.
echo Tip: If the URL contains exclamation marks (!), they can conflict with delayed expansion.
echo      In that rare case, remove "EnableDelayedExpansion" near the top and switch !vars! to %%vars%% carefully,
echo      or share a sanitized sample URL and I’ll tailor the escaping precisely.
goto END

:END
echo.
pause
