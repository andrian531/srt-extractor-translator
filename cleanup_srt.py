import sys
import re
import os


def ts_to_ms(ts):
    """Convert HH:MM:SS,mmm to milliseconds."""
    h, m, rest = ts.split(":")
    s, ms = rest.split(",")
    return int(h) * 3600000 + int(m) * 60000 + int(s) * 1000 + int(ms)


def ms_to_ts(ms):
    """Convert milliseconds to HH:MM:SS,mmm."""
    ms = max(0, int(ms))
    h   = ms // 3600000; ms %= 3600000
    m   = ms // 60000;   ms %= 60000
    s   = ms // 1000;    ms %= 1000
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def parse_srt(text):
    """Parse SRT content into list of [idx, start_ms, end_ms, text]."""
    blocks = []
    pattern = re.compile(
        r"(\d+)\r?\n"
        r"(\d{2}:\d{2}:\d{2},\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2},\d{3})\r?\n"
        r"([\s\S]*?)(?=\r?\n\r?\n|\Z)",
        re.MULTILINE,
    )
    for m in pattern.finditer(text.strip() + "\n\n"):
        text_content = m.group(4).strip()
        if not text_content:
            continue
        blocks.append([
            m.group(1),
            ts_to_ms(m.group(2)),
            ts_to_ms(m.group(3)),
            text_content,
        ])
    return blocks


def fix_overlaps(blocks, gap_ms=50):
    """Ensure each segment ends before the next one starts (with gap_ms buffer)."""
    fixed = 0
    for i in range(len(blocks) - 1):
        if blocks[i][2] > blocks[i + 1][1]:
            new_end = max(blocks[i][1] + 100, blocks[i + 1][1] - gap_ms)
            blocks[i][2] = new_end
            fixed += 1
    return blocks, fixed


def merge_short_segments(blocks, min_duration_ms=1200, min_chars=15):
    """
    Merge a segment into the next one if it is both:
    - shorter than min_duration_ms milliseconds, AND
    - fewer than min_chars characters
    The merged segment keeps the start time of the first and end time of the second.
    """
    if not blocks:
        return blocks, 0
    merged = []
    merge_count = 0
    i = 0
    while i < len(blocks):
        b = blocks[i]
        duration = b[2] - b[1]
        if duration < min_duration_ms and len(b[3]) < min_chars and i < len(blocks) - 1:
            nxt = blocks[i + 1]
            blocks[i + 1] = [nxt[0], b[1], nxt[2], b[3] + " " + nxt[3]]
            merge_count += 1
        else:
            merged.append(b)
        i += 1
    return merged, merge_count


def renumber(blocks):
    """Renumber all blocks sequentially starting from 1."""
    for i, b in enumerate(blocks, 1):
        b[0] = str(i)
    return blocks


def save_srt(blocks, path):
    with open(path, "w", encoding="utf-8") as f:
        for b in blocks:
            f.write(f"{b[0]}\n{ms_to_ts(b[1])} --> {ms_to_ts(b[2])}\n{b[3]}\n\n")


def cleanup(path, do_merge=True, do_fix=True):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        content = f.read()

    blocks = parse_srt(content)
    if not blocks:
        print(f"  [ERROR] No segments found in: {path}")
        return 1

    original_count = len(blocks)
    overlap_fixed  = 0
    merge_count    = 0

    if do_fix:
        blocks, overlap_fixed = fix_overlaps(blocks)

    if do_merge:
        blocks, merge_count = merge_short_segments(blocks)

    blocks = renumber(blocks)

    base, ext = os.path.splitext(path)
    out_path = base + "_clean" + ext
    save_srt(blocks, out_path)

    print(f"  Original  : {original_count} segments")
    if do_fix:
        print(f"  Overlaps  : {overlap_fixed} fixed")
    if do_merge:
        print(f"  Merged    : {merge_count} short segments")
    print(f"  Result    : {len(blocks)} segments")
    print(f"  Saved     : {out_path}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python cleanup_srt.py <file.srt> [--no-merge] [--no-fix-overlaps]")
        sys.exit(1)

    path       = sys.argv[1]
    do_merge   = "--no-merge"          not in sys.argv
    do_fix     = "--no-fix-overlaps"   not in sys.argv

    if not os.path.exists(path):
        print(f"  [ERROR] File not found: {path}")
        sys.exit(1)

    print(f"  File      : {os.path.basename(path)}")
    code = cleanup(path, do_merge=do_merge, do_fix=do_fix)
    sys.exit(code)
