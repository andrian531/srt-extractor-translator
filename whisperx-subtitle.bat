@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul 2>&1

:: ============================================================
::  WHISPERX SUBTITLE EXTRACTOR
::  Place this .bat in your video folder and double-click
:: ============================================================

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "MODEL=medium"
set "LANGUAGE="
set "OUTPUT_FORMAT=srt"
set "WHISPER_DEVICE=cuda"
set "AUTO_TRANSLATE=false"

:: ============================================================
:: QUICK DEPENDENCY CHECK
:: ============================================================
if not exist "%SCRIPT_DIR%\.installed" (
    echo  [ERROR] Dependencies not installed.
    echo  Please run install.bat first.
    echo.
    pause
    exit /b 1
)
where whisperx >nul 2>&1
if errorlevel 1 (
    echo  [ERROR] WhisperX not found. Please run install.bat to install it.
    echo.
    pause
    exit /b 1
)
python --version >nul 2>&1
if errorlevel 1 (
    echo  [ERROR] Python not found. Please run install.bat to reinstall.
    echo.
    pause
    exit /b 1
)

:: ============================================================
:: GPU CHECK
:: ============================================================
set "CUDA_OK=false"
set "GPU_NAME="
set "VRAM="
for /f "tokens=*" %%L in ('python "%~dp0check_gpu.py" verify 2^>nul') do (
    set "%%L"
)
if not "!CUDA_OK!"=="true" set "WHISPER_DEVICE=cpu"

:: ============================================================
:: ENGINE DETECTION (Claude / Gemini for translation)
:: ============================================================
set "CLAUDE_CMD="
set "GEMINI_CMD="

for %%c in (claude claude-code claudecode) do (
    if "!CLAUDE_CMD!"=="" (
        where %%c >nul 2>&1
        if not errorlevel 1 set "CLAUDE_CMD=%%c"
    )
)
if "!CLAUDE_CMD!"=="" (
    for %%p in (
        "%APPDATA%\npm\claude.cmd"
        "%APPDATA%\npm\claude"
        "%LOCALAPPDATA%\npm\claude.cmd"
        "%LOCALAPPDATA%\npm\claude"
        "%ProgramFiles%\nodejs\claude.cmd"
    ) do (
        if "!CLAUDE_CMD!"=="" (
            if exist %%p set "CLAUDE_CMD=%%~p"
        )
    )
)
for %%c in (gemini gemini-cli) do (
    if "!GEMINI_CMD!"=="" (
        where %%c >nul 2>&1
        if not errorlevel 1 set "GEMINI_CMD=%%c"
    )
)
if "!GEMINI_CMD!"=="" (
    for %%p in (
        "%APPDATA%\npm\gemini.cmd"
        "%APPDATA%\npm\gemini"
        "%LOCALAPPDATA%\npm\gemini.cmd"
        "%LOCALAPPDATA%\npm\gemini"
    ) do (
        if "!GEMINI_CMD!"=="" (
            if exist %%p set "GEMINI_CMD=%%~p"
        )
    )
)

:: ============================================================
:: MAIN MENU
:: ============================================================
cls
echo ============================================================
echo   WHISPERX SUBTITLE EXTRACTOR
echo   Folder: %SCRIPT_DIR%
if "!CUDA_OK!"=="true" (
    echo   GPU   : !GPU_NAME! ^(!VRAM!^)
) else (
    echo   GPU   : CPU mode
)
echo ============================================================
echo.
echo   [1] Generate Subtitle    - extract subtitles from video files
echo   [2] Translate Subtitle   - translate .srt files to another language
echo   [3] Generate + Translate - extract then auto-translate (set ^& forget)
echo.
set /p MAIN_MENU="Choose [1-3]: "

if "!MAIN_MENU!"=="2" goto MENU_TRANSLATE
if "!MAIN_MENU!"=="3" goto MENU_GENERATE_TRANSLATE
goto MENU_GENERATE

:: ============================================================
:: MENU: TRANSLATE SUBTITLE
:: ============================================================
:MENU_TRANSLATE
cls
echo ============================================================
echo   TRANSLATE SUBTITLE
echo   Folder: %SCRIPT_DIR%
echo ============================================================
echo.

if "!CLAUDE_CMD!"=="" if "!GEMINI_CMD!"=="" (
    echo  [ERROR] No translation engine found.
    echo  Install Claude : npm install -g @anthropic-ai/claude-code
    echo  Install Gemini : npm install -g @google/gemini-cli
    echo  Then re-run install.bat to verify.
    pause
    exit /b 1
)
if not "!CLAUDE_CMD!"=="" echo  [OK] Claude : !CLAUDE_CMD!
if not "!GEMINI_CMD!"=="" echo  [OK] Gemini : !GEMINI_CMD!
echo.

echo  Scanning for subtitle files (.srt) in: %SCRIPT_DIR%
echo ============================================================
echo.

set "SIDX=0"
for /r "%SCRIPT_DIR%" %%f in (*.srt) do (
    echo %%~nf | findstr /ri "_EN$\|_ID$\|_JA$\|_KO$\|_ZH$\|_TRANSLATED$" >nul
    if errorlevel 1 (
        set /a SIDX+=1
        set "SFILE_!SIDX!=%%f"
        set "SREL=%%f"
        set "SREL=!SREL:%SCRIPT_DIR%\=!"
        echo  [!SIDX!] !SREL!
    )
)

if !SIDX!==0 (
    echo  No .srt files found.
    pause
    exit /b 0
)

echo.
echo  Found: !SIDX! subtitle file(s)
echo.

:CHOOSE_SRT
set "SCHOICE="
set /p SCHOICE="Enter file number (1-!SIDX!) or 'all': "

if /i "!SCHOICE!"=="all" goto TRANSLATE_ALL_FILES
if "!SCHOICE!"=="" goto CHOOSE_SRT
set /a STEST=!SCHOICE! 2>nul
if !STEST! LSS 1 goto INVALID_SRT
if !STEST! GTR !SIDX! goto INVALID_SRT

set "DETECT_FILE=!SFILE_%SCHOICE%!"
call :DETECT_SRT_LANG
call :CHOOSE_TARGET_LANG
echo.
call :RUN_TRANSLATE "!SFILE_%SCHOICE%!"
goto TRANSLATE_DONE

:INVALID_SRT
echo  [!] Invalid input
goto CHOOSE_SRT

:TRANSLATE_ALL_FILES
set "DETECT_FILE=!SFILE_1!"
call :DETECT_SRT_LANG
call :CHOOSE_TARGET_LANG
echo.
for /l %%i in (1,1,!SIDX!) do (
    echo  [%%i/!SIDX!] Translating: !SFILE_%%i!
    call :RUN_TRANSLATE "!SFILE_%%i!"
)

:TRANSLATE_DONE
echo.
echo ============================================================
echo   Translation complete!
echo ============================================================
echo.
pause
exit /b 0

:: ============================================================
:: MENU: GENERATE + TRANSLATE (set & forget)
:: ============================================================
:MENU_GENERATE_TRANSLATE
cls
echo ============================================================
echo   GENERATE + TRANSLATE (WhisperX)
echo   Folder: %SCRIPT_DIR%
echo ============================================================
echo.

if "!CLAUDE_CMD!"=="" if "!GEMINI_CMD!"=="" (
    echo  [WARN] No translation engine found. Translation step will be skipped.
    echo  Install Claude : npm install -g @anthropic-ai/claude-code
    echo  Install Gemini : npm install -g @google/gemini-cli
    echo.
)

echo  Scanning for video files in: %SCRIPT_DIR%
echo  [SRT] = subtitle already exists
echo ============================================================
echo.

set "IDX=0"
for /r "%SCRIPT_DIR%" %%f in (
    *.mp4 *.mkv *.avi *.mov *.ts *.m4v *.flv *.wmv *.webm *.mpeg *.mpg
) do (
    set /a IDX+=1
    set "FILE_!IDX!=%%f"
    set "REL=%%f"
    set "REL=!REL:%SCRIPT_DIR%\=!"
    set "SMARK=     "
    if exist "%%~dpn.srt" set "SMARK=[SRT]"
    echo  [!IDX!] !SMARK! !REL!
)

if !IDX!==0 (
    echo  No video files found in this folder.
    pause
    exit /b 0
)

echo.
echo  Found: !IDX! video file(s)
echo.

:GT_CHOOSE_FILE
set "CHOICE="
set /p CHOICE="Enter file number (1-!IDX!) or 'all': "

if /i "!CHOICE!"=="all" goto GT_CHOOSE_OPTIONS
if "!CHOICE!"=="" goto GT_CHOOSE_FILE
set /a TEST_CHOICE=!CHOICE! 2>nul
if !TEST_CHOICE! LSS 1 goto GT_INVALID_CHOICE
if !TEST_CHOICE! GTR !IDX! goto GT_INVALID_CHOICE
goto GT_CHOOSE_OPTIONS

:GT_INVALID_CHOICE
echo  [!] Invalid input
goto GT_CHOOSE_FILE

:GT_CHOOSE_OPTIONS
set "VID_MIN=0"
set "VID_HHMM=unknown"
if /i not "!CHOICE!"=="all" (
    set "VIDEO_FILE=!FILE_%CHOICE%!"
    call :GET_VIDEO_DURATION
)
echo.
echo ============================================================
echo   TRANSCRIPTION OPTIONS  (WhisperX)
echo ============================================================
if /i not "!CHOICE!"=="all" if not "!VID_HHMM!"=="unknown" (
    echo  Duration : !VID_HHMM!
    if "!CUDA_OK!"=="false" (
        if !VID_MIN! GTR 60 echo  [TIP] Long video on CPU -- 'small' for speed, 'medium' for quality
    ) else (
        if !VID_MIN! GTR 90 echo  [TIP] Long video -- 'large-v3-turbo' for speed, 'large-v3' for max accuracy
    )
    echo ============================================================
)
echo.

set "WX_CACHE=%USERPROFILE%\.cache\huggingface\hub"
set "M1=tiny"
set "M2=base"
set "M3=small"
set "M4=medium"
set "M5=large-v1"
set "M6=large-v2"
set "M7=large-v3"
set "M8=large-v3-turbo"
for %%i in (1 2 3 4 5 6 7 8) do (
    set "ST_%%i=          "
    if exist "!WX_CACHE!\models--Systran--faster-whisper-!M%%i!\" set "ST_%%i=[downloaded]"
)

echo  Select model:
echo  -----------------------------------------------------------
echo   [1] tiny              ~75 MB    !ST_1!
echo   [2] base             ~145 MB    !ST_2!
echo   [3] small            ~466 MB    !ST_3!
echo   [4] medium           ~1.5 GB    !ST_4!   ^(DEFAULT^)
echo   [5] large-v1         ~3.0 GB    !ST_5!
echo   [6] large-v2         ~3.0 GB    !ST_6!
echo   [7] large-v3         ~3.0 GB    !ST_7!
echo   [8] large-v3-turbo   ~1.62 GB   !ST_8!
echo  -----------------------------------------------------------
echo.
set /p MODEL_CHOICE="Choose model [1-8, default=4]: "

if "!MODEL_CHOICE!"=="1" set MODEL=tiny
if "!MODEL_CHOICE!"=="2" set MODEL=base
if "!MODEL_CHOICE!"=="3" set MODEL=small
if "!MODEL_CHOICE!"=="4" set MODEL=medium
if "!MODEL_CHOICE!"=="5" set MODEL=large-v1
if "!MODEL_CHOICE!"=="6" set MODEL=large-v2
if "!MODEL_CHOICE!"=="7" set MODEL=large-v3
if "!MODEL_CHOICE!"=="8" set MODEL=large-v3-turbo
if "!MODEL_CHOICE!"==""  set MODEL=medium

echo.
echo  Source language of the video:
echo   [1] Auto-detect  (mixed / unsure)   [DEFAULT]
echo   [2] Japanese
echo   [3] Korean
echo   [4] Chinese (Mandarin)
echo   [5] Cantonese
echo   [6] Indonesian
echo   [7] English
echo   [8] Other (type manually)
echo.
set /p LANG_CHOICE="Choose language [1-8, default=1]: "

if "!LANG_CHOICE!"=="1" set LANGUAGE=
if "!LANG_CHOICE!"=="2" set LANGUAGE=Japanese
if "!LANG_CHOICE!"=="3" set LANGUAGE=Korean
if "!LANG_CHOICE!"=="4" set LANGUAGE=Chinese
if "!LANG_CHOICE!"=="5" set LANGUAGE=Cantonese
if "!LANG_CHOICE!"=="6" set LANGUAGE=Indonesian
if "!LANG_CHOICE!"=="7" set LANGUAGE=English
if "!LANG_CHOICE!"=="8" (
    set /p LANGUAGE="Enter language name (e.g. Thai, Vietnamese, Arabic): "
)
if "!LANG_CHOICE!"==""  set LANGUAGE=

echo.
echo  Output format:
echo   [1] srt  - most compatible   [DEFAULT]
echo   [2] vtt  - for web
echo   [3] txt  - plain text without timestamps
echo   [4] all  - generate all formats
echo.
set /p FMT_CHOICE="Choose format [1-4, default=1]: "

if "!FMT_CHOICE!"=="1" set OUTPUT_FORMAT=srt
if "!FMT_CHOICE!"=="2" set OUTPUT_FORMAT=vtt
if "!FMT_CHOICE!"=="3" set OUTPUT_FORMAT=txt
if "!FMT_CHOICE!"=="4" set OUTPUT_FORMAT=all
if "!FMT_CHOICE!"==""  set OUTPUT_FORMAT=srt

set "SRT_LANG=unknown"
if "!LANGUAGE!"=="Japanese"   set "SRT_LANG=ja"
if "!LANGUAGE!"=="Korean"     set "SRT_LANG=ko"
if "!LANGUAGE!"=="Chinese"    set "SRT_LANG=zh"
if "!LANGUAGE!"=="Cantonese"  set "SRT_LANG=zh"
if "!LANGUAGE!"=="Indonesian" set "SRT_LANG=id"
if "!LANGUAGE!"=="English"    set "SRT_LANG=en"

call :CHOOSE_TARGET_LANG

echo.
echo ============================================================
echo   SUMMARY:
if /i "!CHOICE!"=="all" (
    echo   Files   : ALL !IDX! files
) else (
    echo   File    : !FILE_%CHOICE%!
)
echo   Engine  : WhisperX
echo   Model   : !MODEL!
if "!LANGUAGE!"=="" (
    echo   Language: Auto-detect
) else (
    echo   Language: !LANGUAGE!
)
echo   Device  : !WHISPER_DEVICE!
echo   Output  : .!OUTPUT_FORMAT!
echo   Translate to: !TARGET_LANG!
echo ============================================================
echo.
set /p CONFIRM="Continue? (Y/N): "
if /i not "!CONFIRM!"=="Y" goto GT_CHOOSE_FILE

set "AUTO_TRANSLATE=true"

if /i "!CHOICE!"=="all" goto GT_PROCESS_ALL

set "TARGET_FILE=!FILE_%CHOICE%!"
call :RUN_WHISPER "!TARGET_FILE!"
goto DONE

:GT_PROCESS_ALL
for /l %%i in (1,1,!IDX!) do (
    echo.
    echo  [%%i/!IDX!] Processing: !FILE_%%i!
    call :RUN_WHISPER "!FILE_%%i!"
)
goto DONE

:: ============================================================
:: MENU: GENERATE SUBTITLE
:: ============================================================
:MENU_GENERATE
cls
echo ============================================================
echo   GENERATE SUBTITLE  (WhisperX)
echo   Folder: %SCRIPT_DIR%
echo ============================================================
echo.

echo  Scanning for video files in: %SCRIPT_DIR%
echo  [SRT] = subtitle already exists
echo ============================================================
echo.

set "IDX=0"
for /r "%SCRIPT_DIR%" %%f in (
    *.mp4 *.mkv *.avi *.mov *.ts *.m4v *.flv *.wmv *.webm *.mpeg *.mpg
) do (
    set /a IDX+=1
    set "FILE_!IDX!=%%f"
    set "REL=%%f"
    set "REL=!REL:%SCRIPT_DIR%\=!"
    set "SMARK=     "
    if exist "%%~dpn.srt" set "SMARK=[SRT]"
    echo  [!IDX!] !SMARK! !REL!
)

if !IDX!==0 (
    echo  No video files found in this folder.
    pause
    exit /b 0
)

echo.
echo  Found: !IDX! video file(s)
echo.

:CHOOSE_FILE
set "CHOICE="
set /p CHOICE="Enter file number (1-!IDX!) or 'all': "

if /i "!CHOICE!"=="all" goto CHOOSE_OPTIONS
if "!CHOICE!"=="" goto CHOOSE_FILE
set /a TEST_CHOICE=!CHOICE! 2>nul
if !TEST_CHOICE! LSS 1 goto INVALID_CHOICE
if !TEST_CHOICE! GTR !IDX! goto INVALID_CHOICE
goto CHOOSE_OPTIONS

:INVALID_CHOICE
echo  [!] Invalid input
goto CHOOSE_FILE

:CHOOSE_OPTIONS
set "VID_MIN=0"
set "VID_HHMM=unknown"
if /i not "!CHOICE!"=="all" (
    set "VIDEO_FILE=!FILE_%CHOICE%!"
    call :GET_VIDEO_DURATION
)
echo.
echo ============================================================
echo   TRANSCRIPTION OPTIONS  (WhisperX)
echo ============================================================
if /i not "!CHOICE!"=="all" if not "!VID_HHMM!"=="unknown" (
    echo  Duration : !VID_HHMM!
    if "!CUDA_OK!"=="false" (
        if !VID_MIN! GTR 60 echo  [TIP] Long video on CPU -- 'small' for speed, 'medium' for quality
    ) else (
        if !VID_MIN! GTR 90 echo  [TIP] Long video -- 'large-v3-turbo' for speed, 'large-v3' for max accuracy
    )
    echo ============================================================
)
echo.

set "WX_CACHE=%USERPROFILE%\.cache\huggingface\hub"
set "M1=tiny"
set "M2=base"
set "M3=small"
set "M4=medium"
set "M5=large-v1"
set "M6=large-v2"
set "M7=large-v3"
set "M8=large-v3-turbo"
for %%i in (1 2 3 4 5 6 7 8) do (
    set "ST_%%i=          "
    if exist "!WX_CACHE!\models--Systran--faster-whisper-!M%%i!\" set "ST_%%i=[downloaded]"
)

echo  Select model:
echo  -----------------------------------------------------------
echo   [1] tiny              ~75 MB    !ST_1!
echo   [2] base             ~145 MB    !ST_2!
echo   [3] small            ~466 MB    !ST_3!
echo   [4] medium           ~1.5 GB    !ST_4!   ^(DEFAULT^)
echo   [5] large-v1         ~3.0 GB    !ST_5!
echo   [6] large-v2         ~3.0 GB    !ST_6!
echo   [7] large-v3         ~3.0 GB    !ST_7!
echo   [8] large-v3-turbo   ~1.62 GB   !ST_8!
echo  -----------------------------------------------------------
echo.
set /p MODEL_CHOICE="Choose model [1-8, default=4]: "

if "!MODEL_CHOICE!"=="1" set MODEL=tiny
if "!MODEL_CHOICE!"=="2" set MODEL=base
if "!MODEL_CHOICE!"=="3" set MODEL=small
if "!MODEL_CHOICE!"=="4" set MODEL=medium
if "!MODEL_CHOICE!"=="5" set MODEL=large-v1
if "!MODEL_CHOICE!"=="6" set MODEL=large-v2
if "!MODEL_CHOICE!"=="7" set MODEL=large-v3
if "!MODEL_CHOICE!"=="8" set MODEL=large-v3-turbo
if "!MODEL_CHOICE!"==""  set MODEL=medium

echo.
echo  Source language of the video:
echo   [1] Auto-detect  (mixed / unsure)   [DEFAULT]
echo   [2] Japanese
echo   [3] Korean
echo   [4] Chinese (Mandarin)
echo   [5] Cantonese
echo   [6] Indonesian
echo   [7] English
echo   [8] Other (type manually)
echo.
set /p LANG_CHOICE="Choose language [1-8, default=1]: "

if "!LANG_CHOICE!"=="1" set LANGUAGE=
if "!LANG_CHOICE!"=="2" set LANGUAGE=Japanese
if "!LANG_CHOICE!"=="3" set LANGUAGE=Korean
if "!LANG_CHOICE!"=="4" set LANGUAGE=Chinese
if "!LANG_CHOICE!"=="5" set LANGUAGE=Cantonese
if "!LANG_CHOICE!"=="6" set LANGUAGE=Indonesian
if "!LANG_CHOICE!"=="7" set LANGUAGE=English
if "!LANG_CHOICE!"=="8" (
    set /p LANGUAGE="Enter language name (e.g. Thai, Vietnamese, Arabic): "
)
if "!LANG_CHOICE!"==""  set LANGUAGE=

echo.
echo  Output format:
echo   [1] srt  - most compatible   [DEFAULT]
echo   [2] vtt  - for web
echo   [3] txt  - plain text without timestamps
echo   [4] all  - generate all formats
echo.
set /p FMT_CHOICE="Choose format [1-4, default=1]: "

if "!FMT_CHOICE!"=="1" set OUTPUT_FORMAT=srt
if "!FMT_CHOICE!"=="2" set OUTPUT_FORMAT=vtt
if "!FMT_CHOICE!"=="3" set OUTPUT_FORMAT=txt
if "!FMT_CHOICE!"=="4" set OUTPUT_FORMAT=all
if "!FMT_CHOICE!"==""  set OUTPUT_FORMAT=srt

echo.
echo ============================================================
echo   SUMMARY:
if /i "!CHOICE!"=="all" (
    echo   File    : ALL !IDX! files
) else (
    echo   File    : !FILE_%CHOICE%!
)
echo   Engine  : WhisperX
echo   Model   : !MODEL!
if "!LANGUAGE!"=="" (
    echo   Language: Auto-detect
) else (
    echo   Language: !LANGUAGE!
)
echo   Device  : !WHISPER_DEVICE!
echo   Output  : .!OUTPUT_FORMAT!
echo ============================================================
echo.
set /p CONFIRM="Continue? (Y/N): "
if /i not "!CONFIRM!"=="Y" goto CHOOSE_FILE

if /i "!CHOICE!"=="all" goto PROCESS_ALL

set "TARGET_FILE=!FILE_%CHOICE%!"
call :RUN_WHISPER "!TARGET_FILE!"
goto DONE

:PROCESS_ALL
for /l %%i in (1,1,!IDX!) do (
    echo.
    echo  [%%i/!IDX!] Processing: !FILE_%%i!
    call :RUN_WHISPER "!FILE_%%i!"
)
goto DONE

:: ============================================================
:: SUBROUTINE: Run WhisperX on one file
:: ============================================================
:RUN_WHISPER
set "INPUT_FILE=%~1"
set "FILE_DIR=%~dp1"
set "FILE_DIR=%FILE_DIR:~0,-1%"

echo.
echo  Processing : %~nx1
echo  Output to  : %FILE_DIR%
echo  Engine     : WhisperX
echo  Model      : %MODEL%
echo  Device     : %WHISPER_DEVICE%
echo  --------------------------------------------------------

if "%LANGUAGE%"=="" (
    whisperx "%INPUT_FILE%" --model %MODEL% --output_format %OUTPUT_FORMAT% --output_dir "%FILE_DIR%" --device %WHISPER_DEVICE%
) else (
    whisperx "%INPUT_FILE%" --model %MODEL% --language %LANGUAGE% --output_format %OUTPUT_FORMAT% --output_dir "%FILE_DIR%" --device %WHISPER_DEVICE%
)

if errorlevel 1 (
    echo  [ERROR] Failed to process: %~nx1
    goto :eof
)

echo  [DONE] Subtitle saved to: %FILE_DIR%

set "SRT_FILE=%FILE_DIR%\%~n1.srt"
if exist "!SRT_FILE!" (
    echo.
    echo  --------------------------------------------------------
    if "!AUTO_TRANSLATE!"=="true" (
        echo  Auto-translating to !TARGET_LANG!...
        if "!SRT_LANG!"=="unknown" (
            set "DETECT_FILE=!SRT_FILE!"
            call :DETECT_SRT_LANG
        )
        call :RUN_TRANSLATE "!SRT_FILE!"
    ) else (
        set /p TRANSLATE_NOW="  Translate subtitle? (Y/N, default=N): "
        if /i "!TRANSLATE_NOW!"=="Y" (
            set "SRT_LANG=unknown"
            if "!LANGUAGE!"=="Japanese"   set "SRT_LANG=ja"
            if "!LANGUAGE!"=="Korean"     set "SRT_LANG=ko"
            if "!LANGUAGE!"=="Chinese"    set "SRT_LANG=zh"
            if "!LANGUAGE!"=="Cantonese"  set "SRT_LANG=zh"
            if "!LANGUAGE!"=="Indonesian" set "SRT_LANG=id"
            if "!LANGUAGE!"=="English"    set "SRT_LANG=en"
            if "!SRT_LANG!"=="unknown" (
                set "DETECT_FILE=!SRT_FILE!"
                call :DETECT_SRT_LANG
            )
            call :CHOOSE_TARGET_LANG
            call :RUN_TRANSLATE "!SRT_FILE!"
        ) else (
            echo  [INFO] Skipped. Use menu [2] to translate later.
        )
    )
)
goto :eof

:: ============================================================
:: SUBROUTINE: Detect SRT source language
:: ============================================================
:DETECT_SRT_LANG
set "SRT_LANG=unknown"
for /f "tokens=*" %%L in ('python "%~dp0translate_srt.py" --detect-lang "!DETECT_FILE!" 2^>nul') do set "SRT_LANG=%%L"
goto :eof

:: ============================================================
:: SUBROUTINE: Choose target language (excludes source lang)
:: ============================================================
:CHOOSE_TARGET_LANG
set "SRT_LANG_NAME=Unknown"
if "!SRT_LANG!"=="en" set "SRT_LANG_NAME=English"
if "!SRT_LANG!"=="id" set "SRT_LANG_NAME=Indonesian"
if "!SRT_LANG!"=="ja" set "SRT_LANG_NAME=Japanese"
if "!SRT_LANG!"=="ko" set "SRT_LANG_NAME=Korean"
if "!SRT_LANG!"=="zh" set "SRT_LANG_NAME=Chinese"

echo.
echo  Detected source language: !SRT_LANG_NAME!
echo.
echo  Select translation target:
echo.

set "TL_COUNT=0"

if not "!SRT_LANG!"=="en" (
    set /a TL_COUNT+=1
    echo   [!TL_COUNT!] English
)
if not "!SRT_LANG!"=="id" (
    set /a TL_COUNT+=1
    echo   [!TL_COUNT!] Indonesian
)
if not "!SRT_LANG!"=="ja" (
    set /a TL_COUNT+=1
    echo   [!TL_COUNT!] Japanese
)
if not "!SRT_LANG!"=="ko" (
    set /a TL_COUNT+=1
    echo   [!TL_COUNT!] Korean
)
if not "!SRT_LANG!"=="zh" (
    set /a TL_COUNT+=1
    echo   [!TL_COUNT!] Chinese (Mandarin)
)
set /a TL_COUNT+=1
echo   [!TL_COUNT!] Other (type manually)
echo.

set /p TL_CHOICE="Choose target [1-!TL_COUNT!]: "
if "!TL_CHOICE!"=="" set "TL_CHOICE=1"
set /a TL_CHOICE=!TL_CHOICE! 2>nul
if !TL_CHOICE! LSS 1 set "TL_CHOICE=1"
if !TL_CHOICE! GTR !TL_COUNT! set "TL_CHOICE=!TL_COUNT!"

set "TL_ITER=0"
set "TARGET_LANG=Other"
set "TARGET_SUFFIX=_TRANSLATED"

if not "!SRT_LANG!"=="en" (
    set /a TL_ITER+=1
    if "!TL_ITER!"=="!TL_CHOICE!" (
        set "TARGET_LANG=English"
        set "TARGET_SUFFIX=_EN"
    )
)
if not "!SRT_LANG!"=="id" (
    set /a TL_ITER+=1
    if "!TL_ITER!"=="!TL_CHOICE!" (
        set "TARGET_LANG=Indonesian"
        set "TARGET_SUFFIX=_ID"
    )
)
if not "!SRT_LANG!"=="ja" (
    set /a TL_ITER+=1
    if "!TL_ITER!"=="!TL_CHOICE!" (
        set "TARGET_LANG=Japanese"
        set "TARGET_SUFFIX=_JA"
    )
)
if not "!SRT_LANG!"=="ko" (
    set /a TL_ITER+=1
    if "!TL_ITER!"=="!TL_CHOICE!" (
        set "TARGET_LANG=Korean"
        set "TARGET_SUFFIX=_KO"
    )
)
if not "!SRT_LANG!"=="zh" (
    set /a TL_ITER+=1
    if "!TL_ITER!"=="!TL_CHOICE!" (
        set "TARGET_LANG=Chinese"
        set "TARGET_SUFFIX=_ZH"
    )
)

if "!TARGET_LANG!"=="Other" (
    set /p TARGET_LANG="  Enter target language (e.g. Thai, Vietnamese, Arabic): "
    set "TARGET_SUFFIX=_TRANSLATED"
)

echo  Target: !TARGET_LANG!
goto :eof

:: ============================================================
:: SUBROUTINE: Run translation
:: ============================================================
:RUN_TRANSLATE
set "TRANS_FILE=%~1"
set "TRANS_SUCCESS=false"
set "GEMINI_PARTIAL=false"

if "!GEMINI_CMD!"=="" if "!CLAUDE_CMD!"=="" (
    echo  [INFO] No translation engine available. Install Claude or Gemini first.
    goto :eof
)

if not "!GEMINI_CMD!"=="" (
    echo  [1] Trying Gemini...
    python "%~dp0translate_srt.py" "!TRANS_FILE!" "!GEMINI_CMD!" "gemini" "!TARGET_LANG!"
    set "GEMINI_EC=!errorlevel!"
    if "!GEMINI_EC!"=="0" set "TRANS_SUCCESS=true"
    if "!GEMINI_EC!"=="2" set "GEMINI_PARTIAL=true"
)

if "!GEMINI_PARTIAL!"=="true" (
    if not "!CLAUDE_CMD!"=="" (
        echo.
        echo  [!] Gemini partial translation detected.
        set /p RETRY_CLAUDE="  Try with Claude to complete remaining segments? (Y/N): "
        if /i "!RETRY_CLAUDE!"=="Y" (
            echo  [2] Trying Claude...
            python "%~dp0translate_srt.py" "!TRANS_FILE!" "!CLAUDE_CMD!" "claude" "!TARGET_LANG!"
        )
    )
    goto :eof
)

if "!TRANS_SUCCESS!"=="false" (
    if not "!CLAUDE_CMD!"=="" (
        if not "!GEMINI_CMD!"=="" (
            echo  [!] Gemini failed ^(0 translations^), using Claude as fallback...
        ) else (
            echo  [2] Trying Claude...
        )
        python "%~dp0translate_srt.py" "!TRANS_FILE!" "!CLAUDE_CMD!" "claude" "!TARGET_LANG!"
    )
)
goto :eof

:: ============================================================
:: SUBROUTINE: Get video duration via ffprobe
:: ============================================================
:GET_VIDEO_DURATION
set "VID_MIN=0"
set "VID_HHMM=unknown"
set "FFPROBE_DUR="
ffprobe -v quiet -show_entries format=duration -of csv=p=0 "!VIDEO_FILE!" > "%TEMP%\ffprobe_dur.tmp" 2>nul
for /f "usebackq tokens=*" %%D in ("%TEMP%\ffprobe_dur.tmp") do set "FFPROBE_DUR=%%D"
del "%TEMP%\ffprobe_dur.tmp" 2>nul
if not defined FFPROBE_DUR goto :eof
if "!FFPROBE_DUR!"=="" goto :eof
for /f "tokens=*" %%L in ('python "%~dp0check_gpu.py" duration "!FFPROBE_DUR!" 2^>nul') do set "%%L"
goto :eof

:: ============================================================
:: DONE
:: ============================================================
:DONE
echo.
echo ============================================================
echo   All done!
echo ============================================================
echo.
pause
