"""
Script debug: test output format Claude/Gemini dengan 5 baris sample.
Jalankan: python debug_engine.py claude
      atau: python debug_engine.py gemini
"""
import sys
import subprocess
import shutil
import os

def find_cmd(name):
    found = shutil.which(name)
    if found:
        return found
    appdata = os.environ.get("APPDATA", "")
    localappdata = os.environ.get("LOCALAPPDATA", "")
    for path in [
        os.path.join(appdata,      "npm", name + ".cmd"),
        os.path.join(localappdata, "npm", name + ".cmd"),
        os.path.join(appdata,      "npm", name),
    ]:
        if os.path.exists(path):
            return path
    return None

engine = sys.argv[1].lower() if len(sys.argv) > 1 else "claude"
cmd_path = find_cmd(engine)

if not cmd_path:
    print(f"[ERROR] {engine} tidak ditemukan")
    sys.exit(1)

print(f"Engine : {engine}")
print(f"Path   : {cmd_path}")
print()

test_lines = [
    "[1] Oh",
    "[2] Yeah, I'm almost there",
    "[5] Well, I haven't even started, but you already look like a slut.",
    "[14] Oh yeah, you've got some nice tits",
    "[18] hmm do you like them don't worry I'll make you talk bitch",
]

prompt = (
    "Terjemahkan baris-baris berikut ke Bahasa Indonesia. "
    "Pertahankan prefix [angka] di tiap baris persis seperti aslinya. "
    "Output HANYA baris terjemahan, tanpa komentar atau penjelasan lain.\n\n"
    + "\n".join(test_lines)
)

print("=== PROMPT ===")
print(prompt)
print()

# Test method 1: -p flag
print("=== METHOD 1: -p flag ===")
try:
    if engine == "claude":
        cmd = [cmd_path, "-p", prompt, "--dangerously-skip-permissions"]
    else:
        cmd = [cmd_path, "-p", prompt]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=60, encoding="utf-8", errors="replace")
    print(f"returncode : {r.returncode}")
    print(f"stdout raw : {repr(r.stdout[:300])}")
    if r.stderr:
        print(f"stderr     : {repr(r.stderr[:200])}")
except subprocess.TimeoutExpired:
    print("TIMEOUT (60s)")
except Exception as e:
    print(f"ERROR: {e}")

print()

# Test method 2: stdin pipe
print("=== METHOD 2: stdin pipe ===")
try:
    cmd = [cmd_path]
    r = subprocess.run(cmd, input=prompt, capture_output=True, text=True, timeout=60, encoding="utf-8", errors="replace")
    print(f"returncode : {r.returncode}")
    print(f"stdout raw : {repr(r.stdout[:300])}")
    if r.stderr:
        print(f"stderr     : {repr(r.stderr[:200])}")
except subprocess.TimeoutExpired:
    print("TIMEOUT (60s)")
except Exception as e:
    print(f"ERROR: {e}")