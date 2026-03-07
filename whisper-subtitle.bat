@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul 2>&1

:: ============================================================
::  WHISPER SUBTITLE EXTRACTOR
::  Taruh file .bat ini di folder video, double-click untuk mulai
:: ============================================================

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "MODEL=large-v3"
set "LANGUAGE="
set "OUTPUT_FORMAT=srt"
set "WHISPER_DEVICE=cuda"

cls
echo ============================================================
echo   WHISPER SUBTITLE EXTRACTOR
echo   Folder: %SCRIPT_DIR%
echo ============================================================
echo.
echo  Menu Utama:
echo   [1] Generate Subtitle  - ekstrak subtitle dari file video
echo   [2] Translate Subtitle - terjemahkan file .srt ke Indonesian
echo.
set /p MAIN_MENU="Pilih menu [1-2]: "

if "!MAIN_MENU!"=="2" goto MENU_TRANSLATE
if "!MAIN_MENU!"=="1" goto MENU_GENERATE
goto MENU_GENERATE

:: ============================================================
:: MENU: TRANSLATE SUBTITLE
:: ============================================================
:MENU_TRANSLATE
cls
echo ============================================================
echo   TRANSLATE SUBTITLE ke Indonesian
echo   Folder: %SCRIPT_DIR%
echo ============================================================
echo.

:: Cek engine translate yang tersedia
echo  Memeriksa engine translate...
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
        "%APPDATA%
pm\claude.cmd"
        "%APPDATA%
pm\claude"
        "%LOCALAPPDATA%
pm\claude.cmd"
        "%LOCALAPPDATA%
pm\claude"
        "%ProgramFiles%
odejs\claude.cmd"
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
        "%APPDATA%
pm\gemini.cmd"
        "%APPDATA%
pm\gemini"
        "%LOCALAPPDATA%
pm\gemini.cmd"
        "%LOCALAPPDATA%
pm\gemini"
    ) do (
        if "!GEMINI_CMD!"=="" (
            if exist %%p set "GEMINI_CMD=%%~p"
        )
    )
)

if "!CLAUDE_CMD!"=="" if "!GEMINI_CMD!"=="" (
    echo  [ERROR] Tidak ada engine translate ditemukan.
    echo  Install Claude : npm install -g @anthropic-ai/claude-code
    echo  Install Gemini : npm install -g @google/gemini-cli
    pause
    exit /b 1
)
if not "!CLAUDE_CMD!"=="" echo  [OK] Claude Code : !CLAUDE_CMD!
if not "!GEMINI_CMD!"=="" echo  [OK] Gemini CLI  : !GEMINI_CMD!
echo.

:: Scan file SRT
echo  Mencari file subtitle (.srt) di: %SCRIPT_DIR%
echo ============================================================
echo.

set "SIDX=0"
for /r "%SCRIPT_DIR%" %%f in (*.srt) do (
    :: Skip file _ID.srt (sudah diterjemahkan)
    echo %%~nf | findstr /i "_ID$" >nul
    if errorlevel 1 (
        set /a SIDX+=1
        set "SFILE_!SIDX!=%%f"
        set "SREL=%%f"
        set "SREL=!SREL:%SCRIPT_DIR%\=!"
        echo  [!SIDX!] !SREL!
    )
)

if !SIDX!==0 (
    echo  Tidak ada file .srt ditemukan.
    pause
    exit /b 0
)

echo.
echo  Total: !SIDX! file subtitle ditemukan
echo.

:CHOOSE_SRT
set "SCHOICE="
set /p SCHOICE="Masukkan nomor file (1-!SIDX!) atau 'all' untuk semua: "

if /i "!SCHOICE!"=="all" goto TRANSLATE_ALL
if "!SCHOICE!"=="" goto CHOOSE_SRT
set /a STEST=!SCHOICE! 2>nul
if !STEST! LSS 1 goto INVALID_SRT
if !STEST! GTR !SIDX! goto INVALID_SRT
goto DO_TRANSLATE_ONE

:INVALID_SRT
echo  [!] Input tidak valid
goto CHOOSE_SRT

:DO_TRANSLATE_ONE
set "TARGET_SRT=!SFILE_%SCHOICE%!"
echo.
echo  Menerjemahkan: !TARGET_SRT!
python "%~dp0translate_srt.py" "!TARGET_SRT!"
goto TRANSLATE_DONE

:TRANSLATE_ALL
for /l %%i in (1,1,!SIDX!) do (
    echo.
    echo  [%%i/!SIDX!] Menerjemahkan: !SFILE_%%i!
    python "%~dp0translate_srt.py" "!SFILE_%%i!"
)

:TRANSLATE_DONE
echo.
echo ============================================================
echo   Terjemahan selesai!
echo ============================================================
echo.
pause
exit /b 0

:: ============================================================
:: MENU: GENERATE SUBTITLE
:: ============================================================
:MENU_GENERATE

:: Deteksi engine translate yang tersedia
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
        "%APPDATA%
pm\claude.cmd"
        "%APPDATA%
pm\claude"
        "%LOCALAPPDATA%
pm\claude.cmd"
        "%LOCALAPPDATA%
pm\claude"
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
        "%APPDATA%
pm\gemini.cmd"
        "%APPDATA%
pm\gemini"
        "%LOCALAPPDATA%
pm\gemini.cmd"
        "%LOCALAPPDATA%
pm\gemini"
    ) do (
        if "!GEMINI_CMD!"=="" (
            if exist %%p set "GEMINI_CMD=%%~p"
        )
    )
)

:: ------------------------------------------------------------
:: STEP 1: Cek Python
:: ------------------------------------------------------------
echo [1/4] Memeriksa Python...
python --version >nul 2>&1
if errorlevel 1 (
    echo  [ERROR] Python tidak ditemukan!
    echo  Download Python di: https://www.python.org/downloads/
    echo  Pastikan centang "Add Python to PATH" saat install.
    pause
    exit /b 1
)
for /f "tokens=*" %%v in ('python --version 2^>^&1') do echo  [OK] %%v

:: ------------------------------------------------------------
:: STEP 2: Cek / Install ffmpeg
:: ------------------------------------------------------------
echo.
echo [2/4] Memeriksa ffmpeg...
ffmpeg -version >nul 2>&1
if errorlevel 1 (
    echo  [!] ffmpeg tidak ditemukan. Mencoba install via winget...
    winget install --id Gyan.FFmpeg -e --silent >nul 2>&1
    if errorlevel 1 (
        echo  [!] winget gagal. Mencoba via chocolatey...
        choco install ffmpeg -y >nul 2>&1
    )
    ffmpeg -version >nul 2>&1
    if errorlevel 1 (
        echo  [ERROR] Gagal install ffmpeg otomatis.
        echo  Install manual: https://www.gyan.dev/ffmpeg/builds/
        echo  Lalu tambahkan folder bin-nya ke System PATH.
        pause
        exit /b 1
    )
    echo  [OK] ffmpeg berhasil diinstall
) else (
    for /f "tokens=1,2,3" %%a in ('ffmpeg -version 2^>^&1 ^| findstr "ffmpeg version"') do echo  [OK] %%a %%b %%c
)

:: ------------------------------------------------------------
:: STEP 3: Cek / Install Whisper
:: ------------------------------------------------------------
echo.
echo [3/4] Memeriksa Whisper...

where whisper >nul 2>&1
set "WHISPER_CLI=%errorlevel%"
python -c "import whisper" >nul 2>&1
set "WHISPER_MOD=%errorlevel%"

:: Cek CLI saja dulu - import whisper butuh torch yang belum tentu ada
if "%WHISPER_CLI%"=="0" (
    echo  [OK] Whisper CLI ditemukan
    goto WHISPER_DONE
)

echo  [!] Whisper belum terinstall. Menginstall sekarang...
echo  (Proses ini bisa memakan waktu beberapa menit)
echo.
pip install -U openai-whisper --no-deps
if errorlevel 1 (
    echo  [!] --no-deps gagal, mencoba install normal...
    pip install -U openai-whisper
)
:: Install dependency Whisper selain torch (torch akan diinstall terpisah versi CUDA)
pip install tiktoken more-itertools numba tqdm regex >nul 2>&1

:: Tidak cek import whisper di sini karena torch belum ada
:: Verifikasi import whisper dilakukan setelah PyTorch terinstall
where whisper >nul 2>&1
if errorlevel 1 (
    echo  [ERROR] Whisper CLI tidak ditemukan setelah install.
    pause
    exit /b 1
)
echo  [OK] Whisper berhasil diinstall, torch akan diinstall di langkah berikutnya

:WHISPER_DONE

:: ------------------------------------------------------------
:: STEP 3b: Cek PyTorch + GPU (auto-detect semua vendor)
:: ------------------------------------------------------------
echo.
echo  Memeriksa GPU dan PyTorch...

set "GPU_VENDOR=unknown"
set "CUDA_VERSION=none"
set "TORCH_TAG=cpu"
set "TORCH_URL=none"
set "CUDA_OK=false"
set "TORCH_INSTALLED=false"
set "GPU_NAME=tidak ada"
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
    echo  [OK] PyTorch GPU aktif - %GPU_NAME% ^(%VRAM%^)
    goto PYTORCH_DONE
)

:: Jika GPU tersedia, selalu reinstall PyTorch CUDA
:: (mencegah Whisper menimpa dengan versi CPU saat install/update)
if not "%TORCH_TAG%"=="cpu" (
    echo  [!] GPU tersedia tapi PyTorch CPU-only terdeteksi
    echo      Menginstall ulang PyTorch %TORCH_TAG% untuk CUDA %CUDA_VERSION%...
    pip uninstall torch torchvision torchaudio -y >nul 2>&1
    pip install torch torchvision torchaudio --index-url %TORCH_URL% >nul 2>&1
    goto PYTORCH_VERIFY
)

if "%TORCH_INSTALLED%"=="false" (
    if "%TORCH_TAG%"=="cpu" (
        echo  [!] Tidak ada GPU, install PyTorch CPU...
        pip install torch torchvision torchaudio >nul 2>&1
        echo  [OK] PyTorch CPU diinstall
        set "WHISPER_DEVICE=cpu"
    ) else (
        echo  [!] PyTorch belum ada, install versi GPU...
        echo      Target: %TORCH_TAG% untuk CUDA %CUDA_VERSION%
        pip install torch torchvision torchaudio --index-url %TORCH_URL% >nul 2>&1
        echo  [OK] PyTorch %TORCH_TAG% diinstall
    )
    goto PYTORCH_VERIFY
)

if "%TORCH_TAG%"=="cpu" (
    echo  [!] Tidak ada GPU yang didukung, PyTorch CPU akan dipakai
    set "WHISPER_DEVICE=cpu"
    goto PYTORCH_DONE
)

echo  [!] PyTorch terinstall tapi GPU tidak aktif ^(versi CPU-only^)
if "%GPU_VENDOR%"=="nvidia" echo      GPU tersedia: NVIDIA CUDA %CUDA_VERSION% ^(butuh PyTorch %TORCH_TAG%^)
if "%GPU_VENDOR%"=="amd"    echo      GPU tersedia: AMD ROCm
echo.
set /p UPGRADE_TORCH="  Upgrade PyTorch ke versi GPU? Proses ~5-10 menit (Y/N, default=N): "
if /i not "%UPGRADE_TORCH%"=="Y" (
    echo  [INFO] Tetap pakai CPU
    set "WHISPER_DEVICE=cpu"
    goto PYTORCH_DONE
)

echo  Mengupgrade PyTorch...
pip uninstall torch torchvision torchaudio -y >nul 2>&1
pip install torch torchvision torchaudio --index-url %TORCH_URL% >nul 2>&1

:PYTORCH_VERIFY
for /f "tokens=*" %%L in ('python "%~dp0check_gpu.py" verify 2^>nul') do (
    set "%%L"
)
if "%CUDA_OK%"=="true" (
    echo  [OK] PyTorch GPU aktif - %GPU_NAME% ^(%VRAM%^)
) else (
    echo  [!] GPU tetap tidak aktif, akan pakai CPU
    set "WHISPER_DEVICE=cpu"
)

:PYTORCH_DONE

:: Verifikasi akhir: whisper + torch bisa di-import bersama
echo.
echo  Verifikasi akhir Whisper + PyTorch...
python -c "import whisper" >nul 2>&1
if errorlevel 1 (
    echo  [!] import whisper gagal - mencoba ulang setelah refresh...
    :: Kadang terjadi karena PATH belum ter-refresh setelah install
    :: Coba jalankan whisper CLI sebagai fallback check
    where whisper >nul 2>&1
    if errorlevel 1 (
        echo  [ERROR] Whisper tidak ditemukan sama sekali.
        echo  Coba jalankan manual:
        echo    pip install openai-whisper --no-deps
        echo    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124
        pause
        exit /b 1
    )
    echo  [OK] Whisper CLI tersedia ^(import skip - lanjut^)
) else (
    for /f "tokens=*" %%v in ('python -c "import whisper; print(whisper.__version__)" 2^>^&1') do echo  [OK] Whisper v%%v siap digunakan
)

:: ------------------------------------------------------------
:: STEP 4: Scan semua file video
:: ------------------------------------------------------------
echo.
echo [4/4] Mencari file video di: %SCRIPT_DIR%
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
    echo  Tidak ada file video ditemukan di folder ini.
    pause
    exit /b 0
)

echo.
echo  Total: !IDX! file ditemukan
echo.

:: ------------------------------------------------------------
:: PILIH FILE
:: ------------------------------------------------------------
:CHOOSE_FILE
set "CHOICE="
set /p CHOICE="Masukkan nomor file (1-!IDX!) atau 'all' untuk semua: "

if /i "!CHOICE!"=="all" goto CHOOSE_OPTIONS
if "!CHOICE!"=="" goto CHOOSE_FILE

set /a TEST_CHOICE=!CHOICE! 2>nul
if !TEST_CHOICE! LSS 1 goto INVALID_CHOICE
if !TEST_CHOICE! GTR !IDX! goto INVALID_CHOICE

goto CHOOSE_OPTIONS

:INVALID_CHOICE
echo  [!] Input tidak valid, masukkan angka antara 1 sampai !IDX!
goto CHOOSE_FILE

:: ------------------------------------------------------------
:: PILIH OPSI
:: ------------------------------------------------------------
:CHOOSE_OPTIONS
echo.
echo ============================================================
echo   OPSI TRANSKRIP
echo ============================================================
echo.
echo  Model Whisper: (semua model pakai GPU jika tersedia)
echo   [1] tiny           - tercepat, akurasi rendah         ^| ~1GB  VRAM
echo   [2] base           - cepat, akurasi cukup             ^| ~1GB  VRAM
echo   [3] small          - seimbang                         ^| ~2GB  VRAM
echo   [4] medium         - akurasi baik                     ^| ~5GB  VRAM
echo   [5] large-v1       - akurasi tinggi, generasi pertama ^| ~10GB VRAM
echo   [6] large-v2       - lebih akurat dari v1             ^| ~10GB VRAM
echo   [7] large-v3       - akurasi terbaik official         ^| ~10GB VRAM
echo   [8] large-v3-turbo - cepat, akurasi hampir sama v3    ^| ~6GB  VRAM
echo.
echo  Rekomendasi: [4] medium untuk hasil cepat, [8] large-v3-turbo untuk hasil terbaik
echo.
set /p MODEL_CHOICE="Pilih model [1-8, default=4]: "

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
echo  Bahasa sumber video:
echo   [1] Auto-detect  (video multi-bahasa / tidak yakin) [DEFAULT]
echo   [2] Japanese
echo   [3] Korean
echo   [4] Chinese Mandarin
echo   [5] Cantonese / Hongkong
echo   [6] Indonesian
echo   [7] English
echo   [8] Lainnya (ketik manual)
echo.
echo  Catatan: Untuk video campur bahasa, pilih Auto-detect
echo.
set /p LANG_CHOICE="Pilih bahasa [1-8, default=1]: "

if "!LANG_CHOICE!"=="1" set LANGUAGE=
if "!LANG_CHOICE!"=="2" set LANGUAGE=Japanese
if "!LANG_CHOICE!"=="3" set LANGUAGE=Korean
if "!LANG_CHOICE!"=="4" set LANGUAGE=Chinese
if "!LANG_CHOICE!"=="5" set LANGUAGE=Cantonese
if "!LANG_CHOICE!"=="6" set LANGUAGE=Indonesian
if "!LANG_CHOICE!"=="7" set LANGUAGE=English
if "!LANG_CHOICE!"=="8" (
    set /p LANGUAGE="Ketik nama bahasa (misal: Thai, Vietnamese, Arabic): "
)
if "!LANG_CHOICE!"==""  set LANGUAGE=

echo.
echo  Format output:
echo   [1] srt  - paling kompatibel [DEFAULT]
echo   [2] vtt  - untuk web
echo   [3] txt  - plain text tanpa timestamp
echo   [4] all  - semua format sekaligus
echo.
set /p FMT_CHOICE="Pilih format [1-4, default=1]: "

if "!FMT_CHOICE!"=="1" set OUTPUT_FORMAT=srt
if "!FMT_CHOICE!"=="2" set OUTPUT_FORMAT=vtt
if "!FMT_CHOICE!"=="3" set OUTPUT_FORMAT=txt
if "!FMT_CHOICE!"=="4" set OUTPUT_FORMAT=all
if "!FMT_CHOICE!"==""  set OUTPUT_FORMAT=srt

:: Rangkuman
echo.
echo ============================================================
echo   AKAN DIPROSES:
if /i "!CHOICE!"=="all" (
    echo   File    : SEMUA !IDX! file
) else (
    echo   File    : !FILE_%CHOICE%!
)
echo   Model   : !MODEL!
if "!LANGUAGE!"=="" (
    echo   Bahasa  : Auto-detect
) else (
    echo   Bahasa  : !LANGUAGE!
)
echo   Device  : !WHISPER_DEVICE!
echo   Output  : .!OUTPUT_FORMAT!
echo ============================================================
echo.
set /p CONFIRM="Lanjutkan? (Y/N): "
if /i not "!CONFIRM!"=="Y" goto CHOOSE_FILE

:: ------------------------------------------------------------
:: PROSES
:: ------------------------------------------------------------
if /i "!CHOICE!"=="all" goto PROCESS_ALL

set "TARGET_FILE=!FILE_%CHOICE%!"
call :RUN_WHISPER "!TARGET_FILE!"
goto DONE

:PROCESS_ALL
for /l %%i in (1,1,!IDX!) do (
    echo.
    echo  [%%i/!IDX!] Memproses: !FILE_%%i!
    call :RUN_WHISPER "!FILE_%%i!"
)
goto DONE

:: ------------------------------------------------------------
:: SUBROUTINE: Jalankan Whisper pada satu file
:: ------------------------------------------------------------
:RUN_WHISPER
set "INPUT_FILE=%~1"
set "FILE_DIR=%~dp1"
set "FILE_DIR=%FILE_DIR:~0,-1%"

echo.
echo  Memproses: %~nx1
echo  Output ke: %FILE_DIR%
echo  Model    : %MODEL%
echo  Device   : %WHISPER_DEVICE%
echo  --------------------------------------------------------

if "%LANGUAGE%"=="" (
    whisper "%INPUT_FILE%" --model %MODEL% --output_format %OUTPUT_FORMAT% --output_dir "%FILE_DIR%" --device %WHISPER_DEVICE% --condition_on_previous_text False --no_speech_threshold 0.6
) else (
    whisper "%INPUT_FILE%" --model %MODEL% --language %LANGUAGE% --output_format %OUTPUT_FORMAT% --output_dir "%FILE_DIR%" --device %WHISPER_DEVICE% --condition_on_previous_text False --no_speech_threshold 0.6
)

if errorlevel 1 (
    if not "%WHISPER_DEVICE%"=="cpu" (
        echo  [!] GPU gagal, mencoba dengan CPU...
        if "%LANGUAGE%"=="" (
            whisper "%INPUT_FILE%" --model %MODEL% --output_format %OUTPUT_FORMAT% --output_dir "%FILE_DIR%" --device cpu --condition_on_previous_text False --no_speech_threshold 0.6
        ) else (
            whisper "%INPUT_FILE%" --model %MODEL% --language %LANGUAGE% --output_format %OUTPUT_FORMAT% --output_dir "%FILE_DIR%" --device cpu --condition_on_previous_text False --no_speech_threshold 0.6
        )
    )
)

if errorlevel 1 (
    echo  [ERROR] Gagal memproses: %~nx1
    goto :eof
)

echo  [SELESAI] Subtitle disimpan di: %FILE_DIR%

set "SRT_FILE=%FILE_DIR%\%~n1.srt"
if exist "!SRT_FILE!" (
    echo.
    echo  --------------------------------------------------------
    echo  Memeriksa terjemahan...
    if not "!CLAUDE_CMD!"=="" (
        python "%~dp0translate_srt.py" "!SRT_FILE!" "!CLAUDE_CMD!" "claude"
    ) else if not "!GEMINI_CMD!"=="" (
        python "%~dp0translate_srt.py" "!SRT_FILE!" "!GEMINI_CMD!" "gemini"
    ) else (
        echo  [INFO] Claude/Gemini tidak ditemukan, skip terjemahan otomatis.
        echo         Gunakan menu [2] Translate Subtitle untuk menerjemahkan manual.
    )
)
goto :eof

:: ------------------------------------------------------------
:: SELESAI
:: ------------------------------------------------------------
:DONE
echo.
echo ============================================================
echo   Semua proses selesai!
echo ============================================================
echo.
pause