@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul 2>&1

:: ============================================================
::  WHISPER SUBTITLE EXTRACTOR
::  Place this .bat in your video folder and double-click
:: ============================================================

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "MODEL=medium"
set "LANGUAGE="
set "OUTPUT_FORMAT=srt"
set "WHISPER_DEVICE=cpu"
set "AUTO_TRANSLATE=false"
set "OFFLINE_TRANSLATE=false"
set "OFFLINE_LLM=false"

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
where whisper >nul 2>&1
if errorlevel 1 (
    echo  [ERROR] Whisper not found. Please run install.bat to reinstall.
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
:: GPU CHECK (quick verify, no install)
:: ============================================================
set "CUDA_OK=false"
set "GPU_DEVICE=cpu"
set "GPU_NAME="
set "VRAM="
for /f "tokens=*" %%L in ('python "%~dp0check_gpu.py" verify 2^>nul') do (
    set "%%L"
)
set "WHISPER_DEVICE=!GPU_DEVICE!"

:: ============================================================
:: ENGINE DETECTION (runs once, shared by all menus)
:: ============================================================
set "GEMINI_CMD="
set "NLLB_AVAILABLE=false"

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
python -c "import transformers" >nul 2>&1
if not errorlevel 1 set "NLLB_AVAILABLE=true"

set "OLLAMA_AVAILABLE=false"
set "OLLAMA_MODEL=none"
ollama --version >nul 2>&1
if not errorlevel 1 (
    set "OLLAMA_AVAILABLE=true"
    if exist "%SCRIPT_DIR%\.ollama" (
        for /f "usebackq tokens=*" %%M in ("%SCRIPT_DIR%\.ollama") do set "OLLAMA_MODEL=%%M"
    )
)

:: ============================================================
:: MAIN MENU
:: ============================================================
:MAIN_LOOP
set "AUTO_TRANSLATE=false"
set "OFFLINE_TRANSLATE=false"
set "OFFLINE_LLM=false"
cls
echo ============================================================
echo   WHISPER SUBTITLE EXTRACTOR
echo   Folder: %SCRIPT_DIR%
if not "!GPU_DEVICE!"=="cpu" (
    echo   GPU   : !GPU_NAME! ^(!VRAM!^)
) else (
    echo   GPU   : CPU mode
)
echo ============================================================
echo.
echo   [1] Generate Subtitle            - extract subtitles from video files
echo   [2] Translate Subtitle           - translate .srt files ^(Gemini + NLLB^)
echo   [3] Generate + Translate         - extract then auto-translate ^(set ^& forget^)
echo   [4] Cleanup SRT                  - fix overlaps and merge short segments
echo   [5] Translate Offline ^(NLLB^)     - translate .srt using NLLB only
echo   [6] Generate + Translate Offline ^(NLLB^) - generate then translate ^(NLLB only^)
echo   [7] Translate Offline ^(LLM+NLLB^) - translate .srt using Offline LLM + NLLB
echo   [8] Generate + Translate Offline ^(LLM+NLLB^) - generate then translate offline
echo.
set /p MAIN_MENU="Choose [1-8]: "

if "!MAIN_MENU!"=="2" goto MENU_TRANSLATE
if "!MAIN_MENU!"=="3" goto MENU_GENERATE_TRANSLATE
if "!MAIN_MENU!"=="4" goto MENU_CLEANUP
if "!MAIN_MENU!"=="5" goto MENU_TRANSLATE_OFFLINE
if "!MAIN_MENU!"=="6" goto MENU_GT_OFFLINE
if "!MAIN_MENU!"=="7" goto MENU_TRANSLATE_LLM
if "!MAIN_MENU!"=="8" goto MENU_GT_LLM
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

if "!GEMINI_CMD!"=="" if "!NLLB_AVAILABLE!"=="false" (
    echo  [ERROR] No translation engine found.
    echo  Install Gemini : npm install -g @google/gemini-cli
    echo  Install NLLB   : pip install transformers sentencepiece sacremoses
    echo  Then re-run install.bat to verify.
    goto RETURN_OR_QUIT
)
if not "!GEMINI_CMD!"=="" echo  [OK] Gemini : !GEMINI_CMD!
if "!NLLB_AVAILABLE!"=="true" echo  [OK] NLLB   : offline ^(local model^)
echo.

:: Scan .srt files (skip already-translated files)
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
    goto RETURN_OR_QUIT
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

:: Single file
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
:: Detect language from first file, apply to all
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
goto RETURN_OR_QUIT

:: ============================================================
:: MENU: CLEANUP SRT
:: ============================================================
:MENU_CLEANUP
cls
echo ============================================================
echo   CLEANUP SRT
echo   Folder: %SCRIPT_DIR%
echo ============================================================
echo.
echo  Fixes timestamp overlaps and merges very short segments.
echo  Output saved as: original_clean.srt
echo.

echo  Scanning for subtitle files (.srt) in: %SCRIPT_DIR%
echo ============================================================
echo.

set "CIDX=0"
for /r "%SCRIPT_DIR%" %%f in (*.srt) do (
    echo %%~nf | findstr /ri "_clean$\|_EN$\|_ID$\|_JA$\|_KO$\|_ZH$\|_TRANSLATED$" >nul
    if errorlevel 1 (
        set /a CIDX+=1
        set "CFILE_!CIDX!=%%f"
        set "CREL=%%f"
        set "CREL=!CREL:%SCRIPT_DIR%\=!"
        echo  [!CIDX!] !CREL!
    )
)

if !CIDX!==0 (
    echo  No .srt files found.
    goto RETURN_OR_QUIT
)

echo.
echo  Found: !CIDX! subtitle file(s)
echo.

:CLEANUP_CHOOSE
set "CCHOICE="
set /p CCHOICE="Enter file number (1-!CIDX!) or 'all': "

if /i "!CCHOICE!"=="all" goto CLEANUP_RUN_ALL
if "!CCHOICE!"=="" goto CLEANUP_CHOOSE
set /a CTEST=!CCHOICE! 2>nul
if !CTEST! LSS 1 goto CLEANUP_INVALID
if !CTEST! GTR !CIDX! goto CLEANUP_INVALID

echo.
echo  Cleaning: !CFILE_%CCHOICE%!
python "%~dp0cleanup_srt.py" "!CFILE_%CCHOICE%!"
goto CLEANUP_DONE

:CLEANUP_INVALID
echo  [!] Invalid input
goto CLEANUP_CHOOSE

:CLEANUP_RUN_ALL
echo.
for /l %%i in (1,1,!CIDX!) do (
    echo  [%%i/!CIDX!] !CFILE_%%i!
    python "%~dp0cleanup_srt.py" "!CFILE_%%i!"
    echo.
)

:CLEANUP_DONE
echo.
echo ============================================================
echo   Cleanup complete!
echo ============================================================
echo.
goto RETURN_OR_QUIT

:: ============================================================
:: MENU: TRANSLATE OFFLINE (NLLB only)
:: ============================================================
:MENU_TRANSLATE_OFFLINE
cls
echo ============================================================
echo   TRANSLATE OFFLINE ^(NLLB only^)
echo   Folder: %SCRIPT_DIR%
echo ============================================================
echo.

if "!NLLB_AVAILABLE!"=="false" (
    echo  [ERROR] NLLB not installed.
    echo  Install NLLB : pip install transformers sentencepiece sacremoses
    echo  Then re-run to verify.
    goto RETURN_OR_QUIT
)
echo  [OK] NLLB : offline ^(local model^)
echo  [INFO] Gemini is skipped. All translation done offline via NLLB.
echo.

:: Scan .srt files (skip already-translated files)
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
    goto RETURN_OR_QUIT
)

echo.
echo  Found: !SIDX! subtitle file(s)
echo.

:OFFLINE_CHOOSE_SRT
set "SCHOICE="
set /p SCHOICE="Enter file number (1-!SIDX!) or 'all': "

if /i "!SCHOICE!"=="all" goto OFFLINE_TRANSLATE_ALL
if "!SCHOICE!"=="" goto OFFLINE_CHOOSE_SRT
set /a STEST=!SCHOICE! 2>nul
if !STEST! LSS 1 goto OFFLINE_INVALID_SRT
if !STEST! GTR !SIDX! goto OFFLINE_INVALID_SRT

:: Single file
set "DETECT_FILE=!SFILE_%SCHOICE%!"
call :DETECT_SRT_LANG
call :CHOOSE_TARGET_LANG
echo.
call :RUN_TRANSLATE_OFFLINE "!SFILE_%SCHOICE%!"
goto OFFLINE_TRANSLATE_DONE

:OFFLINE_INVALID_SRT
echo  [!] Invalid input
goto OFFLINE_CHOOSE_SRT

:OFFLINE_TRANSLATE_ALL
set "DETECT_FILE=!SFILE_1!"
call :DETECT_SRT_LANG
call :CHOOSE_TARGET_LANG
echo.
for /l %%i in (1,1,!SIDX!) do (
    echo  [%%i/!SIDX!] Translating: !SFILE_%%i!
    call :RUN_TRANSLATE_OFFLINE "!SFILE_%%i!"
)

:OFFLINE_TRANSLATE_DONE
echo.
echo ============================================================
echo   Offline translation complete!
echo ============================================================
echo.
goto RETURN_OR_QUIT

:: ============================================================
:: MENU: GENERATE + TRANSLATE OFFLINE (NLLB only)
:: ============================================================
:MENU_GT_OFFLINE
cls
echo ============================================================
echo   GENERATE + TRANSLATE OFFLINE ^(NLLB only^)
echo   Folder: %SCRIPT_DIR%
echo ============================================================
echo.

if "!NLLB_AVAILABLE!"=="false" (
    echo  [WARN] NLLB not installed. Translation step will be skipped.
    echo  Install NLLB : pip install transformers sentencepiece sacremoses
    echo.
)
echo  [INFO] Gemini is skipped. Translation done offline via NLLB.
echo.

:: Scan video files
echo  Scanning for video files in: %SCRIPT_DIR%
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
    echo  [!IDX!] !REL!
)

if !IDX!==0 (
    echo  No video files found in this folder.
    goto RETURN_OR_QUIT
)

echo.
echo  Found: !IDX! video file(s)
echo.

:GTO_CHOOSE_FILE
set "CHOICE="
set /p CHOICE="Enter file number (1-!IDX!) or 'all': "

if /i "!CHOICE!"=="all" goto GTO_CHOOSE_OPTIONS
if "!CHOICE!"=="" goto GTO_CHOOSE_FILE
set /a TEST_CHOICE=!CHOICE! 2>nul
if !TEST_CHOICE! LSS 1 goto GTO_INVALID_CHOICE
if !TEST_CHOICE! GTR !IDX! goto GTO_INVALID_CHOICE
goto GTO_CHOOSE_OPTIONS

:GTO_INVALID_CHOICE
echo  [!] Invalid input
goto GTO_CHOOSE_FILE

:GTO_CHOOSE_OPTIONS
:: Get video duration for single file selection
set "VID_MIN=0"
set "VID_HHMM=unknown"
if /i not "!CHOICE!"=="all" (
    set "VIDEO_FILE=!FILE_%CHOICE%!"
    call :GET_VIDEO_DURATION
)
echo.
echo ============================================================
echo   TRANSCRIPTION OPTIONS
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
echo   [1] tiny           - fastest, lower accuracy         ^| ~1GB  VRAM
echo   [2] base           - fast, decent accuracy           ^| ~1GB  VRAM
echo   [3] small          - balanced                        ^| ~2GB  VRAM
echo   [4] medium         - good accuracy        [DEFAULT]  ^| ~5GB  VRAM
echo   [5] large-v1       - high accuracy                   ^| ~10GB VRAM
echo   [6] large-v2       - better than v1                  ^| ~10GB VRAM
echo   [7] large-v3       - best official accuracy          ^| ~10GB VRAM
echo   [8] large-v3-turbo - fast, near v3 quality           ^| ~6GB  VRAM
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

:: Set SRT_LANG from source language for smart target exclusion
set "SRT_LANG=unknown"
if "!LANGUAGE!"=="Japanese"   set "SRT_LANG=ja"
if "!LANGUAGE!"=="Korean"     set "SRT_LANG=ko"
if "!LANGUAGE!"=="Chinese"    set "SRT_LANG=zh"
if "!LANGUAGE!"=="Cantonese"  set "SRT_LANG=zh"
if "!LANGUAGE!"=="Indonesian" set "SRT_LANG=id"
if "!LANGUAGE!"=="English"    set "SRT_LANG=en"

:: Ask target language upfront
call :CHOOSE_TARGET_LANG

:: Summary
echo.
echo ============================================================
echo   SUMMARY:
if /i "!CHOICE!"=="all" (
    echo   Files   : ALL !IDX! files
) else (
    echo   File    : !FILE_%CHOICE%!
)
echo   Model   : !MODEL!
if "!LANGUAGE!"=="" (
    echo   Language: Auto-detect
) else (
    echo   Language: !LANGUAGE!
)
echo   Device  : !WHISPER_DEVICE!
echo   Output  : .!OUTPUT_FORMAT!
echo   Translate to: !TARGET_LANG! ^(NLLB offline^)
echo ============================================================
echo.
set /p CONFIRM="Continue? (Y/N): "
if /i not "!CONFIRM!"=="Y" goto GTO_CHOOSE_FILE

set "AUTO_TRANSLATE=true"
set "OFFLINE_TRANSLATE=true"

if /i "!CHOICE!"=="all" goto GTO_PROCESS_ALL

set "TARGET_FILE=!FILE_%CHOICE%!"
call :RUN_WHISPER "!TARGET_FILE!"
goto DONE

:GTO_PROCESS_ALL
for /l %%i in (1,1,!IDX!) do (
    echo.
    echo  [%%i/!IDX!] Processing: !FILE_%%i!
    call :RUN_WHISPER "!FILE_%%i!"
)
goto DONE

:: ============================================================
:: MENU: TRANSLATE OFFLINE (LLM + NLLB)
:: ============================================================
:MENU_TRANSLATE_LLM
cls
echo ============================================================
echo   TRANSLATE OFFLINE ^(LLM + NLLB^)
echo   Folder: %SCRIPT_DIR%
echo ============================================================
echo.

if "!OLLAMA_AVAILABLE!"=="false" (
    echo  [ERROR] Ollama not found. Please run install.bat to set up Offline LLM.
    echo.
    goto RETURN_OR_QUIT
)
if "!OLLAMA_MODEL!"=="none" (
    echo  [ERROR] No Offline LLM model configured. Run install.bat and select a model.
    echo.
    goto RETURN_OR_QUIT
)
echo  [OK] Offline LLM : !OLLAMA_MODEL!
if "!NLLB_AVAILABLE!"=="true" (
    echo  [OK] NLLB        : installed ^(fills untranslated gaps^)
) else (
    echo  [WARN] NLLB not installed. LLM results will not have gap-filling.
)
echo  [INFO] Gemini is skipped. Primary engine: !OLLAMA_MODEL!
echo.

echo  Scanning for subtitle files ^(.srt^) in: %SCRIPT_DIR%
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
    goto RETURN_OR_QUIT
)

echo.
echo  Found: !SIDX! subtitle file(s^)
echo.

:LLM_CHOOSE_SRT
set "SCHOICE="
set /p SCHOICE="Enter file number (1-!SIDX!) or 'all': "

if /i "!SCHOICE!"=="all" goto LLM_TRANSLATE_ALL
if "!SCHOICE!"=="" goto LLM_CHOOSE_SRT
set /a STEST=!SCHOICE! 2>nul
if !STEST! LSS 1 goto LLM_INVALID_SRT
if !STEST! GTR !SIDX! goto LLM_INVALID_SRT

set "DETECT_FILE=!SFILE_%SCHOICE%!"
call :DETECT_SRT_LANG
call :CHOOSE_TARGET_LANG
echo.
call :RUN_TRANSLATE_OFFLINE_LLM "!SFILE_%SCHOICE%!"
goto LLM_TRANSLATE_DONE

:LLM_INVALID_SRT
echo  [!] Invalid input
goto LLM_CHOOSE_SRT

:LLM_TRANSLATE_ALL
set "DETECT_FILE=!SFILE_1!"
call :DETECT_SRT_LANG
call :CHOOSE_TARGET_LANG
echo.
for /l %%i in (1,1,!SIDX!) do (
    echo  [%%i/!SIDX!] Translating: !SFILE_%%i!
    call :RUN_TRANSLATE_OFFLINE_LLM "!SFILE_%%i!"
)

:LLM_TRANSLATE_DONE
echo.
echo ============================================================
echo   Offline LLM translation complete!
echo ============================================================
echo.
goto RETURN_OR_QUIT

:: ============================================================
:: MENU: GENERATE + TRANSLATE OFFLINE (LLM + NLLB)
:: ============================================================
:MENU_GT_LLM
cls
echo ============================================================
echo   GENERATE + TRANSLATE OFFLINE ^(LLM + NLLB^)
echo   Folder: %SCRIPT_DIR%
echo ============================================================
echo.

if "!OLLAMA_AVAILABLE!"=="false" (
    echo  [WARN] Ollama not found. Translation step will be skipped.
    echo  Run install.bat to set up Offline LLM.
    echo.
)
if "!OLLAMA_AVAILABLE!"=="true" (
    echo  [OK] Offline LLM : !OLLAMA_MODEL!
)
if "!NLLB_AVAILABLE!"=="true" (
    echo  [OK] NLLB        : installed ^(fills untranslated gaps^)
)
echo  [INFO] Gemini is skipped. Translation done offline via LLM + NLLB.
echo.

echo  Scanning for video files in: %SCRIPT_DIR%
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
    echo  [!IDX!] !REL!
)

if !IDX!==0 (
    echo  No video files found in this folder.
    goto RETURN_OR_QUIT
)

echo.
echo  Found: !IDX! video file(s^)
echo.

:GTL_CHOOSE_FILE
set "CHOICE="
set /p CHOICE="Enter file number (1-!IDX!) or 'all': "

if /i "!CHOICE!"=="all" goto GTL_CHOOSE_OPTIONS
if "!CHOICE!"=="" goto GTL_CHOOSE_FILE
set /a TEST_CHOICE=!CHOICE! 2>nul
if !TEST_CHOICE! LSS 1 goto GTL_INVALID
if !TEST_CHOICE! GTR !IDX! goto GTL_INVALID
goto GTL_CHOOSE_OPTIONS

:GTL_INVALID
echo  [!] Invalid input
goto GTL_CHOOSE_FILE

:GTL_CHOOSE_OPTIONS
set "VID_MIN=0"
set "VID_HHMM=unknown"
if /i not "!CHOICE!"=="all" (
    set "VIDEO_FILE=!FILE_%CHOICE%!"
    call :GET_VIDEO_DURATION
)
echo.
echo ============================================================
echo   TRANSCRIPTION OPTIONS
echo ============================================================
if /i not "!CHOICE!"=="all" if not "!VID_HHMM!"=="unknown" (
    echo  Duration : !VID_HHMM!
)
echo.
call :CHOOSE_MODEL
call :CHOOSE_LANGUAGE
call :CHOOSE_TARGET_LANG
echo.
echo ============================================================
echo   SUMMARY
echo ============================================================
echo   Model   : !MODEL!
if "!LANGUAGE!"=="" (
    echo   Language: Auto-detect
) else (
    echo   Language: !LANGUAGE!
)
echo   Device  : !WHISPER_DEVICE!
echo   Output  : .!OUTPUT_FORMAT!
echo   Translate to: !TARGET_LANG! ^(Offline LLM + NLLB^)
echo ============================================================
echo.
set /p CONFIRM="Continue? (Y/N): "
if /i not "!CONFIRM!"=="Y" goto GTL_CHOOSE_FILE

set "AUTO_TRANSLATE=true"
set "OFFLINE_LLM=true"

if /i "!CHOICE!"=="all" goto GTL_PROCESS_ALL

set "TARGET_FILE=!FILE_%CHOICE%!"
call :RUN_WHISPER "!TARGET_FILE!"
goto DONE

:GTL_PROCESS_ALL
for /l %%i in (1,1,!IDX!) do (
    echo.
    echo  [%%i/!IDX!] Processing: !FILE_%%i!
    call :RUN_WHISPER "!FILE_%%i!"
)
goto DONE

:: ============================================================
:: MENU: GENERATE + TRANSLATE (set & forget)
:: ============================================================
:MENU_GENERATE_TRANSLATE
cls
echo ============================================================
echo   GENERATE + TRANSLATE
echo   Folder: %SCRIPT_DIR%
echo ============================================================
echo.

if "!GEMINI_CMD!"=="" if "!NLLB_AVAILABLE!"=="false" (
    echo  [WARN] No translation engine found. Translation step will be skipped.
    echo  Install Gemini : npm install -g @google/gemini-cli
    echo  Install NLLB   : pip install transformers sentencepiece sacremoses
    echo.
)

:: Scan video files
echo  Scanning for video files in: %SCRIPT_DIR%
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
    echo  [!IDX!] !REL!
)

if !IDX!==0 (
    echo  No video files found in this folder.
    goto RETURN_OR_QUIT
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
:: Get video duration for single file selection
set "VID_MIN=0"
set "VID_HHMM=unknown"
if /i not "!CHOICE!"=="all" (
    set "VIDEO_FILE=!FILE_%CHOICE%!"
    call :GET_VIDEO_DURATION
)
echo.
echo ============================================================
echo   TRANSCRIPTION OPTIONS
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
echo   [1] tiny           - fastest, lower accuracy         ^| ~1GB  VRAM
echo   [2] base           - fast, decent accuracy           ^| ~1GB  VRAM
echo   [3] small          - balanced                        ^| ~2GB  VRAM
echo   [4] medium         - good accuracy        [DEFAULT]  ^| ~5GB  VRAM
echo   [5] large-v1       - high accuracy                   ^| ~10GB VRAM
echo   [6] large-v2       - better than v1                  ^| ~10GB VRAM
echo   [7] large-v3       - best official accuracy          ^| ~10GB VRAM
echo   [8] large-v3-turbo - fast, near v3 quality           ^| ~6GB  VRAM
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

:: Set SRT_LANG from source language for smart target exclusion
set "SRT_LANG=unknown"
if "!LANGUAGE!"=="Japanese"   set "SRT_LANG=ja"
if "!LANGUAGE!"=="Korean"     set "SRT_LANG=ko"
if "!LANGUAGE!"=="Chinese"    set "SRT_LANG=zh"
if "!LANGUAGE!"=="Cantonese"  set "SRT_LANG=zh"
if "!LANGUAGE!"=="Indonesian" set "SRT_LANG=id"
if "!LANGUAGE!"=="English"    set "SRT_LANG=en"

:: Ask target language upfront
call :CHOOSE_TARGET_LANG

:: Summary
echo.
echo ============================================================
echo   SUMMARY:
if /i "!CHOICE!"=="all" (
    echo   Files   : ALL !IDX! files
) else (
    echo   File    : !FILE_%CHOICE%!
)
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
echo   GENERATE SUBTITLE
echo   Folder: %SCRIPT_DIR%
echo ============================================================
echo.

:: Scan video files
echo  Scanning for video files in: %SCRIPT_DIR%
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
    echo  [!IDX!] !REL!
)

if !IDX!==0 (
    echo  No video files found in this folder.
    goto RETURN_OR_QUIT
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
:: Get video duration for single file selection
set "VID_MIN=0"
set "VID_HHMM=unknown"
if /i not "!CHOICE!"=="all" (
    set "VIDEO_FILE=!FILE_%CHOICE%!"
    call :GET_VIDEO_DURATION
)
echo.
echo ============================================================
echo   TRANSCRIPTION OPTIONS
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
echo   [1] tiny           - fastest, lower accuracy         ^| ~1GB  VRAM
echo   [2] base           - fast, decent accuracy           ^| ~1GB  VRAM
echo   [3] small          - balanced                        ^| ~2GB  VRAM
echo   [4] medium         - good accuracy        [DEFAULT]  ^| ~5GB  VRAM
echo   [5] large-v1       - high accuracy                   ^| ~10GB VRAM
echo   [6] large-v2       - better than v1                  ^| ~10GB VRAM
echo   [7] large-v3       - best official accuracy          ^| ~10GB VRAM
echo   [8] large-v3-turbo - fast, near v3 quality           ^| ~6GB  VRAM
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

:: Summary
echo.
echo ============================================================
echo   SUMMARY:
if /i "!CHOICE!"=="all" (
    echo   File    : ALL !IDX! files
) else (
    echo   File    : !FILE_%CHOICE%!
)
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
:: SUBROUTINE: Run Whisper on one file
:: ============================================================
:RUN_WHISPER
set "INPUT_FILE=%~1"
set "FILE_DIR=%~dp1"
set "FILE_DIR=%FILE_DIR:~0,-1%"

echo.
echo  Processing : %~nx1
echo  Output to  : %FILE_DIR%
echo  Model      : %MODEL%
echo  Device     : %WHISPER_DEVICE%
echo  --------------------------------------------------------

if "%LANGUAGE%"=="" (
    whisper "%INPUT_FILE%" --model %MODEL% --output_format %OUTPUT_FORMAT% --output_dir "%FILE_DIR%" --device %WHISPER_DEVICE% --condition_on_previous_text False --no_speech_threshold 0.6
) else (
    whisper "%INPUT_FILE%" --model %MODEL% --language %LANGUAGE% --output_format %OUTPUT_FORMAT% --output_dir "%FILE_DIR%" --device %WHISPER_DEVICE% --condition_on_previous_text False --no_speech_threshold 0.6
)

if errorlevel 1 (
    if not "%WHISPER_DEVICE%"=="cpu" (
        echo  [!] GPU failed, retrying with CPU...
        if "%LANGUAGE%"=="" (
            whisper "%INPUT_FILE%" --model %MODEL% --output_format %OUTPUT_FORMAT% --output_dir "%FILE_DIR%" --device cpu --condition_on_previous_text False --no_speech_threshold 0.6
        ) else (
            whisper "%INPUT_FILE%" --model %MODEL% --language %LANGUAGE% --output_format %OUTPUT_FORMAT% --output_dir "%FILE_DIR%" --device cpu --condition_on_previous_text False --no_speech_threshold 0.6
        )
    )
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
        if "!OFFLINE_LLM!"=="true" (
            call :RUN_TRANSLATE_OFFLINE_LLM "!SRT_FILE!"
        ) else if "!OFFLINE_TRANSLATE!"=="true" (
            call :RUN_TRANSLATE_OFFLINE "!SRT_FILE!"
        ) else (
            call :RUN_TRANSLATE "!SRT_FILE!"
        )
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
:: Input : DETECT_FILE (path to .srt)
:: Output: SRT_LANG   (en / id / ja / ko / zh / unknown)
:: ============================================================
:DETECT_SRT_LANG
set "SRT_LANG=unknown"
for /f "tokens=*" %%L in ('python "%~dp0translate_srt.py" --detect-lang "!DETECT_FILE!" 2^>nul') do set "SRT_LANG=%%L"
goto :eof

:: ============================================================
:: SUBROUTINE: Choose target language (excludes source lang)
:: Input : SRT_LANG
:: Output: TARGET_LANG, TARGET_SUFFIX
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

:: Map choice number back to language (re-run same conditions)
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
:: Gemini primary (+ NLLB auto gap-fill inside translate_srt.py)
:: Fallback to NLLB-only if Gemini not installed
:: Input : file path (arg), TARGET_LANG, GEMINI_CMD, NLLB_AVAILABLE
:: ============================================================
:RUN_TRANSLATE
set "TRANS_FILE=%~1"

if "!GEMINI_CMD!"=="" if "!NLLB_AVAILABLE!"=="false" (
    echo  [INFO] No translation engine available.
    echo  Install Gemini : npm install -g @google/gemini-cli
    echo  Install NLLB   : pip install transformers sentencepiece sacremoses
    goto :eof
)

if not "!GEMINI_CMD!"=="" (
    echo  [*] Translating with Gemini ^(+ NLLB for gaps^)...
    python "%~dp0translate_srt.py" "!TRANS_FILE!" "!GEMINI_CMD!" "gemini" "!TARGET_LANG!"
) else (
    echo  [*] Gemini not found. Translating with NLLB ^(offline^)...
    python "%~dp0translate_srt.py" "!TRANS_FILE!" "" "nllb" "!TARGET_LANG!"
)
goto :eof

:: ============================================================
:: SUBROUTINE: Run translation OFFLINE (NLLB only, no Gemini)
:: Input : file path (arg), TARGET_LANG, NLLB_AVAILABLE
:: ============================================================
:RUN_TRANSLATE_OFFLINE
set "TRANS_FILE=%~1"

if "!NLLB_AVAILABLE!"=="false" (
    echo  [INFO] NLLB not available. Skipping offline translation.
    echo  Install NLLB : pip install transformers sentencepiece sacremoses
    goto :eof
)

echo  [*] Translating offline with NLLB...
python "%~dp0translate_srt.py" "!TRANS_FILE!" "" "nllb" "!TARGET_LANG!"
goto :eof

:: ============================================================
:: SUBROUTINE: Run translation OFFLINE (LLM primary + NLLB gap-fill)
:: Input : file path (arg), TARGET_LANG, OLLAMA_MODEL, NLLB_AVAILABLE
:: ============================================================
:RUN_TRANSLATE_OFFLINE_LLM
set "TRANS_FILE=%~1"

if "!OLLAMA_AVAILABLE!"=="false" (
    echo  [INFO] Ollama not available. Skipping LLM translation.
    echo  Run install.bat to set up Offline LLM.
    goto :eof
)
if "!OLLAMA_MODEL!"=="none" (
    echo  [INFO] No Offline LLM model configured. Run install.bat.
    goto :eof
)

echo  [*] Translating offline with !OLLAMA_MODEL! ^(+ NLLB for gaps^)...
python "%~dp0translate_srt.py" "!TRANS_FILE!" "!OLLAMA_MODEL!" "ollama" "!TARGET_LANG!"
goto :eof

:: ============================================================
:: SUBROUTINE: Get video duration via ffprobe
:: Input : VIDEO_FILE (path to video)
:: Output: VID_MIN (total minutes), VID_HHMM (display string)
:: ============================================================
:GET_VIDEO_DURATION
set "VID_MIN=0"
set "VID_HHMM=unknown"
set "FFPROBE_DUR="
:: Use temp file to avoid quoting issues with paths containing spaces
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
goto RETURN_OR_QUIT

:RETURN_OR_QUIT
echo.
echo   [M] Back to main menu   [Q] Quit
echo.
set /p _RQCHOICE="Choose [M/Q, default=M]: "
if /i "!_RQCHOICE!"=="Q" exit /b 0
goto MAIN_LOOP
