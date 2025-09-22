@echo off
setlocal EnableExtensions

REM ============================================================
REM Logging switches
REM ============================================================
REM 1 = create logfile, 0 = no logfile
set "LOG_ENABLE=1"
REM ffmpeg loglevel: quiet|panic|fatal|error|warning|info|verbose|debug|trace
set "LOG_LEVEL=warning"

REM internal flag to balance pushd/popd
set "DID_PUSHD=0"

REM ============================================================
REM 0) Find ffmpeg + optional winget install (Default: Y)
REM ============================================================
set "FFMPEG_EXE="
call :FIND_FFMPEG
if defined FFMPEG_EXE goto FF_OK

echo(
echo [!] ffmpeg was not found on this system.
set "ans=Y"
set /p "ans=Install via winget? [Y/N] (Default: Y): "
if /I "%ans%"=="N" (
  echo(
  echo Aborted.
  echo(
  pause
  exit /b 1
)

where winget >nul 2>&1
if errorlevel 1 (
  echo(
  echo [!] winget is not available. Please install "App Installer" from Microsoft Store, then re-run.
  echo(
  pause
  exit /b 1
)

echo(
echo Installing ffmpeg with winget...
winget install --id Gyan.FFmpeg -e --source winget
if errorlevel 1 (
  echo(
  echo [!] Installation failed.
  echo(
  pause
  exit /b 1
)

set "FFMPEG_EXE="
call :FIND_FFMPEG
if not defined FFMPEG_EXE (
  echo(
  echo [!] ffmpeg installed, but PATH may not have refreshed in this session.
  echo     Close this terminal and run the script again.
  echo(
  pause
  exit /b 1
)

:FF_OK
echo Using ffmpeg: "%FFMPEG_EXE%"

REM ======================================
REM 1) Input URL
REM ======================================
echo(
set /p "SRC=Enter FULL master/playlist URL: "
if "%SRC%"=="" (
  echo [!] URL cannot be empty.
  echo(
  pause
  exit /b 1
)

REM if there's only a trailing "?", strip it
if "%SRC:~-1%"=="?" set "SRC=%SRC:~0,-1%"

REM ======================================
REM 2) Optional HTTP headers
REM ======================================
echo(
echo Add custom HTTP headers?
echo   1) No headers   [Default]
echo   2) Yes (Referer / Cookie / Origin / Authorization)
set /p "HDRSEL=Select (Default: 1): "
set "H1=" & set "H2=" & set "H3=" & set "H4="

if "%HDRSEL%"=="2" (
  echo(
  REM Referer
  if defined REF (
    REM keep existing REF if set from outside
  ) else (
    set /p "REF=Referer (optional): "
  )
  REM Cookie
  if defined COO (
    REM keep existing COO if set from outside
  ) else (
    set /p "COO=Cookie  (optional): "
  )
  REM Origin
  if defined ORG (
    REM keep existing ORG if set from outside
  ) else (
    set /p "ORG=Origin  (optional): "
  )
  REM Authorization: prefer environment variable if already present
  if defined AUTH (
    echo Detected AUTH from environment. It will be used for Authorization header.
  ) else (
    set /p "AUTH=Authorization (optional, e.g. Bearer <token>): "
  )

  if defined REF  set H1=-headers "Referer: %REF%"
  if defined COO  set H2=-headers "Cookie: %COO%"
  if defined ORG  set H3=-headers "Origin: %ORG%"
  if defined AUTH set H4=-headers "Authorization: %AUTH%"
)

REM ======================================
REM 3) Output folder + filename (timestamp)
REM ======================================
set "DEFAULT_OUT=%USERPROFILE%\Downloads"
echo(
set /p "OUTDIR=Output directory (Default: %DEFAULT_OUT%): "
if "%OUTDIR%"=="" set "OUTDIR=%DEFAULT_OUT%"
for %%A in ("%OUTDIR%") do set "OUTDIR=%%~A"
if not exist "%OUTDIR%" (
  echo Creating directory: %OUTDIR%
  mkdir "%OUTDIR%" >nul 2>&1
  if errorlevel 1 (
    echo [!] Failed to create output directory.
    echo(
    pause
    exit /b 1
  )
)

call :GEN_TS
set "DEFNAME=output_%ts%"
echo(
set /p "BASENAME=Output filename (no .mp4, Default: %DEFNAME%): "
for %%A in ("%BASENAME%") do set "BASENAME=%%~A"
if "%BASENAME%"=="" set "BASENAME=%DEFNAME%"
if /i "%BASENAME:~-4%"==".mp4" set "BASENAME=%BASENAME:~0,-4%"
:TRIMDOT
if "%BASENAME%"=="" goto NAMEDONE
if "%BASENAME:~-1%"=="." (
  set "BASENAME=%BASENAME:~0,-1%"
  goto TRIMDOT
)
:NAMEDONE
set "OUTFILE=%OUTDIR%\%BASENAME%.mp4"

REM ======================================
REM 4) Master/manifest detection + variant picker (with curl)
REM ======================================
set "USE_URL=%SRC%"

set "IS_MASTER=0"
if not "%SRC:master.m3u8=%"=="%SRC%" set "IS_MASTER=1"
if "%IS_MASTER%"=="0" if not "%SRC:manifest.m3u8=%"=="%SRC%" set "IS_MASTER=1"

set "CURL_EXE="
for %%P in (curl.exe) do if not defined CURL_EXE set "CURL_EXE=%%~$PATH:P"

if "%IS_MASTER%"=="1" if defined CURL_EXE (
  set "TMPM3U8=%TEMP%\m3u8_%RANDOM%.txt"
  set "CURLH1=" & set "CURLH2=" & set "CURLH3=" & set "CURLH4="
  if defined REF  set "CURLH1=-H Referer: %REF%"
  if defined COO  set "CURLH2=-H Cookie: %COO%"
  if defined ORG  set "CURLH3=-H Origin: %ORG%"
  if defined AUTH set "CURLH4=-H Authorization: %AUTH%"

  >nul 2>&1 "%CURL_EXE%" -s -L --retry 3 --max-time 25 ^
    -H "Accept: */*" -H "Accept-Encoding: identity" %CURLH1% %CURLH2% %CURLH3% %CURLH4% ^
    "%SRC%" > "%TMPM3U8%"

  if exist "%TMPM3U8%" (
    call :PARSE_VARIANTS "%SRC%" "%TMPM3U8%"
    if defined VAR_CHOSEN_URL set "USE_URL=%VAR_CHOSEN_URL%"
    del /q "%TMPM3U8%" >nul 2>&1
    if exist "%TEMP%\m3u8_variants_%PID%.lst" del /q "%TEMP%\m3u8_variants_%PID%.lst" >nul 2>&1
  )
)

REM ======================================
REM 5) Log settings: file and console use the SAME LOG_LEVEL
REM Note: -report does NOT include -stats lines; kept as-is to preserve your behavior.
REM ======================================
set "SCRIPT_DIR=%~dp0"
set "LOGFILENAME=ffmpeg_%BASENAME%.log"
set "LOGFILE_FULL=%SCRIPT_DIR%logs\%LOGFILENAME%"

if "%LOG_ENABLE%"=="1" (
  if not exist "%SCRIPT_DIR%logs" mkdir "%SCRIPT_DIR%logs" >nul 2>&1
  pushd "%SCRIPT_DIR%logs" >nul
  set "DID_PUSHD=1"
)

REM ======================================
REM 6) FFmpeg call (stable HLS/HTTPS flags)
REM ======================================
set "UA_STR=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"

if "%LOG_ENABLE%"=="1" (
  set "PRE=-hide_banner -y -stats -stats_period 0.5 -loglevel %LOG_LEVEL% -report"
) else (
  set "PRE=-hide_banner -y -stats -stats_period 0.5 -loglevel %LOG_LEVEL%"
)

set "HLS=-protocol_whitelist file,http,https,tcp,tls,crypto -allowed_extensions ALL -http_seekable 0 -multiple_requests 1 -http_persistent 0 -reconnect 1 -reconnect_on_network_error 1 -rw_timeout 30000000 -max_reload 2000"

echo(
echo Source:  "%USE_URL%"
echo Output:  "%OUTFILE%"
if "%LOG_ENABLE%"=="1" echo Logfile: "%SCRIPT_DIR%logs\%LOGFILENAME%"
echo(

"%FFMPEG_EXE%" %PRE% -icy 0 -user_agent "%UA_STR%" ^
  -headers "Accept: */*" ^
  -headers "Accept-Language: en-GB,en;q=0.9" ^
  -headers "Accept-Encoding: identity" ^
  %H1% %H2% %H3% %H4% %HLS% -i "%USE_URL%" -c copy -bsf:a aac_adtstoasc -movflags +faststart "%OUTFILE%"

set "rc=%errorlevel%"

REM only popd if we actually did pushd
if "%DID_PUSHD%"=="1" popd >nul

REM output file check
if not exist "%OUTFILE%" set "rc=1"
if exist "%OUTFILE%" for %%Z in ("%OUTFILE%") do if %%~zZ LSS 1024 set "rc=1"

REM ============================================================
REM Using goto branches instead of inline if..else to avoid '. was unexpected...' errors
REM ============================================================
if "%rc%"=="0" goto DL_OK
goto DL_FAIL

:DL_OK
echo(
echo [OK] Done.
echo Full path: %OUTFILE%
if "%LOG_ENABLE%"=="1" echo Logfile:   %LOGFILE_FULL%
echo(
pause
exit /b 0

:DL_FAIL
echo(
echo [!] Error: download/remux failed.
echo     - Provide Referer/Cookie/Origin/Authorization headers if the CDN requires them (option 2).
echo     - If the master URL ended with only a '?', the script trimmed it.
if "%LOG_ENABLE%"=="1" echo     - Log: %LOGFILE_FULL%
echo(
pause
exit /b 1

REM ============================================================
REM Helper: FIND_FFMPEG -> sets FFMPEG_EXE if found
REM ============================================================
:FIND_FFMPEG
set "FFMPEG_EXE="

REM 1) PATH
for %%P in (ffmpeg.exe) do (
  if not defined FFMPEG_EXE set "FFMPEG_EXE=%%~$PATH:P"
)

REM 2) WinGet Links
if not defined FFMPEG_EXE if exist "%LOCALAPPDATA%\Microsoft\WinGet\Links\ffmpeg.exe" (
  set "FFMPEG_EXE=%LOCALAPPDATA%\Microsoft\WinGet\Links\ffmpeg.exe"
)

REM 3) WinGet Packages (recursive)
if not defined FFMPEG_EXE if exist "%LOCALAPPDATA%\Microsoft\WinGet\Packages" (
  for /f "delims=" %%F in ('where /r "%LOCALAPPDATA%\Microsoft\WinGet\Packages" ffmpeg.exe 2^>nul') do (
    if exist "%%~fF" (
      set "FFMPEG_EXE=%%~fF"
      goto :FIND_DONE
    )
  )
)

REM 4) Program Files
if not defined FFMPEG_EXE if exist "%ProgramFiles%\ffmpeg\bin\ffmpeg.exe" (
  set "FFMPEG_EXE=%ProgramFiles%\ffmpeg\bin\ffmpeg.exe"
)

:FIND_DONE
exit /b 0

REM ============================================================
REM Helper: GEN_TS -> %ts% = yyyyMMdd_HHmmss
REM ============================================================
:GEN_TS
set "ts="
for /f "tokens=1-3 delims=/.- " %%a in ("%date%") do (
  for /f "tokens=1-3 delims=:." %%x in ("%time%") do (
    set "ts=%%c%%a%%b_%%x%%y%%z"
  )
)
if "%ts%"=="" set "ts=%RANDOM%"
exit /b 0

REM ============================================================
REM Helper: PARSE_VARIANTS (when master is used)
REM ============================================================
:PARSE_VARIANTS
set "VAR_CHOSEN_URL="
set "SRCMASTER=%~1"
set "FILE=%~2"
set "PID=%RANDOM%"

set "BASE=%SRCMASTER%"
call :STRIP_AFTER_LAST_SLASH BASE

set "LIST=%TEMP%\m3u8_variants_%PID%.lst"
if exist "%LIST%" del /q "%LIST%" >nul 2>&1

setlocal EnableDelayedExpansion
set "grab=0"
set /a idx=0
for /f "usebackq delims=" %%L in ("%FILE%") do (
  set "line=%%L"
  if "!line:~0,18!"=="#EXT-X-STREAM-INF" (
    set "meta=%%L"
    set "grab=1"
  ) else (
    if "!grab!"=="1" (
      set "url=%%L"
      set "grab=0"
      set /a idx+=1

      set "res="
      for /f "tokens=2 delims==," %%r in ('echo !meta!^|findstr /R /C:"RESOLUTION=.*"') do set "res=%%r"
      set "bw="
      for /f "tokens=2 delims==," %%b in ('echo !meta!^|findstr /R /C:"BANDWIDTH=.*"') do set "bw=%%b"

      >>"%LIST%" echo !idx!^^|^^|^^|!res!^^|^^|^^|!bw!^^|^^|^^|!url!
    )
  )
)
endlocal

if not exist "%LIST%" exit /b 0

echo(
echo [Variants found in master]
for /f "usebackq tokens=1-4 delims=|" %%A in ("%LIST%") do (
  set "i=%%A" & set "r=%%B" & set "b=%%C" & set "u=%%D"
  call echo   %%A^) %%B  BW=%%C  --^> %%D
)

echo(
set /p "CH=Choose variant number (Enter=auto by ffmpeg): "
if "%CH%"=="" exit /b 0

set "SEL="
for /f "usebackq tokens=1-4 delims=|" %%A in ("%LIST%") do (
  if "%%A"=="%CH%" set "SEL=%%D"
)
if "%SEL%"=="" exit /b 0

set "HEAD8=%SEL:~0,8%"
set "HEAD7=%SEL:~0,7%"
if /i "%HEAD8%"=="https://" (
  endlocal & set "VAR_CHOSEN_URL=%SEL%" & exit /b 0
) else if /i "%HEAD7%"=="http://" (
  endlocal & set "VAR_CHOSEN_URL=%SEL%" & exit /b 0
) else (
  endlocal & set "VAR_CHOSEN_URL=%BASE%%SEL%" & exit /b 0
)

REM ============================================================
REM Helper: STRIP_AFTER_LAST_SLASH varname
REM ============================================================
:STRIP_AFTER_LAST_SLASH
setlocal EnableDelayedExpansion
set "s=!%~1!"
set "p=0"
for /L %%N in (0,1,4096) do (
  set "c=!s:~%%N,1!"
  if "!c!"=="" goto donepos
  if "!c!"=="/" set "p=%%N"
)
:donepos
set /a p=p+1
set "baseurl=!s:~0,%p%!"
endlocal & set "%~1=%baseurl%"
exit /b 0
