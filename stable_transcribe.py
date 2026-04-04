import os
import sys
import argparse
import torch
import warnings

# Suppress warnings for cleaner output
warnings.filterwarnings("ignore")

def transcribe():
    parser = argparse.ArgumentParser(description="Stable Whisper Transcriber")
    parser.add_argument("input_file", help="Path to the video/audio file")
    parser.add_argument("--engine", default="faster-whisper", choices=["whisper", "faster-whisper"], help="Transcription engine to use")
    parser.add_argument("--model", default="medium", help="Whisper model size (tiny, base, small, medium, large-v3, etc.)")
    parser.add_argument("--language", default=None, help="Source language")
    parser.add_argument("--device", default="cpu", help="Device to use (cpu or cuda)")
    parser.add_argument("--output_dir", default=".", help="Directory to save output")
    parser.add_argument("--output_format", default="srt", help="Output format (srt, vtt, txt, all)")
    
    args = parser.parse_args()

    # Verify input file existence
    if not os.path.exists(args.input_file):
        print(f"[ERROR] Input file not found: {args.input_file}")
        sys.exit(1)

    try:
        import stable_whisper
    except ImportError:
        print("[ERROR] stable-whisper is not installed. Please run: pip install stable-whisper")
        sys.exit(1)

    print(f"[*] Initializing {args.engine} with Stable TS...")
    print(f"[*] Model: {args.model} | Device: {args.device} | Language: {args.language or 'Auto'}")

    # Load model based on engine
    if args.engine == "faster-whisper":
        model = stable_whisper.load_faster_whisper(args.model, device=args.device)
    else:
        model = stable_whisper.load_model(args.model, device=args.device)

    # Transcription parameters
    transcribe_args = {
        "language": args.language,
        "condition_on_previous_text": False,
        "vad": True  # Try using Voice Activity Detection
    }

    print(f"[*] Transcribing: {os.path.basename(args.input_file)}")
    
    try:
        # Run transcription with VAD
        result = model.transcribe(args.input_file, **transcribe_args)
    except Exception as e:
        if "403" in str(e) or "rate limit" in str(e).lower() or "VAD" in str(e):
            print(f"[WARN] VAD model download failed (GitHub Rate Limit). Retrying without VAD...")
            transcribe_args["vad"] = False
            result = model.transcribe(args.input_file, **transcribe_args)
        else:
            raise e

    # Handle output
    base_name = os.path.splitext(os.path.basename(args.input_file))[0]
    
    if args.output_format == "all":
        formats = ["srt", "vtt", "txt"]
    else:
        formats = [args.output_format]

    for fmt in formats:
        output_path = os.path.join(args.output_dir, f"{base_name}.{fmt}")
        if fmt == "srt":
            result.to_srt_vtt(output_path, word_level=False)
        elif fmt == "vtt":
            result.to_srt_vtt(output_path, word_level=False)
        elif fmt == "txt":
            result.to_txt(output_path)
        print(f"[OK] Saved: {output_path}")

if __name__ == "__main__":
    transcribe()
