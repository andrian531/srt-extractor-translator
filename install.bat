@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul 2>&1

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

:: Read current installed engine (if any)
set "CURRENT_ENGINE=none"
if exist "%SCRIPT_DIR%\.engine" (
    for /f "usebackq tokens=*" %%E in ("%SCRIPT_DIR%\.engine") do set "CURRENT_ENGINE=%%E"
)

echo ============================================================
echo   WHISPER SUBTITLE TOOLS - INSTALLER
if "!CURRENT_ENGINE!"=="none" (
    echo   Status  : not installed
) else (
    echo   Status  : installed ^(!CURRENT_ENGINE!^)
)
echo   To uninstall, run: uninstall.bat
echo ============================================================
echo.

:INSTALL_START
:: ============================================================
:: STEP 1: Python
:: ============================================================
echo [1/5] Checking Python...
python --version >nul 2>&1
if errorlevel 1 (
    echo  [ERROR] Python not found!
    echo  Download Python at: https://www.python.org/downloads/
    echo  Make sure to check "Add Python to PATH" during installation.
    goto INSTALL_FAILED
)
for /f "tokens=*" %%v in ('python --version 2^>^&1') do echo  [OK] %%v

:: ============================================================
:: STEP 2: ffmpeg
:: ============================================================
echo.
echo [2/5] Checking ffmpeg...
ffmpeg -version >nul 2>&1
if errorlevel 1 (
    echo  [!] ffmpeg not found. Trying to install via winget...
    winget install --id Gyan.FFmpeg -e --silent >nul 2>&1
    if errorlevel 1 (
        echo  [!] winget failed. Trying via Chocolatey...
        choco install ffmpeg -y >nul 2>&1
    )
    ffmpeg -version >nul 2>&1
    if errorlevel 1 (
        echo  [ERROR] Could not install ffmpeg automatically.
        echo  Manual install: https://www.gyan.dev/ffmpeg/builds/
        echo  Extract and add the "bin" folder to your System PATH.
        goto INSTALL_FAILED
    )
    echo  [OK] ffmpeg installed successfully
) else (
    for /f "tokens=1,2,3" %%a in ('ffmpeg -version 2^>^&1 ^| findstr "ffmpeg version"') do echo  [OK] %%a %%b %%c
)

:: ============================================================
:: STEP 3: Detect GPU, choose engine
:: ============================================================
echo.
echo [3/5] Detecting GPU...

set "GPU_VENDOR=unknown"
set "CUDA_VERSION=none"
set "TORCH_TAG=cpu"
set "TORCH_URL=none"
set "CUDA_OK=false"
set "TORCH_INSTALLED=false"
set "GPU_NAME=none"
set "VRAM="
set "RECOMMENDED_MODEL=medium"
set "RECOMMENDED_REASON=default"
set "NLLB_RECOMMENDED=600M"
set "NLLB_RECOMMENDED_REASON=default"

for /f "tokens=*" %%L in ('python "%~dp0check_gpu.py" detect 2^>nul') do (
    set "%%L"
)
for /f "tokens=*" %%L in ('python "%~dp0check_gpu.py" verify 2^>nul') do (
    set "%%L"
)

if "!CUDA_OK!"=="true" (
    echo  [OK] GPU: !GPU_NAME! ^(!VRAM!^) — CUDA active
) else (
    if not "!GPU_NAME!"=="none" (
        echo  [!] GPU detected ^(!GPU_NAME!^) but CUDA not active
    ) else (
        echo  [!] No GPU detected — CPU mode
    )
)
echo.

echo ============================================================
echo   Choose transcription engine:
echo ============================================================
echo.

set "WX_LABEL=   "
set "W_LABEL= "
if "!CURRENT_ENGINE!"=="whisperx" set "WX_LABEL=[installed]"
if "!CURRENT_ENGINE!"=="whisper"  set "W_LABEL=[installed]"

echo   [1] WhisperX  !WX_LABEL!
echo       + Faster (CTranslate2 backend, up to 4-8x faster)
echo       + More precise timestamps (word-level alignment)
echo       + Better transcription accuracy
echo       - Larger model size (large-v3-turbo ~1.62 GB vs ~809 MB)
echo.
echo   [2] Whisper (standard OpenAI)  !W_LABEL!
echo       + Well-tested, widely compatible
echo       + Simpler installation
echo       - Slower than WhisperX
echo.

if "!CURRENT_ENGINE!"=="whisperx" (
    set "ENG_DEFAULT=1"
    echo   Current install: WhisperX ^(press Enter to keep^)
) else if "!CURRENT_ENGINE!"=="whisper" (
    set "ENG_DEFAULT=2"
    echo   Current install: Whisper ^(press Enter to keep^)
) else if "!CUDA_OK!"=="true" (
    echo   GPU recommendation: [1] WhisperX
    echo   Reason: GPU detected, WhisperX will run significantly faster
    set "ENG_DEFAULT=1"
) else (
    echo   Recommendation: [1] WhisperX
    echo   Reason: WhisperX is still faster and more accurate even on CPU
    set "ENG_DEFAULT=1"
)
echo.

set /p ENGINE_INPUT="  Choose [1=WhisperX / 2=Whisper, default=!ENG_DEFAULT!]: "
if "!ENGINE_INPUT!"=="" set "ENGINE_INPUT=!ENG_DEFAULT!"

if "!ENGINE_INPUT!"=="2" (
    set "INSTALL_ENGINE=whisper"
    echo  Selected: Whisper ^(standard^)
) else (
    set "INSTALL_ENGINE=whisperx"
    echo  Selected: WhisperX
)

echo !INSTALL_ENGINE!> "%SCRIPT_DIR%\.engine"
echo  [OK] Engine choice saved to .engine
echo.

:: ============================================================
:: STEP 4: Install chosen engine
:: ============================================================
echo [4/5] Installing !INSTALL_ENGINE!...

if "!INSTALL_ENGINE!"=="whisper" goto INSTALL_WHISPER
goto INSTALL_WHISPERX

:INSTALL_WHISPER
where whisper >nul 2>&1
if not errorlevel 1 (
    echo  [OK] Whisper CLI already found
    goto INSTALL_PYTORCH
)
echo  Installing standard Whisper...
pip install -U openai-whisper --no-deps
if errorlevel 1 pip install -U openai-whisper
pip install tiktoken more-itertools numba tqdm regex >nul 2>&1
where whisper >nul 2>&1
if errorlevel 1 (
    echo  [ERROR] Whisper CLI not found after installation.
    goto INSTALL_FAILED
)
echo  [OK] Whisper installed
goto INSTALL_PYTORCH

:INSTALL_WHISPERX
where whisperx >nul 2>&1
if not errorlevel 1 (
    echo  [OK] WhisperX already installed
    goto INSTALL_PYTORCH
)
echo  Installing WhisperX (this may take several minutes)...
pip install whisperx
if errorlevel 1 (
    echo  [ERROR] WhisperX installation failed.
    goto INSTALL_FAILED
)
where whisperx >nul 2>&1
if errorlevel 1 (
    echo  [ERROR] WhisperX not found in PATH after install.
    goto INSTALL_FAILED
)
echo  [OK] WhisperX installed

:INSTALL_PYTORCH
echo.
echo  Checking PyTorch / GPU support...

python -c "import torch" >nul 2>&1
if not errorlevel 1 set "TORCH_INSTALLED=true"

for /f "tokens=*" %%L in ('python "%~dp0check_gpu.py" verify 2^>nul') do (
    set "%%L"
)

if "!CUDA_OK!"=="true" (
    echo  [OK] PyTorch GPU active - !GPU_NAME! ^(!VRAM!^)
    goto PYTORCH_DONE
)

if not "!TORCH_TAG!"=="cpu" (
    echo  [!] GPU detected but PyTorch is CPU-only
    echo      Reinstalling PyTorch !TORCH_TAG! for CUDA !CUDA_VERSION!...
    pip uninstall torch torchvision torchaudio -y >nul 2>&1
    pip install torch torchvision torchaudio --index-url !TORCH_URL! >nul 2>&1
    goto PYTORCH_VERIFY
)

if "!TORCH_INSTALLED!"=="false" (
    if "!TORCH_TAG!"=="cpu" (
        echo  [!] No GPU detected, installing CPU-only PyTorch...
        pip install torch torchvision torchaudio >nul 2>&1
        echo  [OK] PyTorch CPU installed
    ) else (
        echo  [!] PyTorch not found, installing GPU version...
        pip install torch torchvision torchaudio --index-url !TORCH_URL! >nul 2>&1
        echo  [OK] PyTorch !TORCH_TAG! installed
    )
    goto PYTORCH_VERIFY
)

if "!TORCH_TAG!"=="cpu" (
    echo  [!] No supported GPU found, will use CPU mode
    goto PYTORCH_DONE
)

echo  [!] PyTorch installed but GPU not active ^(CPU-only build^)
if "!GPU_VENDOR!"=="nvidia" echo      GPU: NVIDIA CUDA !CUDA_VERSION! ^(needs PyTorch !TORCH_TAG!^)
echo.
set /p UPGRADE_TORCH="  Upgrade PyTorch to GPU version? (~5-10 min download) (Y/N, default=N): "
if /i not "!UPGRADE_TORCH!"=="Y" (
    echo  [INFO] Keeping CPU-only PyTorch
    goto PYTORCH_DONE
)
echo  Upgrading PyTorch...
pip uninstall torch torchvision torchaudio -y >nul 2>&1
pip install torch torchvision torchaudio --index-url !TORCH_URL! >nul 2>&1

:PYTORCH_VERIFY
for /f "tokens=*" %%L in ('python "%~dp0check_gpu.py" verify 2^>nul') do (
    set "%%L"
)
if "!CUDA_OK!"=="true" (
    echo  [OK] PyTorch GPU active - !GPU_NAME! ^(!VRAM!^)
) else (
    echo  [!] GPU still not active, will use CPU
)

:PYTORCH_DONE

:: ============================================================
:: STEP 5: AI Translation Engines
:: ============================================================
echo.
echo [5/5] Checking AI translation engines...
echo  (Optional - required for subtitle translation)
echo.

set "CLAUDE_FOUND=false"
set "GEMINI_FOUND=false"

for %%c in (claude claude-code claudecode) do (
    where %%c >nul 2>&1
    if not errorlevel 1 (
        echo  [OK] Claude found: %%c
        set "CLAUDE_FOUND=true"
    )
)
for %%c in (gemini gemini-cli) do (
    where %%c >nul 2>&1
    if not errorlevel 1 (
        echo  [OK] Gemini found: %%c
        set "GEMINI_FOUND=true"
    )
)

if "!CLAUDE_FOUND!"=="false" if "!GEMINI_FOUND!"=="false" (
    echo  [WARN] No AI translation engine found.
    echo         Install one or both for subtitle translation:
    echo.
    echo           Claude : npm install -g @anthropic-ai/claude-code
    echo           Gemini : npm install -g @google/gemini-cli
    echo.
    echo         Re-run install.bat after installing to verify.
)

:: ============================================================
:: STEP 5b: Model Download
:: ============================================================
if "!INSTALL_ENGINE!"=="whisperx" goto WX_MODEL_SECTION

echo.
echo [5b] Whisper Model Download ^(optional^)
echo  Models stored in: %USERPROFILE%\.cache\whisper\
echo.

set "CACHE_DIR=%USERPROFILE%\.cache\whisper"
echo  GPU recommendation: !RECOMMENDED_MODEL! ^(!RECOMMENDED_REASON!^)
echo.

set "M1=tiny"           & set "S1=~75 MB " & set "V1=~1 GB "
set "M2=base"           & set "S2=~145 MB" & set "V2=~1 GB "
set "M3=small"          & set "S3=~466 MB" & set "V3=~2 GB "
set "M4=medium"         & set "S4=~1.5 GB" & set "V4=~5 GB "
set "M5=large-v1"       & set "S5=~3.0 GB" & set "V5=~10 GB"
set "M6=large-v2"       & set "S6=~3.0 GB" & set "V6=~10 GB"
set "M7=large-v3"       & set "S7=~3.0 GB" & set "V7=~10 GB"
set "M8=large-v3-turbo" & set "S8=~809 MB" & set "V8=~6 GB "

set "MODEL_DL_DEFAULT=S"

:MODEL_LOOP
for %%i in (1 2 3 4 5 6 7 8) do (
    set "ST_%%i=            "
    if exist "%CACHE_DIR%\!M%%i!.pt"      set "ST_%%i=[installed]  "
    if /i "!M%%i!"=="!RECOMMENDED_MODEL!" set "ST_%%i=[RECOMMENDED]"
    if exist "%CACHE_DIR%\!M%%i!.pt" if /i "!M%%i!"=="!RECOMMENDED_MODEL!" set "ST_%%i=[installed] * "
    if /i "!M%%i!"=="!RECOMMENDED_MODEL!" set "MODEL_DL_DEFAULT=%%i"
)

echo.
echo  Whisper models  ^(stored in: %CACHE_DIR%\^)
echo  ------------------------------------------------------------------------
echo   No  Model              Size      VRAM       Status
echo  ------------------------------------------------------------------------
for %%i in (1 2 3 4 5 6 7 8) do (
    echo   [%%i] !M%%i!          !S%%i!    !V%%i!     !ST_%%i!
)
echo  ------------------------------------------------------------------------
echo   [A] Download ALL models  ^(~12 GB total^)
echo   [S] Skip / Done
echo  ------------------------------------------------------------------------
echo.
echo  Tip: Disable Cloudflare/firewall if download is slow or fails.
echo.
set /p MODEL_DL="Choose [1-8 / A / S, default=!MODEL_DL_DEFAULT!]: "
if "!MODEL_DL!"=="" set "MODEL_DL=!MODEL_DL_DEFAULT!"
if /i "!MODEL_DL!"=="S" goto NLLB_SECTION
if /i "!MODEL_DL!"=="A" goto MODEL_DOWNLOAD_ALL
set /a DL_IDX=!MODEL_DL! 2>nul
if !DL_IDX! LSS 1 goto MODEL_LOOP
if !DL_IDX! GTR 8 goto MODEL_LOOP
echo.
call :DOWNLOAD_MODEL !M%MODEL_DL%!
goto MODEL_LOOP

:MODEL_DOWNLOAD_ALL
echo.
for %%i in (1 2 3 4 5 6 7 8) do (
    call :DOWNLOAD_MODEL !M%%i!
)
goto MODEL_LOOP

:WX_MODEL_SECTION
set "WX_CACHE=%USERPROFILE%\.cache\huggingface\hub"
echo.
echo [5b] WhisperX Model Download ^(optional^)
echo  Models stored in: !WX_CACHE!\
echo.

set "M1=tiny"           & set "S1=~75 MB  " & set "V1=~1 GB "
set "M2=base"           & set "S2=~145 MB " & set "V2=~1 GB "
set "M3=small"          & set "S3=~466 MB " & set "V3=~2 GB "
set "M4=medium"         & set "S4=~1.5 GB " & set "V4=~5 GB "
set "M5=large-v1"       & set "S5=~3.0 GB " & set "V5=~10 GB"
set "M6=large-v2"       & set "S6=~3.0 GB " & set "V6=~10 GB"
set "M7=large-v3"       & set "S7=~3.0 GB " & set "V7=~10 GB"
set "M8=large-v3-turbo" & set "S8=~1.62 GB" & set "V8=~6 GB "

set "WX_DEFAULT=S"

:WX_MODEL_LOOP
for %%i in (1 2 3 4 5 6 7 8) do (
    set "WX_ST_%%i=            "
    if exist "!WX_CACHE!\models--Systran--faster-whisper-!M%%i!\" set "WX_ST_%%i=[installed]  "
    if /i "!M%%i!"=="!RECOMMENDED_MODEL!" set "WX_ST_%%i=[RECOMMENDED]"
    if exist "!WX_CACHE!\models--Systran--faster-whisper-!M%%i!\" if /i "!M%%i!"=="!RECOMMENDED_MODEL!" set "WX_ST_%%i=[installed] * "
    if /i "!M%%i!"=="!RECOMMENDED_MODEL!" set "WX_DEFAULT=%%i"
)

echo.
echo  WhisperX models  ^(stored in: !WX_CACHE!\^)
echo  ------------------------------------------------------------------------
echo   No  Model              Size       VRAM       Status
echo  ------------------------------------------------------------------------
for %%i in (1 2 3 4 5 6 7 8) do (
    echo   [%%i] !M%%i!          !S%%i!   !V%%i!     !WX_ST_%%i!
)
echo  ------------------------------------------------------------------------
echo   [A] Download ALL WhisperX models
echo   [S] Skip / Done
echo  ------------------------------------------------------------------------
echo.
set /p WX_DL="Choose [1-8 / A / S, default=!WX_DEFAULT!]: "
if "!WX_DL!"=="" set "WX_DL=!WX_DEFAULT!"
if /i "!WX_DL!"=="S" goto NLLB_SECTION
if /i "!WX_DL!"=="A" goto WX_DL_ALL
set /a WX_IDX=!WX_DL! 2>nul
if !WX_IDX! LSS 1 goto WX_MODEL_LOOP
if !WX_IDX! GTR 8 goto WX_MODEL_LOOP
echo.
call :DOWNLOAD_WX_MODEL !M%WX_DL%!
goto WX_MODEL_LOOP

:WX_DL_ALL
echo.
for %%i in (1 2 3 4 5 6 7 8) do (
    call :DOWNLOAD_WX_MODEL !M%%i!
)
goto WX_MODEL_LOOP

:: ============================================================
:: STEP 5c: NLLB Translation Model (offline, local)
:: ============================================================
:NLLB_SECTION
echo.
echo [5c] NLLB Translation Model ^(offline, local^)
echo  Used by translate engine as gap-filler when Gemini misses segments.
echo  Packages: transformers sentencepiece sacremoses accelerate
echo.

set "NLLB_PKG_OK=false"
python -c "import transformers" >nul 2>&1
if not errorlevel 1 (
    echo  [OK] transformers already installed
    set "NLLB_PKG_OK=true"
) else (
    set /p INSTALL_NLLB_PKG="  Install NLLB packages? (Y/N, default=Y): "
    if /i not "!INSTALL_NLLB_PKG!"=="N" (
        pip install transformers sentencepiece sacremoses accelerate
        if errorlevel 1 (
            echo  [WARN] Some NLLB packages may not have installed correctly
        ) else (
            echo  [OK] NLLB packages installed
            set "NLLB_PKG_OK=true"
        )
    )
)

if "!NLLB_PKG_OK!"=="false" (
    echo  [INFO] NLLB skipped. You can install it later and re-run install.bat.
    goto FINISH
)

set "HF_HUB=%USERPROFILE%\.cache\huggingface\hub"
set "NLLB_600M_DIR=!HF_HUB!\models--facebook--nllb-200-distilled-600M"
set "NLLB_1B3_DIR=!HF_HUB!\models--facebook--nllb-200-distilled-1.3B"

set "NLLB_600M_ST=            "
set "NLLB_1B3_ST=            "
if exist "!NLLB_600M_DIR!\" set "NLLB_600M_ST=[downloaded]"
if exist "!NLLB_1B3_DIR!\"  set "NLLB_1B3_ST=[downloaded]"

if "!NLLB_RECOMMENDED!"=="1.3B" (
    set "NLLB_600M_REC=             "
    set "NLLB_1B3_REC=[RECOMMENDED]"
    set "NLLB_DEFAULT=2"
) else (
    set "NLLB_600M_REC=[RECOMMENDED]"
    set "NLLB_1B3_REC=             "
    set "NLLB_DEFAULT=1"
)

:NLLB_MODEL_LOOP
echo.
echo  NLLB Models:
echo  -------------------------------------------------------------------
echo   [1] nllb-200-distilled-600M   ~2.4 GB   !NLLB_600M_ST!  !NLLB_600M_REC!
echo   [2] nllb-200-distilled-1.3B   ~5.0 GB   !NLLB_1B3_ST!   !NLLB_1B3_REC!
echo   [S] Skip
echo  -------------------------------------------------------------------
echo   Recommendation: !NLLB_RECOMMENDED! ^(!NLLB_RECOMMENDED_REASON!^)
echo.
set /p NLLB_DL="Choose [1-2 / S, default=!NLLB_DEFAULT!]: "
if "!NLLB_DL!"=="" set "NLLB_DL=!NLLB_DEFAULT!"
if /i "!NLLB_DL!"=="S" goto FINISH
if "!NLLB_DL!"=="1" goto NLLB_DL_600M
if "!NLLB_DL!"=="2" goto NLLB_DL_1B3
goto NLLB_MODEL_LOOP

:NLLB_DL_600M
echo.
echo  Downloading nllb-200-distilled-600M...
python -c "from transformers import AutoModelForSeq2SeqLM, AutoTokenizer; AutoTokenizer.from_pretrained('facebook/nllb-200-distilled-600M'); AutoModelForSeq2SeqLM.from_pretrained('facebook/nllb-200-distilled-600M')"
if errorlevel 1 (
    echo  [ERROR] Failed to download 600M model
    goto NLLB_MODEL_LOOP
)
echo  [OK] nllb-200-distilled-600M downloaded
echo 600M>"%SCRIPT_DIR%\.nllb"
echo  [OK] Model preference saved to .nllb
goto FINISH

:NLLB_DL_1B3
echo.
echo  Downloading nllb-200-distilled-1.3B...
python -c "from transformers import AutoModelForSeq2SeqLM, AutoTokenizer; AutoTokenizer.from_pretrained('facebook/nllb-200-distilled-1.3B'); AutoModelForSeq2SeqLM.from_pretrained('facebook/nllb-200-distilled-1.3B')"
if errorlevel 1 (
    echo  [ERROR] Failed to download 1.3B model
    goto NLLB_MODEL_LOOP
)
echo  [OK] nllb-200-distilled-1.3B downloaded
echo 1.3B>"%SCRIPT_DIR%\.nllb"
echo  [OK] Model preference saved to .nllb
goto FINISH

:FINISH
echo installed > "%SCRIPT_DIR%\.installed"

set "USE_BAT=whisper-subtitle.bat"
if "!INSTALL_ENGINE!"=="whisperx" set "USE_BAT=whisperx-subtitle.bat"

echo.
echo ============================================================
echo  [SUCCESS] Installation complete!
echo  Engine   : !INSTALL_ENGINE!
echo  Run      : !USE_BAT!
echo ============================================================
echo.
pause
exit /b 0

::------------------------------------------------------------
:DOWNLOAD_MODEL
set "DL_MODEL=%~1"
if exist "%CACHE_DIR%\%DL_MODEL%.pt" (
    echo  [SKIP] %DL_MODEL% already downloaded
    goto :eof
)
echo  Downloading %DL_MODEL%...
python -c "import whisper; whisper.load_model('%DL_MODEL%')"
if errorlevel 1 (
    echo  [ERROR] Failed to download %DL_MODEL%
) else (
    echo  [OK] %DL_MODEL% downloaded
)
goto :eof

::------------------------------------------------------------
:DOWNLOAD_WX_MODEL
set "DL_WX=%~1"
set "WX_HUB=%USERPROFILE%\.cache\huggingface\hub"
if exist "!WX_HUB!\models--Systran--faster-whisper-%DL_WX%\" (
    echo  [SKIP] WhisperX %DL_WX% already downloaded
    goto :eof
)
echo  Downloading WhisperX %DL_WX%...
python -c "from faster_whisper import WhisperModel; WhisperModel('%DL_WX%', device='cpu')"
if errorlevel 1 (
    echo  [ERROR] Failed to download WhisperX %DL_WX%
) else (
    echo  [OK] WhisperX %DL_WX% downloaded
)
goto :eof

:INSTALL_FAILED
echo.
echo ============================================================
echo  [FAILED] Installation incomplete.
echo  Fix the error above, then run install.bat again.
echo ============================================================
echo.
pause
exit /b 1
