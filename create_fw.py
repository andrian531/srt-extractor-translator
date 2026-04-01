import codecs

try:
    with codecs.open("whisperx-subtitle.bat", "r", "utf-8") as f:
        text = f.read()
    
    # Normalize newlines to \n to ensure multiline replaces work
    text = text.replace("\r\n", "\n")

    # Replacements for menu and UI
    text = text.replace("WHISPERX SUBTITLE EXTRACTOR", "FASTER-WHISPER SUBTITLE EXTRACTOR")
    text = text.replace("Engine  : WhisperX", "Engine  : faster-whisper (stable-ts)")
    text = text.replace("Engine     : WhisperX", "Engine     : faster-whisper (stable-ts)")
    text = text.replace("TRANSCRIPTION OPTIONS  (WhisperX)", "TRANSCRIPTION OPTIONS  (faster-whisper (stable-ts))")

    # Replace whisperx command check
    check_whisperx = """where whisperx >nul 2>&1
if errorlevel 1 (
    echo  [ERROR] WhisperX not found. Please run install.bat to install it."""
    check_fw = """python -c "import stable_whisper; import faster_whisper" >nul 2>&1
if errorlevel 1 (
    echo  [ERROR] faster-whisper or stable-ts not found. Please run install.bat to install it."""
    text = text.replace(check_whisperx, check_fw)

    # Replace whisperx command execution
    old_cmd = """    whisperx "%INPUT_FILE%" --model %MODEL% --output_format %OUTPUT_FORMAT% --output_dir "%FILE_DIR%" --device %WHISPER_DEVICE% --max_line_width 35 --max_line_count 2
) else (
    whisperx "%INPUT_FILE%" --model %MODEL% --language %LANGUAGE% --output_format %OUTPUT_FORMAT% --output_dir "%FILE_DIR%" --device %WHISPER_DEVICE% --max_line_width 35 --max_line_count 2"""
    
    new_cmd = """    set "ST_OUT=%FILE_DIR%\\%~n1.%OUTPUT_FORMAT%"
    if "%OUTPUT_FORMAT%"=="all" set "ST_OUT=%FILE_DIR%\\%~n1.srt"
    stable-ts "%INPUT_FILE%" -o "!ST_OUT!" --model %MODEL% --device %WHISPER_DEVICE% --backend faster-whisper --max_line_count 2 --max_line_width 35
) else (
    set "ST_OUT=%FILE_DIR%\\%~n1.%OUTPUT_FORMAT%"
    if "%OUTPUT_FORMAT%"=="all" set "ST_OUT=%FILE_DIR%\\%~n1.srt"
    stable-ts "%INPUT_FILE%" -o "!ST_OUT!" --model %MODEL% --language %LANGUAGE% --device %WHISPER_DEVICE% --backend faster-whisper --max_line_count 2 --max_line_width 35"""
    text = text.replace(old_cmd, new_cmd)

    # Replace USE_BAT defaults inside install.bat logic if there are any inside this file
    text = text.replace('whisperx-subtitle.bat', 'faster-whisper-subtitle.bat')

    # Re-add Windows CRLF
    text = text.replace("\n", "\r\n")

    with codecs.open("faster-whisper-subtitle.bat", "w", "utf-8") as f:
        f.write(text)
    print("Success: faster-whisper-subtitle.bat created.")
except Exception as e:
    print("Error:", e)
