"""
list_media.py  –  Safe file lister for whisper-subtitle.bat
------------------------------------------------------------
Outputs a numbered list of media files to stdout so that
batch scripts can read them without delayed-expansion issues.

Usage:
  python list_media.py <folder> video             -> list video files
  python list_media.py <folder> srt               -> list SRT files (non-translated)
  python list_media.py <folder> srt-cleanup       -> list SRT files (exclude _clean too)
  python list_media.py <folder> get <N>           -> print full path of item N
  python list_media.py <folder> check-srt <path>  -> print [SRT] if .srt exists beside video

Output format for list modes:
  Line 1: total count
  Lines 2+: one absolute path per line  (no numbering, batch adds it)
"""

import os
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

VIDEO_EXTS = {'.mp4', '.mkv', '.avi', '.mov', '.ts', '.m4v',
              '.flv', '.wmv', '.webm', '.mpeg', '.mpg'}

TRANSLATED_SUFFIXES = ('_en', '_id', '_ja', '_ko', '_zh', '_translated')


def is_translated_srt(name_no_ext: str) -> bool:
    low = name_no_ext.lower()
    return any(low.endswith(s) for s in TRANSLATED_SUFFIXES)


def list_videos(folder: str):
    found = []
    for root, _dirs, files in os.walk(folder):
        for f in sorted(files):
            if os.path.splitext(f)[1].lower() in VIDEO_EXTS:
                found.append(os.path.join(root, f))
    found.sort()
    print(len(found))
    for p in found:
        print(p)


def list_srts(folder: str, exclude_clean: bool = False):
    found = []
    for root, _dirs, files in os.walk(folder):
        for f in sorted(files):
            base, ext = os.path.splitext(f)
            if ext.lower() != '.srt':
                continue
            if is_translated_srt(base):
                continue
            if exclude_clean and base.lower().endswith('_clean'):
                continue
            found.append(os.path.join(root, f))
    found.sort()
    print(len(found))
    for p in found:
        print(p)


def get_item(folder: str, n: int, mode: str):
    """Re-list and return the Nth item (1-based)."""
    items = []
    if mode == 'video':
        for root, _dirs, files in os.walk(folder):
            for f in sorted(files):
                if os.path.splitext(f)[1].lower() in VIDEO_EXTS:
                    items.append(os.path.join(root, f))
    else:
        for root, _dirs, files in os.walk(folder):
            for f in sorted(files):
                base, ext = os.path.splitext(f)
                if ext.lower() != '.srt':
                    continue
                if is_translated_srt(base):
                    continue
                items.append(os.path.join(root, f))
    items.sort()
    if 1 <= n <= len(items):
        print(items[n - 1])
    else:
        print('')


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print('0')
        sys.exit(0)

    folder = sys.argv[1]
    cmd    = sys.argv[2].lower()

    if not os.path.isdir(folder):
        print('0')
        sys.exit(1)

    if cmd == 'video':
        list_videos(folder)
    elif cmd == 'srt':
        list_srts(folder, exclude_clean=False)
    elif cmd == 'srt-cleanup':
        list_srts(folder, exclude_clean=True)
    elif cmd == 'get':
        n    = int(sys.argv[3]) if len(sys.argv) > 3 else 0
        mode = sys.argv[4].lower() if len(sys.argv) > 4 else 'video'
        get_item(folder, n, mode)
    else:
        print('0')
