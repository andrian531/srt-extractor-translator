# Whisper Subtitle Tools

Extract subtitles from any video file using OpenAI Whisper (local, offline), then translate them to any language using Gemini CLI or Claude Code — all from a simple menu-driven interface.

## Features

- **Generate subtitles** from video files using Whisper (runs fully offline, on your machine)
- **Translate SRT files** to any language via AI (Gemini CLI or Claude Code)
- Auto-detects source language of SRT files
- Smart target language menu — never offers translation to the same language as source
- AI detects content genre/type before translating for more natural, context-aware results
- GPU auto-detection with model recommendation based on your VRAM
- Batch-based translation with resume support — safe to interrupt and continue
- Gemini first, Claude as automatic fallback
- Supports: English, Indonesian, Japanese, Korean, Chinese, and any other language

## Requirements

### Hardware

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| OS | Windows 10 | Windows 11 |
| RAM | 8 GB | 16 GB |
| GPU | — (CPU works) | NVIDIA GPU with CUDA |
| VRAM | — | 6 GB+ |

**GPU / VRAM guide for model selection:**

| VRAM | Recommended Model | Notes |
|------|-------------------|-------|
| No GPU | medium | Runs on CPU, slow but works |
| 4–6 GB | medium | Safe and reliable |
| 6–10 GB | large-v3-turbo | Best balance of speed and accuracy |
| 10 GB+ | large-v3 | Maximum accuracy |

> CPU mode works but is significantly slower. A mid-range GPU (e.g. RTX 3060 6GB) is ideal.

### Software

| Software | Version | Notes |
|----------|---------|-------|
| Windows | 10 / 11 | Only Windows is supported |
| [Python](https://www.python.org/downloads/) | 3.10+ | Check **"Add Python to PATH"** during install |
| [Node.js](https://nodejs.org/) | 18+ | Required for AI translation engines |
| NVIDIA Driver | Latest | Only if you have an NVIDIA GPU |

### AI Translation Engine (at least one required for translation)

| Engine | Install | Cost | Notes |
|--------|---------|------|-------|
| **Gemini CLI** | `npm install -g @google/gemini-cli` | Free tier available | Recommended, more permissive |
| **Claude Code** | `npm install -g @anthropic-ai/claude-code` | Paid | Fallback engine |

> Subtitle generation works without any AI engine. Translation requires at least one.

## Installation

1. **Download or clone this repository**

2. **Run `install.bat`** — it will automatically:
   - Verify Python is installed
   - Install ffmpeg (via winget or Chocolatey)
   - Install OpenAI Whisper
   - Detect your GPU and install the correct version of PyTorch (CUDA or CPU)
   - Check for Gemini CLI and Claude Code
   - Offer to pre-download a Whisper model based on your GPU

3. **Done.** Run `whisper-subtitle.bat` to start.

> If ffmpeg auto-install fails, download it manually from [gyan.dev/ffmpeg](https://www.gyan.dev/ffmpeg/builds/) and add the `bin` folder to your system PATH.

## Usage

Double-click `whisper-subtitle.bat` from any folder containing your video files.

### Menu [1] — Generate Subtitle

1. Select a video file (or all files)
2. Choose a Whisper model
3. Choose the source language (or Auto-detect)
4. Choose output format (srt / vtt / txt / all)
5. Confirm — Whisper runs locally on your machine
6. After completion, optionally translate the generated subtitle

### Menu [2] — Translate Subtitle

1. Select an existing `.srt` file (or all files)
2. Source language is auto-detected from the file content
3. Choose target language — source language is excluded from the list
4. Translation runs via Gemini (primary) → Claude (fallback if Gemini fails)

### Output Files

| File | Description |
|------|-------------|
| `video.srt` | Original subtitle from Whisper |
| `video_ID.srt` | Indonesian translation |
| `video_EN.srt` | English translation |
| `video_JA.srt` | Japanese translation |
| `video_KO.srt` | Korean translation |
| `video_ZH.srt` | Chinese translation |

## Tips

- **Slow download from Hugging Face?** Disable Cloudflare or any firewall/VPN while downloading Whisper models — they throttle Hugging Face traffic.
- **Japanese video?** Select "Japanese" explicitly as source language instead of Auto-detect for better accuracy, especially for mixed-language content.
- **Translation interrupted?** Just run it again — progress is cached in a `_tmp/` folder next to the SRT file and will resume from where it stopped.
- **Gemini vs Claude:** Gemini is the default engine and handles a wider range of content. Claude is used as a fallback if Gemini fails or is unavailable.
- **CPU mode:** Works, but expect 5–10x slower transcription compared to GPU. Use `medium` or `small` model for reasonable speed.

## Tested On

- OS: Windows 11 Pro
- Python: 3.11
- Whisper: openai-whisper (latest)
- PyTorch: CUDA 12.x

## Project Structure

```
whisper-subtitle.bat   — main menu (generate + translate)
install.bat            — one-time setup wizard
translate_srt.py       — translation engine (Gemini / Claude)
check_gpu.py           — GPU detection and PyTorch verification
```

## License

MIT — free to use, modify, and distribute.
