@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul 2>&1

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

set "CURRENT_ENGINE=none"
if exist "%SCRIPT_DIR%\.engine" (
    for /f "usebackq tokens=*" %%E in ("%SCRIPT_DIR%\.engine") do set "CURRENT_ENGINE=%%E"
)

cls
echo ============================================================
echo   WHISPER SUBTITLE TOOLS - UNINSTALL
echo ============================================================
echo.
if "!CURRENT_ENGINE!"=="none" (
    echo   Status  : no engine recorded in .engine file
) else (
    echo   Installed engine: !CURRENT_ENGINE!
)
echo.
set "OLLAMA_MARKER=none"
if exist "%SCRIPT_DIR%\.ollama" (
    for /f "usebackq tokens=*" %%O in ("%SCRIPT_DIR%\.ollama") do set "OLLAMA_MARKER=%%O"
)

echo   [1] Uninstall WhisperX  (whisperx + faster-whisper + model cache)
echo   [2] Uninstall Whisper   (openai-whisper + model cache)
echo   [3] Uninstall both
echo   [4] Uninstall NLLB      (transformers packages + model cache)
if "!OLLAMA_MARKER!"=="none" (
    echo   [5] Uninstall Offline LLM  (remove downloaded models + marker^)
) else (
    echo   [5] Uninstall Offline LLM  (model: !OLLAMA_MARKER!^)
)
echo   [6] Cancel
echo.
set /p CHOICE="Choose [1-6]: "

if "!CHOICE!"=="6" exit /b 0
if "!CHOICE!"=="1" goto UNINSTALL_WHISPERX
if "!CHOICE!"=="2" goto UNINSTALL_WHISPER
if "!CHOICE!"=="3" goto UNINSTALL_BOTH
if "!CHOICE!"=="4" goto UNINSTALL_NLLB
if "!CHOICE!"=="5" goto UNINSTALL_OLLAMA
echo  Invalid choice.
pause
exit /b 0

:UNINSTALL_WHISPERX
echo.
echo  Uninstalling WhisperX packages...
pip uninstall whisperx faster-whisper ctranslate2 pyannote.audio -y 2>nul
echo  [OK] WhisperX packages removed

echo.
set /p DEL_WX="  Delete WhisperX model cache? (Y/N, default=Y): "
if /i not "!DEL_WX!"=="N" (
    set "WX_HUB=%USERPROFILE%\.cache\huggingface\hub"
    if exist "!WX_HUB!" (
        for /d %%D in ("!WX_HUB!\models--Systran--faster-whisper-*") do (
            echo  Removing: %%~nxD
            rmdir /s /q "%%D" 2>nul
        )
        echo  [OK] WhisperX model cache removed
    ) else (
        echo  [INFO] No WhisperX cache found
    )
)
goto CLEANUP

:UNINSTALL_WHISPER
echo.
echo  Uninstalling Whisper package...
pip uninstall openai-whisper -y 2>nul
echo  [OK] openai-whisper removed

echo.
set /p DEL_W="  Delete Whisper model cache? (Y/N, default=Y): "
if /i not "!DEL_W!"=="N" (
    set "W_CACHE=%USERPROFILE%\.cache\whisper"
    if exist "!W_CACHE!" (
        rmdir /s /q "!W_CACHE!" 2>nul
        echo  [OK] Whisper model cache removed
    ) else (
        echo  [INFO] No Whisper cache found
    )
)
goto CLEANUP

:UNINSTALL_BOTH
echo.
echo  Uninstalling WhisperX packages...
pip uninstall whisperx faster-whisper ctranslate2 pyannote.audio -y 2>nul
echo  [OK] WhisperX packages removed

echo.
echo  Uninstalling Whisper package...
pip uninstall openai-whisper -y 2>nul
echo  [OK] openai-whisper removed

echo.
set /p DEL_ALL="  Delete ALL model caches? (Y/N, default=Y): "
if /i not "!DEL_ALL!"=="N" (
    set "WX_HUB=%USERPROFILE%\.cache\huggingface\hub"
    if exist "!WX_HUB!" (
        for /d %%D in ("!WX_HUB!\models--Systran--faster-whisper-*") do (
            echo  Removing: %%~nxD
            rmdir /s /q "%%D" 2>nul
        )
        echo  [OK] WhisperX model cache removed
    )
    set "W_CACHE=%USERPROFILE%\.cache\whisper"
    if exist "!W_CACHE!" (
        rmdir /s /q "!W_CACHE!" 2>nul
        echo  [OK] Whisper model cache removed
    )
)
goto CLEANUP

:UNINSTALL_NLLB
echo.
echo  Uninstalling NLLB packages...
pip uninstall transformers sentencepiece sacremoses accelerate tokenizers -y 2>nul
echo  [OK] NLLB packages removed

echo.
set /p DEL_NLLB="  Delete NLLB model cache? (Y/N, default=Y): "
if /i not "!DEL_NLLB!"=="N" (
    set "HF_HUB=%USERPROFILE%\.cache\huggingface\hub"
    if exist "!HF_HUB!" (
        for /d %%D in ("!HF_HUB!\models--facebook--nllb-*") do (
            echo  Removing: %%~nxD
            rmdir /s /q "%%D" 2>nul
        )
        echo  [OK] NLLB model cache removed
    ) else (
        echo  [INFO] No NLLB cache found
    )
)
if exist "%SCRIPT_DIR%\.nllb" (
    del "%SCRIPT_DIR%\.nllb"
    echo  [OK] .nllb marker removed
)
echo.
echo ============================================================
echo  [DONE] NLLB uninstall complete.
echo ============================================================
echo.
pause
exit /b 0

:UNINSTALL_OLLAMA
echo.
echo  Removing Offline LLM models...

set "OLL_MODEL=none"
if exist "%SCRIPT_DIR%\.ollama" (
    for /f "usebackq tokens=*" %%M in ("%SCRIPT_DIR%\.ollama") do set "OLL_MODEL=%%M"
)

if "!OLL_MODEL!"=="none" (
    echo  [INFO] No .ollama marker found ^(no model recorded^).
) else (
    echo  Recorded model: !OLL_MODEL!
    set /p REMOVE_OLL_MODEL="  Remove model '!OLL_MODEL!' from Ollama? (Y/N, default=Y): "
    if /i not "!REMOVE_OLL_MODEL!"=="N" (
        ollama rm !OLL_MODEL! >nul 2>&1
        if errorlevel 1 (
            echo  [WARN] Could not remove !OLL_MODEL! - it may not be installed or Ollama service is not running.
        ) else (
            echo  [OK] Ollama model removed: !OLL_MODEL!
        )
    )
)

echo.
set /p REMOVE_ALL_OLL="  Remove ALL other Ollama models too? (Y/N, default=N): "
if /i "!REMOVE_ALL_OLL!"=="Y" (
    for /f "skip=1 tokens=1" %%M in ('ollama list 2^>nul') do (
        echo  Removing: %%M
        ollama rm %%M >nul 2>&1
    )
    echo  [OK] All Ollama models removed
)

if exist "%SCRIPT_DIR%\.ollama" (
    del "%SCRIPT_DIR%\.ollama"
    echo  [OK] .ollama marker removed
)

echo.
echo ============================================================
echo  [DONE] Offline LLM uninstall complete.
echo  Note: Ollama runtime itself was NOT uninstalled.
echo  To remove Ollama: Control Panel ^> Programs ^> Uninstall Ollama
echo ============================================================
echo.
pause
exit /b 0

:CLEANUP
echo.
set /p REMOVE_TORCH="  Remove PyTorch too? (only if not used for anything else) (Y/N, default=N): "
if /i "!REMOVE_TORCH!"=="Y" (
    pip uninstall torch torchvision torchaudio -y 2>nul
    echo  [OK] PyTorch removed
)

if exist "%SCRIPT_DIR%\.installed" del "%SCRIPT_DIR%\.installed"
if exist "%SCRIPT_DIR%\.engine"    del "%SCRIPT_DIR%\.engine"
echo  [OK] Marker files removed

echo.
echo ============================================================
echo  [DONE] Uninstall complete.
echo ============================================================
echo.
pause
exit /b 0
