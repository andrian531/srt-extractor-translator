@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul 2>&1

:: ============================================================
::  SUBTITLE TOOLS - MULTI ENGINE
::  Supports: Whisper / WhisperX / faster-whisper + stable-ts
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
set "SWAP_PRIMARY=false"
set "TRANSCRIBE_ENGINE="

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
python --version >nul 2>&1
if errorlevel 1 (
    echo  [ERROR] Python not found. Please run install.bat to reinstall.
    echo.
    pause
    exit /b 1
)

:: ============================================================
:: TRANSCRIPTION ENGINE DETECTION
:: ============================================================
set "WHISPER_INSTALLED=false"
set "WHISPERX_INSTALLED=false"
set "FASTER_WHISPER_INSTALLED=false"
set "STABLE_TS_INSTALLED=false"

where whisper >nul 2>&1
if not errorlevel 1 set "WHISPER_INSTALLED=true"

where whisperx >nul 2>&1
if not errorlevel 1 set "WHISPERX_INSTALLED=true"

python -c "import faster_whisper" >nul 2>&1
if not errorlevel 1 set "FASTER_WHISPER_INSTALLED=true"

python -c "import stable_whisper" >nul 2>&1
if not errorlevel 1 set "STABLE_TS_INSTALLED=true"

:: At least one transcription engine must be installed
if "!WHISPER_INSTALLED!"=="false" if "!WHISPERX_INSTALLED!"=="false" if "!FASTER_WHISPER_INSTALLED!"=="false" (
    echo  [ERROR] No transcription engine found.
    echo  Please run install.bat to install one of:
    echo    - Whisper ^(standard OpenAI^)
    echo    - WhisperX
    echo    - faster-whisper + stable-ts
    echo.
    pause
    exit /b 1
)

:: Build engine list label for main menu
set "ENG_LIST="
if "!WHISPER_INSTALLED!"=="true"       set "ENG_LIST=!ENG_LIST! Whisper"
if "!WHISPERX_INSTALLED!"=="true"      set "ENG_LIST=!ENG_LIST! WhisperX"
if "!FASTER_WHISPER_INSTALLED!"=="true" if "!STABLE_TS_INSTALLED!"=="true" (
    set "ENG_LIST=!ENG_LIST! faster-whisper+stable-ts"
)

:: ============================================================
:: GPU CHECK
:: ============================================================
set "CUDA_OK=false"
set "GPU_DEVICE=cpu"
set "GPU_NAME="
set "VRAM="
for /f "tokens=*" %%L in ('python "%~dp0check_gpu.py" verify 2^>nul') do (
    set "%%L"
)
set "WHISPER_DEVICE=!GPU_DEVICE!"
if "!WHISPER_DEVICE!"=="mps" set "WHISPER_DEVICE=cpu"

:: ============================================================
:: TRANSLATION ENGINE DETECTION (Gemini / NLLB / Ollama)
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
:: INIT ENGINE
:: ============================================================
REM call :SELECT_TRANSCRIPTION_ENGINE

:: ============================================================
:: MAIN MENU
:: ============================================================
:MAIN_LOOP
set "AUTO_TRANSLATE=false"
set "OFFLINE_TRANSLATE=false"
set "OFFLINE_LLM=false"
set "SWAP_PRIMARY=false"
cls
echo ============================================================
echo   SUBTITLE TOOLS - MULTI ENGINE
echo   Folder: %SCRIPT_DIR%
if not "!GPU_DEVICE!"=="cpu" (
    echo   GPU    : !GPU_NAME! ^(!VRAM!^)
) else (
    echo   GPU    : CPU mode
)
echo   Engine : !TRANSCRIBE_ENGINE!
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
set /p SCHOICE="Enter file number(s) (e.g. 1 or 1,3) or 'all': "

if /i "!SCHOICE!"=="all" goto TRANSLATE_ALL_FILES
if "!SCHOICE!"=="" goto CHOOSE_SRT
echo !SCHOICE! | findstr "," >nul
if not errorlevel 1 goto TRANSLATE_MULTI
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

:TRANSLATE_MULTI
set "DETECT_FILE=!SFILE_1!"
call :DETECT_SRT_LANG
call :CHOOSE_TARGET_LANG
echo.
for %%c in (!SCHOICE!) do (
    set /a CTEST=%%c 2>nul
    if !CTEST! GEQ 1 if !CTEST! LEQ !SIDX! (
        call set "_SFPATH=%%SFILE_!CTEST!%%"
        echo  [*] Translating: !_SFPATH!
        call :RUN_TRANSLATE "!_SFPATH!"
    )
)
goto TRANSLATE_DONE

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
set /p SCHOICE="Enter file number(s) (e.g. 1 or 1,3) or 'all': "

if /i "!SCHOICE!"=="all" goto OFFLINE_TRANSLATE_ALL
if "!SCHOICE!"=="" goto OFFLINE_CHOOSE_SRT
echo !SCHOICE! | findstr "," >nul
if not errorlevel 1 goto OFFLINE_TRANSLATE_MULTI
set /a STEST=!SCHOICE! 2>nul
if !STEST! LSS 1 goto OFFLINE_INVALID_SRT
if !STEST! GTR !SIDX! goto OFFLINE_INVALID_SRT

set "DETECT_FILE=!SFILE_%SCHOICE%!"
call :DETECT_SRT_LANG
call :CHOOSE_TARGET_LANG
echo.
call :RUN_TRANSLATE_OFFLINE "!SFILE_%SCHOICE%!"
goto OFFLINE_TRANSLATE_DONE

:OFFLINE_INVALID_SRT
echo  [!] Invalid input
goto OFFLINE_CHOOSE_SRT

:OFFLINE_TRANSLATE_MULTI
set "DETECT_FILE=!SFILE_1!"
call :DETECT_SRT_LANG
call :CHOOSE_TARGET_LANG
echo.
for %%c in (!SCHOICE!) do (
    set /a CTEST=%%c 2>nul
    if !CTEST! GEQ 1 if !CTEST! LEQ !SIDX! (
        call set "_SFPATH=%%SFILE_!CTEST!%%"
        echo  [*] Translating: !_SFPATH!
        call :RUN_TRANSLATE_OFFLINE "!_SFPATH!"
    )
)
goto OFFLINE_TRANSLATE_DONE

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
call :CHOOSE_OLLAMA_MODEL
if "!OLLAMA_MODEL!"=="none" (
    echo  [ERROR] No Ollama models found. Pull a model first: ollama pull qwen2.5:7b
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
echo  Found: !SIDX! subtitle file(s)
echo.

:LLM_CHOOSE_SRT
set "SCHOICE="
set /p SCHOICE="Enter file number(s) (e.g. 1 or 1,3) or 'all': "

if /i "!SCHOICE!"=="all" goto LLM_TRANSLATE_ALL
if "!SCHOICE!"=="" goto LLM_CHOOSE_SRT
echo !SCHOICE! | findstr "," >nul
if not errorlevel 1 goto LLM_TRANSLATE_MULTI
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

:LLM_TRANSLATE_MULTI
set "DETECT_FILE=!SFILE_1!"
call :DETECT_SRT_LANG
call :CHOOSE_TARGET_LANG
echo.
for %%c in (!SCHOICE!) do (
    set /a CTEST=%%c 2>nul
    if !CTEST! GEQ 1 if !CTEST! LEQ !SIDX! (
        call set "_SFPATH=%%SFILE_!CTEST!%%"
        echo  [*] Translating: !_SFPATH!
        call :RUN_TRANSLATE_OFFLINE_LLM "!_SFPATH!"
    )
)
goto LLM_TRANSLATE_DONE

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
:: MENU: GENERATE SUBTITLE
:: ============================================================
:MENU_GENERATE
cls
echo ============================================================
echo   GENERATE SUBTITLE
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
    goto RETURN_OR_QUIT
)

echo.
echo  Found: !IDX! video file(s)
echo.

:CHOOSE_FILE
set "CHOICE="
set /p CHOICE="Enter file number(s) (e.g. 1 or 1,3) or 'all': "

if /i "!CHOICE!"=="all" goto CHOOSE_OPTIONS
if "!CHOICE!"=="" goto CHOOSE_FILE
echo !CHOICE! | findstr "," >nul
if not errorlevel 1 goto CHOOSE_OPTIONS
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
set "IS_MULTI=false"
echo !CHOICE! | findstr "," >nul
if not errorlevel 1 set "IS_MULTI=true"
if /i not "!CHOICE!"=="all" if "!IS_MULTI!"=="false" (
    set "VIDEO_FILE=!FILE_%CHOICE%!"
    call :GET_VIDEO_DURATION
)
echo.
if /i not "!CHOICE!"=="all" if not "!VID_HHMM!"=="unknown" (
    echo  Duration : !VID_HHMM!
    echo.
)
echo ============================================================
echo   STEP 1/2 - SELECT MODEL
echo ============================================================
echo.
call :SELECT_MODEL
echo.
echo ============================================================
echo   STEP 2/2 - LANGUAGE ^& FORMAT
echo ============================================================
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
if not "!TRANSCRIBE_ENGINE!"=="faster-whisper" (
    echo   [4] all  - generate all formats
)
echo.
set /p FMT_CHOICE="Choose format [1-4, default=1]: "

if "!FMT_CHOICE!"=="1" set OUTPUT_FORMAT=srt
if "!FMT_CHOICE!"=="2" set OUTPUT_FORMAT=vtt
if "!FMT_CHOICE!"=="3" set OUTPUT_FORMAT=txt
if "!FMT_CHOICE!"=="4" set OUTPUT_FORMAT=all
if "!FMT_CHOICE!"==""  set OUTPUT_FORMAT=srt
if "!TRANSCRIBE_ENGINE!"=="faster-whisper" if "!OUTPUT_FORMAT!"=="all" set OUTPUT_FORMAT=srt

echo.
echo ============================================================
echo   SUMMARY:
if /i "!CHOICE!"=="all" (
    echo   Files   : ALL !IDX! files
) else if "!IS_MULTI!"=="true" (
    echo   Files   : !CHOICE!
) else (
    echo   File    : !FILE_%CHOICE%!
)
echo   Engine  : !TRANSCRIBE_ENGINE!
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
if "!IS_MULTI!"=="true" goto PROCESS_MULTI

set "TARGET_FILE=!FILE_%CHOICE%!"
call :RUN_WHISPER "!TARGET_FILE!"
goto DONE

:PROCESS_MULTI
for %%c in (!CHOICE!) do (
    set /a CTEST=%%c 2>nul
    if !CTEST! GEQ 1 if !CTEST! LEQ !IDX! (
        call set "_FPATH=%%FILE_!CTEST!%%"
        echo.
        echo  [*] Processing: !_FPATH!
        call :RUN_WHISPER "!_FPATH!"
    )
)
goto DONE

:PROCESS_ALL
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
    goto RETURN_OR_QUIT
)

echo.
echo  Found: !IDX! video file(s)
echo.

:GT_CHOOSE_FILE
set "CHOICE="
set /p CHOICE="Enter file number(s) (e.g. 1 or 1,3) or 'all': "

if /i "!CHOICE!"=="all" goto GT_CHOOSE_OPTIONS
if "!CHOICE!"=="" goto GT_CHOOSE_FILE
echo !CHOICE! | findstr "," >nul
if not errorlevel 1 goto GT_CHOOSE_OPTIONS
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
set "IS_MULTI=false"
echo !CHOICE! | findstr "," >nul
if not errorlevel 1 set "IS_MULTI=true"
if /i not "!CHOICE!"=="all" if "!IS_MULTI!"=="false" (
    set "VIDEO_FILE=!FILE_%CHOICE%!"
    call :GET_VIDEO_DURATION
)
echo.
if /i not "!CHOICE!"=="all" if not "!VID_HHMM!"=="unknown" (
    echo  Duration : !VID_HHMM!
    echo.
)
echo ============================================================
echo   STEP 1/2 - SELECT MODEL
echo ============================================================
echo.
call :SELECT_MODEL
echo.
echo ============================================================
echo   STEP 2/2 - LANGUAGE ^& FORMAT
echo ============================================================
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
if not "!TRANSCRIBE_ENGINE!"=="faster-whisper" (
    echo   [4] all  - generate all formats
)
echo.
set /p FMT_CHOICE="Choose format [1-4, default=1]: "

if "!FMT_CHOICE!"=="1" set OUTPUT_FORMAT=srt
if "!FMT_CHOICE!"=="2" set OUTPUT_FORMAT=vtt
if "!FMT_CHOICE!"=="3" set OUTPUT_FORMAT=txt
if "!FMT_CHOICE!"=="4" set OUTPUT_FORMAT=all
if "!FMT_CHOICE!"==""  set OUTPUT_FORMAT=srt
if "!TRANSCRIBE_ENGINE!"=="faster-whisper" if "!OUTPUT_FORMAT!"=="all" set OUTPUT_FORMAT=srt

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
) else if "!IS_MULTI!"=="true" (
    echo   Files   : !CHOICE!
) else (
    echo   File    : !FILE_%CHOICE%!
)
echo   Engine  : !TRANSCRIBE_ENGINE!
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
set "SWAP_PRIMARY=swap"

if /i "!CHOICE!"=="all" goto GT_PROCESS_ALL
if "!IS_MULTI!"=="true" goto GT_PROCESS_MULTI

set "TARGET_FILE=!FILE_%CHOICE%!"
call :RUN_WHISPER "!TARGET_FILE!"
goto DONE

:GT_PROCESS_MULTI
for %%c in (!CHOICE!) do (
    set /a CTEST=%%c 2>nul
    if !CTEST! GEQ 1 if !CTEST! LEQ !IDX! (
        call set "_FPATH=%%FILE_!CTEST!%%"
        echo.
        echo  [*] Processing: !_FPATH!
        call :RUN_WHISPER "!_FPATH!"
    )
)
goto DONE

:GT_PROCESS_ALL
for /l %%i in (1,1,!IDX!) do (
    echo.
    echo  [%%i/!IDX!] Processing: !FILE_%%i!
    call :RUN_WHISPER "!FILE_%%i!"
)
goto DONE

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
    goto RETURN_OR_QUIT
)

echo.
echo  Found: !IDX! video file(s)
echo.

:GTO_CHOOSE_FILE
set "CHOICE="
set /p CHOICE="Enter file number(s) (e.g. 1 or 1,3) or 'all': "

if /i "!CHOICE!"=="all" goto GTO_CHOOSE_OPTIONS
if "!CHOICE!"=="" goto GTO_CHOOSE_FILE
echo !CHOICE! | findstr "," >nul
if not errorlevel 1 goto GTO_CHOOSE_OPTIONS
set /a TEST_CHOICE=!CHOICE! 2>nul
if !TEST_CHOICE! LSS 1 goto GTO_INVALID_CHOICE
if !TEST_CHOICE! GTR !IDX! goto GTO_INVALID_CHOICE
goto GTO_CHOOSE_OPTIONS

:GTO_INVALID_CHOICE
echo  [!] Invalid input
goto GTO_CHOOSE_FILE

:GTO_CHOOSE_OPTIONS
set "VID_MIN=0"
set "VID_HHMM=unknown"
set "IS_MULTI=false"
echo !CHOICE! | findstr "," >nul
if not errorlevel 1 set "IS_MULTI=true"
if /i not "!CHOICE!"=="all" if "!IS_MULTI!"=="false" (
    set "VIDEO_FILE=!FILE_%CHOICE%!"
    call :GET_VIDEO_DURATION
)
echo.
if /i not "!CHOICE!"=="all" if not "!VID_HHMM!"=="unknown" (
    echo  Duration : !VID_HHMM!
    echo.
)
echo ============================================================
echo   STEP 1/2 - SELECT MODEL
echo ============================================================
echo.
call :SELECT_MODEL
echo.
echo ============================================================
echo   STEP 2/2 - LANGUAGE ^& FORMAT
echo ============================================================
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
if not "!TRANSCRIBE_ENGINE!"=="faster-whisper" (
    echo   [4] all  - generate all formats
)
echo.
set /p FMT_CHOICE="Choose format [1-4, default=1]: "

if "!FMT_CHOICE!"=="1" set OUTPUT_FORMAT=srt
if "!FMT_CHOICE!"=="2" set OUTPUT_FORMAT=vtt
if "!FMT_CHOICE!"=="3" set OUTPUT_FORMAT=txt
if "!FMT_CHOICE!"=="4" set OUTPUT_FORMAT=all
if "!FMT_CHOICE!"==""  set OUTPUT_FORMAT=srt
if "!TRANSCRIBE_ENGINE!"=="faster-whisper" if "!OUTPUT_FORMAT!"=="all" set OUTPUT_FORMAT=srt

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
) else if "!IS_MULTI!"=="true" (
    echo   Files   : !CHOICE!
) else (
    echo   File    : !FILE_%CHOICE%!
)
echo   Engine  : !TRANSCRIBE_ENGINE!
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
set "SWAP_PRIMARY=swap"

if /i "!CHOICE!"=="all" goto GTO_PROCESS_ALL
if "!IS_MULTI!"=="true" goto GTO_PROCESS_MULTI

set "TARGET_FILE=!FILE_%CHOICE%!"
call :RUN_WHISPER "!TARGET_FILE!"
goto DONE

:GTO_PROCESS_MULTI
for %%c in (!CHOICE!) do (
    set /a CTEST=%%c 2>nul
    if !CTEST! GEQ 1 if !CTEST! LEQ !IDX! (
        call set "_FPATH=%%FILE_!CTEST!%%"
        echo.
        echo  [*] Processing: !_FPATH!
        call :RUN_WHISPER "!_FPATH!"
    )
)
goto DONE

:GTO_PROCESS_ALL
for /l %%i in (1,1,!IDX!) do (
    echo.
    echo  [%%i/!IDX!] Processing: !FILE_%%i!
    call :RUN_WHISPER "!FILE_%%i!"
)
goto DONE

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
    call :CHOOSE_OLLAMA_MODEL
    if "!OLLAMA_MODEL!"=="none" (
        echo  [WARN] No Ollama models found. Pull a model first: ollama pull qwen2.5:7b
        echo.
    ) else (
        echo  [OK] Offline LLM : !OLLAMA_MODEL!
    )
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
echo  Found: !IDX! video file(s)
echo.

:GTL_CHOOSE_FILE
set "CHOICE="
set /p CHOICE="Enter file number(s) (e.g. 1 or 1,3) or 'all': "

if /i "!CHOICE!"=="all" goto GTL_CHOOSE_OPTIONS
if "!CHOICE!"=="" goto GTL_CHOOSE_FILE
echo !CHOICE! | findstr "," >nul
if not errorlevel 1 goto GTL_CHOOSE_OPTIONS
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
set "IS_MULTI=false"
echo !CHOICE! | findstr "," >nul
if not errorlevel 1 set "IS_MULTI=true"
if /i not "!CHOICE!"=="all" if "!IS_MULTI!"=="false" (
    set "VIDEO_FILE=!FILE_%CHOICE%!"
    call :GET_VIDEO_DURATION
)
echo.
if /i not "!CHOICE!"=="all" if not "!VID_HHMM!"=="unknown" (
    echo  Duration : !VID_HHMM!
    echo.
)
echo ============================================================
echo   STEP 1/2 - SELECT MODEL
echo ============================================================
echo.
call :SELECT_MODEL
echo.
echo ============================================================
echo   STEP 2/2 - LANGUAGE ^& FORMAT
echo ============================================================
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
if not "!TRANSCRIBE_ENGINE!"=="faster-whisper" (
    echo   [4] all  - generate all formats
)
echo.
set /p FMT_CHOICE="Choose format [1-4, default=1]: "

if "!FMT_CHOICE!"=="1" set OUTPUT_FORMAT=srt
if "!FMT_CHOICE!"=="2" set OUTPUT_FORMAT=vtt
if "!FMT_CHOICE!"=="3" set OUTPUT_FORMAT=txt
if "!FMT_CHOICE!"=="4" set OUTPUT_FORMAT=all
if "!FMT_CHOICE!"==""  set OUTPUT_FORMAT=srt
if "!TRANSCRIBE_ENGINE!"=="faster-whisper" if "!OUTPUT_FORMAT!"=="all" set OUTPUT_FORMAT=srt

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
) else if "!IS_MULTI!"=="true" (
    echo   Files   : !CHOICE!
) else (
    echo   File    : !FILE_%CHOICE%!
)
echo   Engine  : !TRANSCRIBE_ENGINE!
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
set "SWAP_PRIMARY=swap"

if /i "!CHOICE!"=="all" goto GTL_PROCESS_ALL
if "!IS_MULTI!"=="true" goto GTL_PROCESS_MULTI

set "TARGET_FILE=!FILE_%CHOICE%!"
call :RUN_WHISPER "!TARGET_FILE!"
goto DONE

:GTL_PROCESS_MULTI
for %%c in (!CHOICE!) do (
    set /a CTEST=%%c 2>nul
    if !CTEST! GEQ 1 if !CTEST! LEQ !IDX! (
        call set "_FPATH=%%FILE_!CTEST!%%"
        echo.
        echo  [*] Processing: !_FPATH!
        call :RUN_WHISPER "!_FPATH!"
    )
)
goto DONE

:GTL_PROCESS_ALL
for /l %%i in (1,1,!IDX!) do (
    echo.
    echo  [%%i/!IDX!] Processing: !FILE_%%i!
    call :RUN_WHISPER "!FILE_%%i!"
)
goto DONE

:: ============================================================
:: SUBROUTINE: Select transcription engine
:: Sets: TRANSCRIBE_ENGINE
:: ============================================================
:SELECT_TRANSCRIPTION_ENGINE
if exist "%SCRIPT_DIR%\.engine" (
    for /f "usebackq tokens=*" %%E in ("%SCRIPT_DIR%\.engine") do set "TRANSCRIBE_ENGINE=%%E"
    
    REM Verify the saved engine is actually installed
    set "ENG_OK=false"
    if "!TRANSCRIBE_ENGINE!"=="whisper" if "!WHISPER_INSTALLED!"=="true" set "ENG_OK=true"
    if "!TRANSCRIBE_ENGINE!"=="whisperx" if "!WHISPERX_INSTALLED!"=="true" set "ENG_OK=true"
    if "!TRANSCRIBE_ENGINE!"=="faster-whisper" if "!FASTER_WHISPER_INSTALLED!"=="true" set "ENG_OK=true"
    
    if "!ENG_OK!"=="true" (
        exit /b 0
    ) else (
        echo  [WARN] Saved engine '!TRANSCRIBE_ENGINE!' is not installed. Please select again.
    )
)

set "TE_COUNT=3"
set "TE_1=whisper"
set "TE_2=whisperx"
set "TE_3=faster-whisper"

set "TE_REC=1"
if "!FASTER_WHISPER_INSTALLED!"=="true" set "TE_REC=3"
if "!TE_REC!"=="1" if "!WHISPERX_INSTALLED!"=="true" set "TE_REC=2"
set "TE_DEFAULT=!TE_REC!"

echo  Available transcription engines:
echo.
for /l %%i in (1,1,3) do (
    set "TE_LABEL="
    set "TE_STATUS=[Not detected]"
    if "!TE_%%i!"=="whisper" (
        set "TE_LABEL=slower, most accurate"
        if "!WHISPER_INSTALLED!"=="true" set "TE_STATUS=[Installed]"
    )
    if "!TE_%%i!"=="whisperx" (
        set "TE_LABEL=fast, timestamps may drift"
        if "!WHISPERX_INSTALLED!"=="true" set "TE_STATUS=[Installed]"
    )
    if "!TE_%%i!"=="faster-whisper" (
        set "TE_LABEL=fast, better timestamps (recommended)"
        if "!FASTER_WHISPER_INSTALLED!"=="true" set "TE_STATUS=[Installed]"
    )
    
    set "DEF_TXT="
    if "%%i"=="!TE_REC!" set "DEF_TXT= *DEFAULT*"
    
    REM Only show if installed
    if "!TE_STATUS!"=="[Installed]" (
        echo   [%%i] !TE_%%i! - !TE_LABEL!!DEF_TXT!
    )
)
echo.

:ASK_ENGINE
set /p TE_CHOICE="Choose engine [default=!TE_DEFAULT!]: "
if "!TE_CHOICE!"=="" set "TE_CHOICE=!TE_DEFAULT!"
set /a TE_TEST=!TE_CHOICE! 2>nul

if !TE_TEST! LSS 1 goto INVALID_ENG
if !TE_TEST! GTR 3 goto INVALID_ENG

set "TRANSCRIBE_ENGINE=!TE_%TE_CHOICE%!"

REM Validate selection
set "SEL_OK=false"
if "!TRANSCRIBE_ENGINE!"=="whisper" if "!WHISPER_INSTALLED!"=="true" set "SEL_OK=true"
if "!TRANSCRIBE_ENGINE!"=="whisperx" if "!WHISPERX_INSTALLED!"=="true" set "SEL_OK=true"
if "!TRANSCRIBE_ENGINE!"=="faster-whisper" if "!FASTER_WHISPER_INSTALLED!"=="true" set "SEL_OK=true"

if "!SEL_OK!"=="false" (
    echo  [!] Engine not installed! Please choose an installed engine.
    goto ASK_ENGINE
)

echo !TRANSCRIBE_ENGINE!> "%SCRIPT_DIR%\.engine"
echo  Selected: !TRANSCRIBE_ENGINE! ^(Saved to .engine^)
goto :eof

:INVALID_ENG
echo  [!] Invalid choice
goto ASK_ENGINE

:: ============================================================
:: SUBROUTINE: Select model (adapts cache path to engine)
:: Sets: MODEL
:: ============================================================
:SELECT_MODEL
set "WX_CACHE=%USERPROFILE%\.cache\huggingface\hub"
set "W_CACHE=%USERPROFILE%\.cache\whisper"
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
    if "!TRANSCRIBE_ENGINE!"=="whisper" (
        if exist "!W_CACHE!\!M%%i!.pt" set "ST_%%i=[downloaded]"
    ) else (
        if exist "!WX_CACHE!\models--Systran--faster-whisper-!M%%i!\" set "ST_%%i=[downloaded]"
    )
)

if "!CUDA_OK!"=="true" (
    if !VID_MIN! GTR 90 echo  [TIP] Long video — large-v3-turbo for speed, large-v3 for max accuracy
) else (
    if !VID_MIN! GTR 60 echo  [TIP] Long video on CPU — small for speed, medium for quality
)

echo  Select model  ^(engine: !TRANSCRIBE_ENGINE!^):
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
goto :eof

:: ============================================================
:: SUBROUTINE: Run transcription on one file
:: Dispatches to correct engine based on TRANSCRIBE_ENGINE
:: ============================================================
:RUN_WHISPER
set "INPUT_FILE=%~1"
set "FILE_DIR=%~dp1"
set "FILE_DIR=%FILE_DIR:~0,-1%"

echo.
echo  Processing : %~nx1
echo  Output to  : %FILE_DIR%
echo  Engine     : %TRANSCRIBE_ENGINE%
echo  Model      : %MODEL%
echo  Device     : %WHISPER_DEVICE%
echo  --------------------------------------------------------

setlocal DisableDelayedExpansion
set "RAW_FILE=%~1"
setlocal EnableDelayedExpansion

if "%TRANSCRIBE_ENGINE%"=="whisper" (
    if "%LANGUAGE%"=="" (
        whisper "!RAW_FILE!" --model %MODEL% --output_format %OUTPUT_FORMAT% --output_dir "%FILE_DIR%" --device %WHISPER_DEVICE% --max_line_width 35 --max_line_count 2
    ) else (
        whisper "!RAW_FILE!" --model %MODEL% --language %LANGUAGE% --output_format %OUTPUT_FORMAT% --output_dir "%FILE_DIR%" --device %WHISPER_DEVICE% --max_line_width 35 --max_line_count 2
    )
) else if "%TRANSCRIBE_ENGINE%"=="faster-whisper" (
    REM stable-ts uses -o <outfile> - construct output path based on format
    set "ST_OUT=%FILE_DIR%\%~n1.%OUTPUT_FORMAT%"
    if "%OUTPUT_FORMAT%"=="all" set "ST_OUT=%FILE_DIR%\%~n1.srt"
    if "%LANGUAGE%"=="" (
        stable-ts "!RAW_FILE!" -o "!ST_OUT!" --model %MODEL% --device %WHISPER_DEVICE% --backend faster-whisper --max_line_count 2 --max_line_width 35 --no_speech_threshold 0.45 --suppress_silence 1 --condition_on_previous_text false
    ) else (
        stable-ts "!RAW_FILE!" -o "!ST_OUT!" --model %MODEL% --language %LANGUAGE% --device %WHISPER_DEVICE% --backend faster-whisper --max_line_count 2 --max_line_width 35 --no_speech_threshold 0.45 --suppress_silence 1 --condition_on_previous_text false
    )
) else (
    if "%LANGUAGE%"=="" (
        whisperx "!RAW_FILE!" --model %MODEL% --output_format %OUTPUT_FORMAT% --output_dir "%FILE_DIR%" --device %WHISPER_DEVICE% --max_line_width 35 --max_line_count 2
    ) else (
        whisperx "!RAW_FILE!" --model %MODEL% --language %LANGUAGE% --output_format %OUTPUT_FORMAT% --output_dir "%FILE_DIR%" --device %WHISPER_DEVICE% --max_line_width 35 --max_line_count 2
    )
)

if errorlevel 1 (
    if not "%WHISPER_DEVICE%"=="cpu" (
        echo  [!] GPU failed, retrying with CPU...
        if "%TRANSCRIBE_ENGINE%"=="whisper" (
            if "%LANGUAGE%"=="" (
                whisper "!RAW_FILE!" --model %MODEL% --output_format %OUTPUT_FORMAT% --output_dir "%FILE_DIR%" --device cpu --max_line_width 35 --max_line_count 2
            ) else (
                whisper "!RAW_FILE!" --model %MODEL% --language %LANGUAGE% --output_format %OUTPUT_FORMAT% --output_dir "%FILE_DIR%" --device cpu --max_line_width 35 --max_line_count 2
            )
        ) else if "%TRANSCRIBE_ENGINE%"=="faster-whisper" (
            set "ST_OUT=%FILE_DIR%\%~n1.%OUTPUT_FORMAT%"
            if "%OUTPUT_FORMAT%"=="all" set "ST_OUT=%FILE_DIR%\%~n1.srt"
            if "%LANGUAGE%"=="" (
                stable-ts "!RAW_FILE!" -o "!ST_OUT!" --model %MODEL% --device cpu --backend faster-whisper --max_line_count 2 --max_line_width 35 --no_speech_threshold 0.45 --suppress_silence 1 --condition_on_previous_text false
            ) else (
                stable-ts "!RAW_FILE!" -o "!ST_OUT!" --model %MODEL% --language %LANGUAGE% --device cpu --backend faster-whisper --max_line_count 2 --max_line_width 35 --no_speech_threshold 0.45 --suppress_silence 1 --condition_on_previous_text false
            )
        ) else (
            if "%LANGUAGE%"=="" (
                whisperx "!RAW_FILE!" --model %MODEL% --output_format %OUTPUT_FORMAT% --output_dir "%FILE_DIR%" --device cpu --max_line_width 35 --max_line_count 2
            ) else (
                whisperx "!RAW_FILE!" --model %MODEL% --language %LANGUAGE% --output_format %OUTPUT_FORMAT% --output_dir "%FILE_DIR%" --device cpu --max_line_width 35 --max_line_count 2
            )
        )
    ) else (
        echo  [ERROR] Failed to process: %~nx1
        endlocal
        endlocal
        goto :eof
    )
)

echo  [DONE] Subtitle saved to: %FILE_DIR%

set "SRT_FILE=%FILE_DIR%\%~n1.srt"
if exist "!SRT_FILE!" (
    echo.
    echo  --------------------------------------------------------
    echo  [*] Running auto-cleanup (fix overlaps + merge short segments)...
    call :RUN_CLEANUP "!SRT_FILE!"
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
        echo  [INFO] Translation skipped. Use menu [2] to translate later.
    )
)

endlocal
endlocal
goto :eof

:: ============================================================
:: SUBROUTINE: Auto-cleanup SRT (fix overlaps + merge short segs)
:: Input : file path (arg)
:: Overwrites the original file in-place
:: ============================================================
:RUN_CLEANUP
set "CLEAN_FILE=%~1"
if not exist "!CLEAN_FILE!" goto :eof
python "%~dp0cleanup_srt.py" "!CLEAN_FILE!"
if errorlevel 1 (
    echo  [WARN] Cleanup skipped (error in cleanup_srt.py)
    goto :eof
)
set "CLEAN_OUT=%~dpn1_clean%~x1"
if exist "!CLEAN_OUT!" (
    move /y "!CLEAN_OUT!" "!CLEAN_FILE!" >nul
    echo  [OK]  Cleanup applied in-place: %~nx1
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
:: SUBROUTINE: Run translation (Gemini + NLLB)
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
    python "%~dp0translate_srt.py" "!TRANS_FILE!" "!GEMINI_CMD!" "gemini" "!TARGET_LANG!" "!SWAP_PRIMARY!"
) else (
    echo  [*] Gemini not found. Translating with NLLB ^(offline^)...
    python "%~dp0translate_srt.py" "!TRANS_FILE!" "" "nllb" "!TARGET_LANG!" "!SWAP_PRIMARY!"
)
goto :eof

:: ============================================================
:: SUBROUTINE: Run translation OFFLINE (NLLB only)
:: ============================================================
:RUN_TRANSLATE_OFFLINE
set "TRANS_FILE=%~1"

if "!NLLB_AVAILABLE!"=="false" (
    echo  [INFO] NLLB not available. Skipping offline translation.
    echo  Install NLLB : pip install transformers sentencepiece sacremoses
    goto :eof
)

echo  [*] Translating offline with NLLB...
python "%~dp0translate_srt.py" "!TRANS_FILE!" "" "nllb" "!TARGET_LANG!" "!SWAP_PRIMARY!"
goto :eof

:: ============================================================
:: SUBROUTINE: Run translation OFFLINE (LLM primary + NLLB)
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
python "%~dp0translate_srt.py" "!TRANS_FILE!" "!OLLAMA_MODEL!" "ollama" "!TARGET_LANG!" "!SWAP_PRIMARY!"
goto :eof

:: ============================================================
:: SUBROUTINE: Choose Ollama model from installed models
:: ============================================================
:CHOOSE_OLLAMA_MODEL
set "OLL_IDX=0"
for /f "skip=1 tokens=1" %%m in ('ollama list 2^>nul') do (
    if not "%%m"=="" (
        set /a OLL_IDX+=1
        set "OLL_M_!OLL_IDX!=%%m"
    )
)
if !OLL_IDX!==0 (
    set "OLLAMA_MODEL=none"
    goto :eof
)
if !OLL_IDX!==1 (
    set "OLLAMA_MODEL=!OLL_M_1!"
    goto :eof
)
echo.
echo  Select Ollama model:
echo.
for /l %%i in (1,1,!OLL_IDX!) do (
    echo   [%%i] !OLL_M_%%i!
)
echo.
:OLL_SEL_PROMPT
set "OLL_CHOICE="
set /p OLL_CHOICE="Choose model [1-!OLL_IDX!]: "
if "!OLL_CHOICE!"=="" goto OLL_SEL_PROMPT
set /a OLL_TEST=!OLL_CHOICE! 2>nul
if !OLL_TEST! LSS 1 goto OLL_SEL_INVALID
if !OLL_TEST! GTR !OLL_IDX! goto OLL_SEL_INVALID
set "OLLAMA_MODEL=!OLL_M_%OLL_CHOICE%!"
goto :eof
:OLL_SEL_INVALID
echo  [!] Invalid choice
goto OLL_SEL_PROMPT

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
goto RETURN_OR_QUIT

:RETURN_OR_QUIT
echo.
echo   [M] Back to main menu   [Q] Quit
echo.
set /p _RQCHOICE="Choose [M/Q, default=M]: "
if /i "!_RQCHOICE!"=="Q" exit /b 0
goto MAIN_LOOP
