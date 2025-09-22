@echo off
setlocal EnableExtensions

REM ============================================================
REM Logging switches
REM ============================================================
REM 1 = create logfile, 0 = no logfile
set "LOG_ENABLE=1"
REM ffmpeg loglevel: quiet|panic|fatal|error|warning|info|verbose|debug|trace
set "LOG_LEVEL=warning"

REM TLS verification: 1 = verify (default), 0 = skip verify (debug)
set "TLS_VERIFY=1"

REM internal flag to balance pushd/popd
set "DID_PUSHD=0"

REM detect PowerShell (for long inputs and passing long headers safely)
set "PWSH_EXE="
for %%P in (powershell.exe) do if not defined PWSH_EXE set "PWSH_EXE=%%~$PATH:P"

REM temp files for long headers (only created when non-empty input is provided)
set "AUTH_FILE="
set "COOKIE_FILE="

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
if defined PWSH_EXE (
  for /f "usebackq delims=" %%I in (`
    powershell -NoProfile -Command "Read-Host -Prompt 'Enter FULL master/playlist URL (.m3u8 or .mpd)'"
  `) do set "SRC=%%~I"
) else (
  set /p "SRC=Enter FULL master/playlist URL (.m3u8 or .mpd): "
)
if "%SRC%"=="" (
  echo [!] URL cannot be empty.
  echo(
  pause
  exit /b 1
)

REM if there's only a trailing "?", strip it
if "%SRC:~-1%"=="?" set "SRC=%SRC:~0,-1%"

REM ======================================
REM 2) Optional HTTP headers (no practical length limits via PowerShell)
REM ======================================
echo(
echo Add custom HTTP headers?
echo   1) No headers   [Default]
echo   2) Yes (Referer / Cookie / Origin / Authorization)
set /p "HDRSEL=Select (Default: 1): "
set "REF=" & set "COO=" & set "ORG=" & set "AUTH="

if "%HDRSEL%"=="2" (
  echo(
  REM Referer (short)
  if defined PWSH_EXE (
    for /f "usebackq delims=" %%I in (`
      powershell -NoProfile -Command "Read-Host -Prompt 'Referer (optional)'"
    `) do set "REF=%%~I"
  ) else (
    set /p "REF=Referer (optional): "
  )

  REM Cookie (can be very long) -> only create temp file if non-empty
  if defined PWSH_EXE (
    for /f "usebackq delims=" %%I in (`
      powershell -NoProfile -Command ^
        "$v=Read-Host -Prompt 'Cookie  (optional, paste full string)'; if([string]::IsNullOrWhiteSpace($v)){''} else { $p=[IO.Path]::GetTempFileName(); [IO.File]::WriteAllText($p,$v,[Text.Encoding]::UTF8); $p }"
    `) do set "COOKIE_FILE=%%~I"
  ) else (
    set /p "COO=Cookie  (optional): "
  )

  REM Origin (short)
  if defined PWSH_EXE (
    for /f "usebackq delims=" %%I in (`
      powershell -NoProfile -Command "Read-Host -Prompt 'Origin  (optional)'"
    `) do set "ORG=%%~I"
  ) else (
    set /p "ORG=Origin  (optional): "
  )

  REM Authorization (can be very long) -> only create temp file if non-empty
  if defined PWSH_EXE (
    for /f "usebackq delims=" %%I in (`
      powershell -NoProfile -Command ^
        "$v=Read-Host -Prompt 'Authorization (optional, e.g. Bearer <token>)'; if([string]::IsNullOrWhiteSpace($v)){''} else { $p=[IO.Path]::GetTempFileName(); [IO.File]::WriteAllText($p,$v,[Text.Encoding]::UTF8); $p }"
    `) do set "AUTH_FILE=%%~I"
  ) else (
    set /p "AUTH=Authorization (optional, e.g. Bearer <token>): "
  )
)

REM ======================================
REM 3) Output folder + filename (timestamp)
REM ======================================
set "DEFAULT_OUT=%USERPROFILE%\Downloads"
echo(
if defined PWSH_EXE (
  for /f "usebackq delims=" %%I in (`
    powershell -NoProfile -Command "Read-Host -Prompt 'Output directory (Default: %DEFAULT_OUT%)'"
  `) do set "OUTDIR=%%~I"
) else (
  set /p "OUTDIR=Output directory (Default: %DEFAULT_OUT%): "
)
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
if defined PWSH_EXE (
  for /f "usebackq delims=" %%I in (`
    powershell -NoProfile -Command "Read-Host -Prompt 'Output filename (no .mp4, Default: %DEFNAME%)'"
  `) do set "BASENAME=%%~I"
) else (
  set /p "BASENAME=Output filename (no .mp4, Default: %DEFNAME%): "
)
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
REM 4) Master/manifest detection + variant picker (with curl or PowerShell)
REM ======================================
set "USE_URL=%SRC%"

set "IS_MASTER=0"
if not "%SRC:master.m3u8=%"=="%SRC%" set "IS_MASTER=1"
if "%IS_MASTER%"=="0" if not "%SRC:manifest.m3u8=%"=="%SRC%" set "IS_MASTER=1"

set "CURL_EXE="
for %%P in (curl.exe) do if not defined CURL_EXE set "CURL_EXE=%%~$PATH:P"

if "%IS_MASTER%"=="1" (
  set "TMPM3U8=%TEMP%\m3u8_%RANDOM%.txt"

  if defined PWSH_EXE (
    powershell -NoProfile -Command ^
      "$h=@{};" ^
      "if('%REF%' -ne ''){$h['Referer']='%REF%'};" ^
      "if('%ORG%' -ne ''){$h['Origin']='%ORG%'};" ^
      "if('%COOKIE_FILE%' -ne ''){ if(Test-Path '%COOKIE_FILE%'){ $c=Get-Content -LiteralPath '%COOKIE_FILE%' -Raw; if($c){ $c=$c -replace '^\uFEFF',''; $h['Cookie']=$c.Trim() } } } else { if('%COO%' -ne ''){$h['Cookie']='%COO%' } };" ^
      "if('%AUTH_FILE%'   -ne ''){ if(Test-Path '%AUTH_FILE%'){ $a=Get-Content -LiteralPath '%AUTH_FILE%'   -Raw; if($a){ $a=$a -replace '^\uFEFF',''; $h['Authorization']=$a.Trim() } } } else { if('%AUTH%' -ne ''){$h['Authorization']='%AUTH%' } };" ^
      "Invoke-WebRequest -Uri '%SRC%' -Headers $h -MaximumRedirection 5 -UseBasicParsing -OutFile '%TMPM3U8%' | Out-Null" ^
      "" >nul 2>&1
  ) else if defined CURL_EXE (
    set "CURLH1=" & set "CURLH2=" & set "CURLH3=" & set "CURLH4="
    if not "%REF%"=="" set "CURLH1=-H Referer: %REF%"
    if not "%COO%"=="" set "CURLH2=-H Cookie: %COO%"
    if not "%ORG%"=="" set "CURLH3=-H Origin: %ORG%"
    if not "%AUTH%"=="" set "CURLH4=-H Authorization: %AUTH%"
    >nul 2>&1 "%CURL_EXE%" -s -L --retry 3 --max-time 25 ^
      -H "Accept: */*" -H "Accept-Encoding: identity" %CURLH1% %CURLH2% %CURLH3% %CURLH4% ^
      "%SRC%" > "%TMPM3U8%"
  )

  if exist "%TMPM3U8%" (
    call :PARSE_VARIANTS "%SRC%" "%TMPM3U8%"
    if defined VAR_CHOSEN_URL set "USE_URL=%VAR_CHOSEN_URL%"
    del /q "%TMPM3U8%" >nul 2>&1
    if exist "%TEMP%\m3u8_variants_%PID%.lst" del /q "%TEMP%\m3u8_variants_%PID%.lst" >nul 2>&1
  )
)

REM ======================================
REM 5) Log settings
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
REM 6) FFmpeg call (via PowerShell when available to avoid cmd limits)
REM ======================================
set "UA_STR=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"

echo(
echo Source:  "%USE_URL%"
echo Output:  "%OUTFILE%"
if "%LOG_ENABLE%"=="1" echo Logfile: "%SCRIPT_DIR%logs\%LOGFILENAME%"
echo(

if defined PWSH_EXE (
  powershell -NoProfile -Command ^
    "$ff   = '%FFMPEG_EXE%';" ^
    "$src  = '%USE_URL%';" ^
    "$out  = '%OUTFILE%';" ^
    "$ua   = '%UA_STR%';" ^
    "$args = @('-hide_banner','-y','-stats','-stats_period','0.5','-loglevel','%LOG_LEVEL%');" ^
    "if ('%LOG_ENABLE%' -eq '1') { $args += '-report' }" ^
    "$args += @('-icy','0','-user_agent',$ua);" ^
    "$hdrPairs = @();" ^
    "$hdrPairs += @('-headers','Accept: */*');" ^
    "$hdrPairs += @('-headers','Accept-Language: en-GB,en;q=0.9');" ^
    "$hdrPairs += @('-headers','Accept-Encoding: identity');" ^
    "if('%REF%' -ne ''){  $hdrPairs += @('-headers',('Referer: ' + '%REF%')) }" ^
    "if('%ORG%' -ne ''){  $hdrPairs += @('-headers',('Origin: '  + '%ORG%')) }" ^
    "if('%COO%' -ne ''){  $hdrPairs += @('-headers',('Cookie: '  + '%COO%')) }" ^
    "if('%AUTH%' -ne ''){ $hdrPairs += @('-headers',('Authorization: ' + '%AUTH%')) }" ^
    "if('%COOKIE_FILE%' -ne ''){ if(Test-Path '%COOKIE_FILE%'){ $c=[IO.File]::ReadAllText('%COOKIE_FILE%'); if($c){ $c=$c -replace '^\uFEFF',''; $hdrPairs += @('-headers',('Cookie: ' + $c.Trim())) } } }" ^
    "if('%AUTH_FILE%'   -ne ''){ if(Test-Path '%AUTH_FILE%'){ $a=[IO.File]::ReadAllText('%AUTH_FILE%'); if($a){ $a=$a -replace '^\uFEFF',''; $hdrPairs += @('-headers',('Authorization: ' + $a.Trim())) } } }" ^
    "$args += $hdrPairs;" ^
    "$u = [Uri]$src; $dnsHost = $u.DnsSafeHost;" ^
    "if ('%TLS_VERIFY%' -eq '0') { $args += @('-tls_verify','0','-tls_hostname',$dnsHost) }" ^
    "$args += @('-protocol_whitelist','file,http,https,tcp,tls,crypto','-allowed_extensions','ALL','-multiple_requests','1','-reconnect','1','-reconnect_on_network_error','1','-rw_timeout','30000000');" ^
    "$args += @('-i',$src,'-c','copy','-bsf:a','aac_adtstoasc','-movflags','+faststart',$out);" ^
    "& $ff @args"
) else (
  REM Fallback: classic cmd path (limited by cmd line length)
  set "H1=" & set "H2=" & set "H3=" & set "H4="
  if not "%REF%"==""  set "H1=-headers "Referer: %REF%""
  if not "%COO%"==""  set "H2=-headers "Cookie: %COO%""
  if not "%ORG%"==""  set "H3=-headers "Origin: %ORG%""
  if not "%AUTH%"=="" set "H4=-headers "Authorization: %AUTH%""

  if "%LOG_ENABLE%"=="1" (
    set "PRE=-hide_banner -y -stats -stats_period 0.5 -loglevel %LOG_LEVEL% -report"
  ) else (
    set "PRE=-hide_banner -y -stats -stats_period 0.5 -loglevel %LOG_LEVEL%"
  )

  "%FFMPEG_EXE%" %PRE% ^
    %H1% %H2% %H3% %H4% ^
    -icy 0 -user_agent "%UA_STR%" ^
    -headers "Accept: */*" ^
    -headers "Accept-Language: en-GB,en;q=0.9" ^
    -headers "Accept-Encoding: identity" ^
    -protocol_whitelist file,http,https,tcp,tls,crypto -allowed_extensions ALL -multiple_requests 1 -reconnect 1 -reconnect_on_network_error 1 -rw_timeout 30000000 ^
    -i "%USE_URL%" -c copy -bsf:a aac_adtstoasc -movflags +faststart "%OUTFILE%"
)

set "rc=%errorlevel%"

REM clean up temp header files (best-effort)
if defined AUTH_FILE if exist "%AUTH_FILE%" del /q "%AUTH_FILE%" >nul 2>&1
if defined COOKIE_FILE if exist "%COOKIE_FILE%" del /q "%COOKIE_FILE%" >nul 2>&1

REM only popd, if we did pushd
if "%DID_PUSHD%"=="1" popd >nul

REM output file check
if not exist "%OUTFILE%" set "rc=1"
if exist "%OUTFILE%" for %%Z in ("%OUTFILE%") do if %%~zZ LSS 1024 set "rc=1"

REM ============================================================
REM Using goto branches instead of inline if..else to avoid errors
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
echo     - If the master/manifest URL ended with only a '?', the script trimmed it.
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
