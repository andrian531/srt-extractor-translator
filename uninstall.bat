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
echo   [1] Uninstall WhisperX  (whisperx + faster-whisper + model cache)
echo   [2] Uninstall Whisper   (openai-whisper + model cache)
echo   [3] Uninstall both
echo   [4] Cancel
echo.
set /p CHOICE="Choose [1-4]: "

if "!CHOICE!"=="4" exit /b 0
if "!CHOICE!"=="1" goto UNINSTALL_WHISPERX
if "!CHOICE!"=="2" goto UNINSTALL_WHISPER
if "!CHOICE!"=="3" goto UNINSTALL_BOTH
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
