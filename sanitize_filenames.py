"""
sanitize_filenames.py
---------------------
Finds video/SRT files whose names contain characters that break
Windows batch scripting with EnableDelayedExpansion (primarily '!').

Usage:
  python sanitize_filenames.py <folder> check   -> lists files, prints count first
  python sanitize_filenames.py <folder> rename  -> renames files, prints results
"""
import os
import sys


# Characters that cause problems in batch delayed expansion
PROBLEM_CHARS = ['!']

VIDEO_EXTS = {'.mp4', '.mkv', '.avi', '.mov', '.ts', '.m4v',
              '.flv', '.wmv', '.webm', '.mpeg', '.mpg'}
SRT_EXTS   = {'.srt'}
ALL_EXTS   = VIDEO_EXTS | SRT_EXTS


def sanitize_name(name: str) -> str:
    """Return a safe version of the filename (name only, no directory)."""
    base, ext = os.path.splitext(name)
    for ch in PROBLEM_CHARS:
        base = base.replace(ch, '')
    # Collapse multiple consecutive spaces that may result from removal
    while '  ' in base:
        base = base.replace('  ', ' ')
    base = base.strip()
    return base + ext


def find_problematic(folder: str):
    """
    Walk folder recursively and return list of
    (old_path, new_path, old_name, new_name) for files that need renaming.
    """
    results = []
    for root, _dirs, files in os.walk(folder):
        for fname in sorted(files):
            ext = os.path.splitext(fname)[1].lower()
            if ext not in ALL_EXTS:
                continue
            # Check if any problematic char is present
            if not any(ch in fname for ch in PROBLEM_CHARS):
                continue
            new_name = sanitize_name(fname)
            if new_name == fname:
                continue  # Nothing would change
            old_path = os.path.join(root, fname)
            new_path = os.path.join(root, new_name)
            results.append((old_path, new_path, fname, new_name))
    return results


def mode_check(folder: str):
    items = find_problematic(folder)
    print(len(items))          # First line: count (read by batch)
    for old_path, new_path, old_name, new_name in items:
        # Relative display path
        rel = os.path.relpath(old_path, folder)
        print(f"  {rel}")
        print(f"  -> {new_name}")


def mode_rename(folder: str):
    items = find_problematic(folder)
    renamed = 0
    errors  = 0
    for old_path, new_path, old_name, new_name in items:
        # Guard: skip if target already exists to avoid data loss
        if os.path.exists(new_path):
            print(f"[SKIP] Target already exists: {new_name}")
            continue
        try:
            os.rename(old_path, new_path)
            print(f"[OK]   {old_name}")
            print(f"    -> {new_name}")
            renamed += 1
        except OSError as exc:
            print(f"[ERR]  {old_name}: {exc}")
            errors += 1
    print()
    print(f"Done: {renamed} renamed, {errors} error(s).")


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: sanitize_filenames.py <folder> <check|rename>")
        sys.exit(1)

    folder = sys.argv[1]
    mode   = sys.argv[2].lower()

    if not os.path.isdir(folder):
        print(f"[ERR] Not a directory: {folder}")
        sys.exit(1)

    if mode == 'check':
        mode_check(folder)
    elif mode == 'rename':
        mode_rename(folder)
    else:
        print(f"[ERR] Unknown mode: {mode}. Use 'check' or 'rename'.")
        sys.exit(1)
