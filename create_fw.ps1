$text = Get-Content whisperx-subtitle.bat -Raw
$text = $text -replace 'WHISPERX SUBTITLE EXTRACTOR', 'FASTER-WHISPER SUBTITLE EXTRACTOR'
$text = $text -replace 'Engine  : WhisperX', 'Engine  : faster-whisper (stable-ts)'
$text = $text -replace 'Engine     : WhisperX', 'Engine     : faster-whisper (stable-ts)'
$text = $text -replace 'TRANSCRIPTION OPTIONS  \(WhisperX\)', 'TRANSCRIPTION OPTIONS  (faster-whisper)'

$old_check = 'where whisperx \>nul 2\>\&1\r\nif errorlevel 1 \(\r\n    echo  \[ERROR\] WhisperX not found\. Please run install\.bat to install it\.'
$new_check = 'python -c "import stable_whisper; import faster_whisper" >nul 2>&1`r`nif errorlevel 1 (`r`n    echo  [ERROR] faster-whisper or stable-ts not found. Please run install.bat.'
$text = $text -replace $old_check, $new_check

$old_cmd = 'whisperx "%INPUT_FILE%" --model %MODEL% --output_format %OUTPUT_FORMAT% --output_dir "%FILE_DIR%" --device %WHISPER_DEVICE% --max_line_width 35 --max_line_count 2\r\n\) else \(\r\n    whisperx "%INPUT_FILE%" --model %MODEL% --language %LANGUAGE% --output_format %OUTPUT_FORMAT% --output_dir "%FILE_DIR%" --device %WHISPER_DEVICE% --max_line_width 35 --max_line_count 2'
$new_cmd = 'set "ST_OUT=%FILE_DIR%\%~n1.%OUTPUT_FORMAT%"`r`n    if "%OUTPUT_FORMAT%"=="all" set "ST_OUT=%FILE_DIR%\%~n1.srt"`r`n    stable-ts "%INPUT_FILE%" -o "!ST_OUT!" --model %MODEL% --device %WHISPER_DEVICE% --backend faster-whisper --max_line_count 2 --max_line_width 35`r`n) else (`r`n    set "ST_OUT=%FILE_DIR%\%~n1.%OUTPUT_FORMAT%"`r`n    if "%OUTPUT_FORMAT%"=="all" set "ST_OUT=%FILE_DIR%\%~n1.srt"`r`n    stable-ts "%INPUT_FILE%" -o "!ST_OUT!" --model %MODEL% --language %LANGUAGE% --device %WHISPER_DEVICE% --backend faster-whisper --max_line_count 2 --max_line_width 35'
$text = $text -replace $old_cmd, $new_cmd

Set-Content -Path "faster-whisper-subtitle.bat" -Value $text
