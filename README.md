# Whisper Subtitle Tools

Extract subtitles from any video file using OpenAI Whisper or WhisperX (local, offline), then translate them to any language using Gemini CLI or NLLB (offline) — all from a simple menu-driven interface.

## Features

- **Generate subtitles** from video files using Whisper or WhisperX (runs fully offline, on your machine)
- **Translate SRT files** to any language — Gemini CLI (primary) with NLLB as offline gap-fill and fallback
- **Generate + Translate** in one go — set language and target upfront, walk away
- **Cleanup SRT** — fix timestamp overlaps and merge very short segments into one
- Auto-detects source language of SRT files
- Smart target language menu — never offers translation to the same language as source
- AI detects content genre/type before translating for more natural, context-aware results
- GPU auto-detection with model recommendation based on your VRAM (NVIDIA CUDA, AMD ROCm, Apple Silicon MPS)
- Batch-based translation with resume support — safe to interrupt and continue
- Gemini primary, NLLB offline fallback — translation works even without internet
- Anti-repetition measures for NLLB output with Gemini retry for edge cases
- Translation quality report — shows how many segments came from Gemini, NLLB, retry, or fallback
- Translation preview — displays first 5 translated segments after each run
- Menu stays open after completion or error — return to menu or quit
- Supports: English, Indonesian, Japanese, Korean, Chinese, and any other language

## Requirements

### Hardware

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| OS | Windows 10 | Windows 11 |
| RAM | 8 GB | 16 GB |
| GPU | — (CPU works) | NVIDIA (CUDA), AMD (ROCm), or Apple Silicon (MPS) |
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
| **Gemini CLI** | `npm install -g @google/gemini-cli` | Free tier available | Primary engine, recommended |
| **NLLB (offline)** | `pip install transformers sentencepiece sacremoses` | Free | Offline fallback, no internet needed |

Translation priority: **Gemini** → **NLLB** (fills missed segments) → **Gemini retry** (if NLLB output is repetitive) → NLLB result as last resort.

If Gemini is not installed, translation runs fully offline via NLLB. NLLB requires ~1.3 GB model download on first use (cached locally after that).

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

3. **Done.** Run `whisper-subtitle.bat` (OpenAI Whisper) or `whisperx-subtitle.bat` (WhisperX, faster with word-level timestamps) to start.

> If ffmpeg auto-install fails, download it manually from [gyan.dev/ffmpeg](https://www.gyan.dev/ffmpeg/builds/) and add the `bin` folder to your system PATH.

## Usage

1. **Copy your video files into the project folder** — either directly or inside a `video/` subfolder to keep things organized
2. **Double-click `whisper-subtitle.bat`** — it will automatically detect all video and subtitle files recursively

> Output files (`.srt`, translations, temp cache) are saved next to each video file — so if your videos are in `video/`, all outputs go there too, keeping the project root clean.
>
> Do not move just the `.bat` file alone — it requires `translate_srt.py` and `check_gpu.py` to be in the same directory.

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
4. Translation runs via Gemini (primary) → NLLB offline (gap-fill and fallback)

### Menu [4] — Cleanup SRT

1. Select an existing `.srt` file (or all files)
2. Script fixes overlapping timestamps and merges segments shorter than 1.2 seconds with fewer than 15 characters into the next segment
3. Output saved as `filename_clean.srt` — original file is not modified

> Useful for cleaning up Whisper output before translation, or fixing timing issues after editing.

### Menu [3] — Generate + Translate (Set & Forget)

1. Select a video file (or all files)
2. Choose a Whisper model
3. Choose the source language (or Auto-detect)
4. Choose output format
5. Choose target language — asked upfront before processing starts
6. Confirm — Whisper runs, then translation starts automatically with no further prompts

> Use this when you want to walk away and come back to find everything done.

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
- **NLLB first run:** The NLLB model (~1.3 GB) downloads automatically from Hugging Face on first use and is cached locally — only happens once.
- **Gemini vs NLLB:** Gemini is the default engine and produces more natural translations. NLLB is offline-capable and serves as an automatic gap-fill and fallback.
- **CPU mode:** Works, but expect 5–10x slower transcription compared to GPU. Use `medium` or `small` model for reasonable speed.
- **Apple Silicon (Mac)?** Whisper uses MPS (GPU acceleration). WhisperX falls back to CPU — CTranslate2 does not support MPS.

## Tested On

- OS: Windows 11 Pro
- Python: 3.13
- Whisper: openai-whisper (latest)
- WhisperX: 3.8.1
- PyTorch: 2.6.0+cu124
- NLLB: facebook/nllb-200-distilled-1.3B

## Project Structure

```
whisper-subtitle.bat    — main menu using OpenAI Whisper
whisperx-subtitle.bat   — main menu using WhisperX (faster, word-level timestamps)
install.bat             — one-time setup wizard
translate_srt.py        — translation engine (Gemini primary, NLLB offline fallback)
cleanup_srt.py          — SRT post-processor (fix overlaps, merge short segments)
check_gpu.py            — GPU detection and PyTorch verification
```

## License

The scripts in this repository (`*.bat`, `*.py`) are licensed under the **MIT License** — free to use, modify, and distribute, including for commercial purposes.

### Third-Party Model Licenses

| Component | License | Commercial Use |
|-----------|---------|----------------|
| [openai-whisper](https://github.com/openai/whisper) | MIT | Yes |
| [WhisperX](https://github.com/m-bain/whisperX) | MIT | Yes |
| [faster-whisper](https://github.com/SYSTRAN/faster-whisper) | MIT | Yes |
| [HuggingFace Transformers](https://github.com/huggingface/transformers) | Apache 2.0 | Yes |
| [NLLB-200 model](https://huggingface.co/facebook/nllb-200-distilled-1.3B) (Meta) | CC BY-NC 4.0 | **No** |

> **Important:** The NLLB translation model (`facebook/nllb-200-distilled-*`) is licensed under [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/) — **non-commercial use only**. If you use this tool commercially, disable NLLB and use Gemini or another engine instead.
