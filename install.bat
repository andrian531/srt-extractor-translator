@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul 2>&1

echo ============================================================
echo   WHISPER SUBTITLE TOOLS - INSTALLER
echo   This script installs all required dependencies.
echo   Run this once before using whisper-subtitle.bat
echo ============================================================
echo.

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

:: ============================================================
:: STEP 1: Python
:: ============================================================
echo [1/4] Checking Python...
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
echo [2/4] Checking ffmpeg...
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
:: STEP 3: Whisper
:: ============================================================
echo.
echo [3/4] Checking Whisper...
where whisper >nul 2>&1
if not errorlevel 1 (
    echo  [OK] Whisper CLI found
    goto WHISPER_DONE
)

echo  [!] Whisper not installed. Installing now...
echo  (This may take a few minutes)
echo.
pip install -U openai-whisper --no-deps
if errorlevel 1 (
    echo  [!] --no-deps failed, trying full install...
    pip install -U openai-whisper
)
pip install tiktoken more-itertools numba tqdm regex >nul 2>&1

where whisper >nul 2>&1
if errorlevel 1 (
    echo  [ERROR] Whisper CLI not found after installation.
    echo  Try manually: pip install openai-whisper
    goto INSTALL_FAILED
)
echo  [OK] Whisper installed

:WHISPER_DONE

:: ============================================================
:: STEP 3b: PyTorch + GPU
:: ============================================================
echo.
echo [3b/4] Checking PyTorch and GPU support...

set "GPU_VENDOR=unknown"
set "CUDA_VERSION=none"
set "TORCH_TAG=cpu"
set "TORCH_URL=none"
set "CUDA_OK=false"
set "TORCH_INSTALLED=false"
set "GPU_NAME=none"
set "VRAM="

for /f "tokens=*" %%L in ('python "%~dp0check_gpu.py" detect 2^>nul') do (
    set "%%L"
)

echo  GPU Vendor : %GPU_VENDOR%
if not "%CUDA_VERSION%"=="none" echo  CUDA/ROCm  : %CUDA_VERSION%

python -c "import torch" >nul 2>&1
if not errorlevel 1 set "TORCH_INSTALLED=true"

for /f "tokens=*" %%L in ('python "%~dp0check_gpu.py" verify 2^>nul') do (
    set "%%L"
)

if "%CUDA_OK%"=="true" (
    echo  [OK] PyTorch GPU active - %GPU_NAME% ^(%VRAM%^)
    goto PYTORCH_DONE
)

if not "%TORCH_TAG%"=="cpu" (
    echo  [!] GPU detected but PyTorch is CPU-only
    echo      Reinstalling PyTorch %TORCH_TAG% for CUDA %CUDA_VERSION%...
    pip uninstall torch torchvision torchaudio -y >nul 2>&1
    pip install torch torchvision torchaudio --index-url %TORCH_URL% >nul 2>&1
    goto PYTORCH_VERIFY
)

if "%TORCH_INSTALLED%"=="false" (
    if "%TORCH_TAG%"=="cpu" (
        echo  [!] No GPU detected, installing CPU-only PyTorch...
        pip install torch torchvision torchaudio >nul 2>&1
        echo  [OK] PyTorch CPU installed
    ) else (
        echo  [!] PyTorch not found, installing GPU version...
        echo      Target: %TORCH_TAG% for CUDA %CUDA_VERSION%
        pip install torch torchvision torchaudio --index-url %TORCH_URL% >nul 2>&1
        echo  [OK] PyTorch %TORCH_TAG% installed
    )
    goto PYTORCH_VERIFY
)

if "%TORCH_TAG%"=="cpu" (
    echo  [!] No supported GPU found, will use CPU mode
    goto PYTORCH_DONE
)

echo  [!] PyTorch is installed but GPU is not active ^(CPU-only build^)
if "%GPU_VENDOR%"=="nvidia" echo      GPU found: NVIDIA CUDA %CUDA_VERSION% ^(needs PyTorch %TORCH_TAG%^)
if "%GPU_VENDOR%"=="amd"    echo      GPU found: AMD ROCm
echo.
set /p UPGRADE_TORCH="  Upgrade PyTorch to GPU version? (~5-10 min download) (Y/N, default=N): "
if /i not "%UPGRADE_TORCH%"=="Y" (
    echo  [INFO] Keeping CPU-only PyTorch
    goto PYTORCH_DONE
)

echo  Upgrading PyTorch...
pip uninstall torch torchvision torchaudio -y >nul 2>&1
pip install torch torchvision torchaudio --index-url %TORCH_URL% >nul 2>&1

:PYTORCH_VERIFY
for /f "tokens=*" %%L in ('python "%~dp0check_gpu.py" verify 2^>nul') do (
    set "%%L"
)
if "%CUDA_OK%"=="true" (
    echo  [OK] PyTorch GPU active - %GPU_NAME% ^(%VRAM%^)
) else (
    echo  [!] GPU still not active, will use CPU
)

:PYTORCH_DONE

:: ============================================================
:: STEP 4: AI Translation Engines (Claude / Gemini)
:: ============================================================
echo.
echo [4/5] Checking AI translation engines...
echo  (These are optional but required for subtitle translation)
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

if "%CLAUDE_FOUND%"=="false" if "%GEMINI_FOUND%"=="false" (
    echo  [WARN] No AI translation engine found.
    echo         Subtitle generation will still work, but auto-translation
    echo         will be disabled until you install one of the following:
    echo.
    echo           Claude : npm install -g @anthropic-ai/claude-code
    echo           Gemini : npm install -g @google/gemini-cli
    echo.
    echo         Re-run install.bat after installing an engine to verify.
)

:: ============================================================
:: STEP 5: Whisper Model Download (optional)
:: ============================================================
echo.
echo [5/5] Whisper Model Download ^(optional^)
echo  Models are stored in: %USERPROFILE%\.cache\whisper\
echo.

set "CACHE_DIR=%USERPROFILE%\.cache\whisper"

:: Check which models are already installed
echo  Available models:
echo  -----------------------------------------------------------------------
echo   No  Model             Size      VRAM needed   Status
echo  -----------------------------------------------------------------------

set "M1=tiny"       & set "S1=~75 MB  " & set "V1=~1 GB "
set "M2=base"       & set "S2=~145 MB " & set "V2=~1 GB "
set "M3=small"      & set "S3=~466 MB " & set "V3=~2 GB "
set "M4=medium"     & set "S4=~1.5 GB " & set "V4=~5 GB "
set "M5=large-v1"   & set "S5=~3.0 GB " & set "V5=~10 GB"
set "M6=large-v2"   & set "S6=~3.0 GB " & set "V6=~10 GB"
set "M7=large-v3"   & set "S7=~3.0 GB " & set "V7=~10 GB"
set "M8=large-v3-turbo" & set "S8=~809 MB " & set "V8=~6 GB "

for %%i in (1 2 3 4 5 6 7 8) do (
    set "ST_%%i=not installed"
    if exist "%CACHE_DIR%\!M%%i!.pt" set "ST_%%i=installed    "
)

for %%i in (1 2 3 4 5 6 7 8) do (
    echo   [%%i] !M%%i!          !S%%i!    !V%%i!      !ST_%%i!
)

echo  -----------------------------------------------------------------------
echo   [A] Download ALL models  ^(~12 GB total^)
echo   [S] Skip - download later automatically on first use
echo  -----------------------------------------------------------------------
echo.
echo  Tip: Disable Cloudflare/firewall if download is slow or fails.
echo.
set /p MODEL_DL="Choose model to download [1-8 / A / S, default=S]: "

if /i "!MODEL_DL!"=="S" goto MODEL_SKIP
if "!MODEL_DL!"==""     goto MODEL_SKIP
if /i "!MODEL_DL!"=="A" goto MODEL_DOWNLOAD_ALL

:: Download single model
set /a DL_IDX=!MODEL_DL! 2>nul
if !DL_IDX! LSS 1 goto MODEL_SKIP
if !DL_IDX! GTR 8 goto MODEL_SKIP

call :DOWNLOAD_MODEL !M%MODEL_DL%!
goto MODEL_DONE

:MODEL_DOWNLOAD_ALL
echo.
echo  Downloading all models... this will take a while.
echo.
for %%i in (1 2 3 4 5 6 7 8) do (
    call :DOWNLOAD_MODEL !M%%i!
)
goto MODEL_DONE

:MODEL_SKIP
echo  [SKIP] Models will be downloaded automatically on first use.

:MODEL_DONE

:: ============================================================
:: Write marker file
:: ============================================================
echo installed > "%SCRIPT_DIR%\.installed"

echo.
echo ============================================================
echo  [SUCCESS] All core dependencies are installed!
echo  You can now run whisper-subtitle.bat
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

:INSTALL_FAILED
echo.
echo ============================================================
echo  [FAILED] Installation incomplete.
echo  Fix the error above, then run install.bat again.
echo ============================================================
echo.
pause
exit /b 1
