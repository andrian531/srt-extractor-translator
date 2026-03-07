import sys
import os
import re
import subprocess
import time


def detect_claude_cmd():
    import shutil
    for cmd in ["claude", "claude-code", "claudecode"]:
        found = shutil.which(cmd)
        if found:
            return found
    appdata = os.environ.get("APPDATA", "")
    localappdata = os.environ.get("LOCALAPPDATA", "")
    programfiles = os.environ.get("ProgramFiles", "")
    programfiles86 = os.environ.get("ProgramFiles(x86)", "")
    for path in [
        os.path.join(appdata,        "npm", "claude.cmd"),
        os.path.join(appdata,        "npm", "claude"),
        os.path.join(localappdata,   "npm", "claude.cmd"),
        os.path.join(localappdata,   "npm", "claude"),
        os.path.join(programfiles,   "nodejs", "claude.cmd"),
        os.path.join(programfiles86, "nodejs", "claude.cmd"),
    ]:
        if os.path.exists(path):
            return path
    return None


def detect_gemini_cmd():
    import shutil
    for cmd in ["gemini", "gemini-cli"]:
        found = shutil.which(cmd)
        if found:
            return found
    appdata = os.environ.get("APPDATA", "")
    localappdata = os.environ.get("LOCALAPPDATA", "")
    for path in [
        os.path.join(appdata,      "npm", "gemini.cmd"),
        os.path.join(appdata,      "npm", "gemini"),
        os.path.join(localappdata, "npm", "gemini.cmd"),
        os.path.join(localappdata, "npm", "gemini"),
    ]:
        if os.path.exists(path):
            return path
    return None


def detect_available_engines():
    engines = {}
    claude = detect_claude_cmd()
    if claude:
        engines["claude"] = claude
    gemini = detect_gemini_cmd()
    if gemini:
        engines["gemini"] = gemini
    return engines


def resolve_cmd(cmd):
    import shutil
    if os.path.isabs(cmd) and os.path.exists(cmd):
        return cmd
    if sys.platform == "win32":
        appdata = os.environ.get("APPDATA", "")
        localappdata = os.environ.get("LOCALAPPDATA", "")
        name = os.path.basename(cmd).replace(".cmd", "").replace(".CMD", "")
        for path in [
            os.path.join(appdata,      "npm", name + ".cmd"),
            os.path.join(appdata,      "npm", name),
            os.path.join(localappdata, "npm", name + ".cmd"),
            os.path.join(localappdata, "npm", name),
        ]:
            if os.path.exists(path):
                return path
    found = shutil.which(cmd)
    if found:
        return found
    return cmd


def detect_language(srt_path):
    """Detect the source language of an SRT file.
    Returns: 'en', 'id', 'ja', 'ko', 'zh', or 'unknown'
    """
    try:
        with open(srt_path, "r", encoding="utf-8", errors="replace") as f:
            raw = f.read(8000)

        lines = []
        for line in raw.split("\n"):
            line = line.strip()
            if not line or line.isdigit() or "-->" in line:
                continue
            lines.append(line)
        text = " ".join(lines)

        if not text.strip():
            return "unknown"

        # Japanese: hiragana / katakana characters
        hiragana_kata = sum(1 for c in text if "\u3040" <= c <= "\u30ff")
        if hiragana_kata > 5:
            return "ja"

        # Korean: hangul characters
        hangul = sum(1 for c in text if "\uac00" <= c <= "\ud7a3")
        if hangul > 5:
            return "ko"

        # Chinese: CJK ideographs (no kana overlap)
        cjk = sum(1 for c in text if "\u4e00" <= c <= "\u9fff")
        if cjk > 50 and hiragana_kata == 0 and hangul == 0:
            return "zh"

        text_lower = text.lower()

        id_words = [
            "yang", "dan", "ini", "itu", "tidak", "ada", "dengan",
            "untuk", "saya", "kamu", "aku", "adalah", "sudah", "akan", "bisa",
        ]
        en_words = [
            "the", "and", "you", "that", "this", "with", "have",
            "for", "are", "but", "not", "from", "they", "what", "just",
        ]
        found_id = sum(1 for w in id_words if re.search(r"\b" + w + r"\b", text_lower))
        found_en = sum(1 for w in en_words if re.search(r"\b" + w + r"\b", text_lower))

        if found_id >= 4 and found_id > found_en:
            return "id"
        if found_en >= 4:
            return "en"
        return "unknown"

    except Exception:
        return "unknown"


def parse_srt(content):
    blocks = re.split(r'\n\s*\n', content.strip())
    parsed = []
    for block in blocks:
        lines = block.strip().split('\n')
        if len(lines) >= 3:
            idx = lines[0].strip()
            ts = lines[1].strip()
            text = '\n'.join(lines[2:]).strip()
            if text:
                parsed.append((idx, ts, text))
    return parsed


def estimate_token_cost(blocks):
    total_chars = sum(len(text) for _, _, text in blocks)
    estimated_input  = int(total_chars / 4 * 1.3)
    estimated_output = int(total_chars / 4)
    return estimated_input, estimated_output


def check_engine_responsive(engine_cmd, engine_type):
    try:
        result = subprocess.run(
            [engine_cmd],
            input="Reply with only the word: OK",
            capture_output=True, text=True, timeout=60,
            encoding="utf-8", errors="replace"
        )
        if result.returncode == 0 and result.stdout.strip():
            return True, result.stdout.strip()
        return False, (result.stderr or result.stdout or "no output").strip()
    except FileNotFoundError as e:
        return False, f"File not found: {e}"
    except subprocess.TimeoutExpired:
        return False, "Timeout (>60s)"
    except Exception as e:
        return False, str(e)


def detect_genre(engine_cmd, engine_type, srt_path, sample_lines=60):
    """Ask the AI to identify the genre/type of content from a sample of the SRT.
    Returns a short genre description string, or empty string if detection fails.
    """
    try:
        with open(srt_path, "r", encoding="utf-8", errors="replace") as f:
            raw = f.read(12000)

        text_lines = []
        for line in raw.split("\n"):
            line = line.strip()
            if not line or line.isdigit() or "-->" in line:
                continue
            text_lines.append(line)
            if len(text_lines) >= sample_lines:
                break

        sample = "\n".join(text_lines)
        if not sample.strip():
            return ""

        prompt = (
            "Based on the following subtitle excerpt, identify the genre and type of this content "
            "in ONE concise phrase (e.g. 'Japanese medical drama', 'Korean romantic comedy', "
            "'sci-fi action thriller', 'adult role-play scenario set in a clinic', etc.).\n"
            "Be specific about setting, tone, and any notable themes.\n"
            "Reply with ONLY the genre/type description, nothing else.\n\n"
            f"Subtitle excerpt:\n{sample}"
        )

        rc, stdout, _ = run_translate_prompt(engine_cmd, engine_type, prompt)
        if rc == 0 and stdout.strip():
            # Take first line only, cap at 300 chars
            return stdout.strip().split("\n")[0][:300]
        return ""
    except Exception:
        return ""


def run_translate_prompt(engine_cmd, engine_type, prompt):
    try:
        result = subprocess.run(
            [engine_cmd],
            input=prompt,
            capture_output=True, text=True, timeout=300,
            encoding="utf-8", errors="replace"
        )
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return -1, "", "TIMEOUT"
    except FileNotFoundError as e:
        return -2, "", str(e)
    except Exception as e:
        return -3, "", str(e)


def translate_with_claude(claude_cmd, srt_path, output_path, engine_type="claude", target_lang="Indonesian", source_lang=""):
    claude_cmd = resolve_cmd(claude_cmd)
    engine_label = "Claude" if engine_type == "claude" else "Gemini"
    print(f"  Engine         : {engine_label}")
    print(f"  Path           : {claude_cmd}")
    print(f"  Target language: {target_lang}")

    with open(srt_path, "r", encoding="utf-8", errors="replace") as f:
        content = f.read()

    blocks = parse_srt(content)
    if not blocks:
        print("  [ERROR] No text found in SRT file")
        return False

    # Detect genre/content type for better translation context
    print(f"  Detecting content genre...")
    genre = detect_genre(claude_cmd, engine_type, srt_path)
    if genre:
        print(f"  Genre          : {genre}")
    else:
        print(f"  Genre          : (not detected, proceeding without)")

    total = len(blocks)
    print(f"  Total segments : {total}")

    est_input, est_output = estimate_token_cost(blocks)
    est_total = est_input + est_output
    cost = (est_input / 1_000_000 * 3.0) + (est_output / 1_000_000 * 15.0)
    print(f"  Est. tokens    : ~{est_total:,} ({est_input:,} input + {est_output:,} output)")
    print(f"  Est. cost      : ~${cost:.4f}")
    if est_total > 50_000:
        print(f"  [!] Large file - this may take a while")

    print(f"  Checking {engine_label}...")
    ok, msg = check_engine_responsive(claude_cmd, engine_type)
    if not ok:
        print(f"  [ERROR] {engine_label} not responding: {msg}")
        print(f"          Token limit may be exhausted or connection issue.")
        return False
    print(f"  [OK] {engine_label} responsive ({msg[:50]})")
    print(f"  Translating in batches...")

    MAX_TOKENS_PER_BATCH = 300
    GEMINI_BATCH_DELAY   = 3    # seconds between batches (Gemini only)
    MAX_RETRY            = 2    # retry attempts on failure or timeout

    def est_tok(text):
        return max(1, len(text) // 4)

    batches = []
    cur_batch = []
    cur_tokens = 0
    for block in blocks:
        t = est_tok(block[2])
        if cur_tokens + t > MAX_TOKENS_PER_BATCH and cur_batch:
            batches.append(cur_batch)
            cur_batch = [block]
            cur_tokens = t
        else:
            cur_batch.append(block)
            cur_tokens += t
    if cur_batch:
        batches.append(cur_batch)

    total_batch = len(batches)
    print(f"  Total batches  : {total_batch} (max ~{MAX_TOKENS_PER_BATCH} tokens/batch)")

    tmp_dir = output_path + "_tmp"
    os.makedirs(tmp_dir, exist_ok=True)
    print(f"  Temp folder    : {tmp_dir}")

    translated_blocks = []

    for batch_num, batch in enumerate(batches, 1):
        batch_tokens = sum(est_tok(t) for _, _, t in batch)
        tmp_file = os.path.join(tmp_dir, f"batch_{batch_num:04d}.txt")

        if os.path.exists(tmp_file):
            with open(tmp_file, "r", encoding="utf-8") as f:
                cached = f.read()
            translated_lines = {}
            for line in cached.strip().split("\n"):
                m = re.match(r"\[(\d+)\]\s*(.*)", line.strip())
                if m and m.group(2).strip():
                    translated_lines[m.group(1)] = m.group(2)
            matched = sum(1 for idx, _, _ in batch if idx in translated_lines)
            if matched > 0:
                print(f"  Batch {batch_num}/{total_batch} - resumed from cache ({matched}/{len(batch)} match)")
                for idx, ts, text in batch:
                    translated_blocks.append((idx, ts, translated_lines.get(idx, text)))
                continue
            else:
                print(f"  Batch {batch_num}/{total_batch} - cache invalid, reprocessing")
                os.remove(tmp_file)

        if engine_type == "gemini" and batch_num > 1:
            time.sleep(GEMINI_BATCH_DELAY)

        print(f"  Batch {batch_num}/{total_batch} ({len(batch)} segments, ~{batch_tokens} tokens)...", end="", flush=True)

        lines_to_translate = [f"[{idx}] {text}" for idx, ts, text in batch]

        LANG_NAMES = {
            "ja": "Japanese", "ko": "Korean", "zh": "Chinese",
            "en": "English",  "id": "Indonesian",
        }
        src_label = LANG_NAMES.get(source_lang, "") if source_lang else ""
        from_clause = f" from {src_label}" if src_label else ""
        genre_line = f"Content type: {genre}\n" if genre else ""

        prompt = (
            f"You are a professional subtitle translator.\n"
            f"Translate the following subtitle lines{from_clause} to {target_lang}.\n"
            f"{genre_line}"
            "\nGuidelines:\n"
            "- Write natural, fluent translations that feel native in the target language\n"
            "- Preserve the speaker's tone, emotion, and personality (casual, formal, excited, sad, etc.)\n"
            "- Adapt idioms and cultural expressions naturally — avoid word-for-word literal translation\n"
            "- Use vocabulary and phrasing appropriate to the content type above\n"
            "- Keep translations concise so they are easy to read quickly as subtitles\n"
            "- Keep the [number] prefix on each line exactly as-is\n"
            "- Output ONLY the translated lines, no comments or explanations\n\n"
            + "\n".join(lines_to_translate)
        )

        try:
            rc, stdout, stderr = -1, "", ""
            for attempt in range(1, MAX_RETRY + 2):
                rc, stdout, stderr = run_translate_prompt(claude_cmd, engine_type, prompt)
                if rc == 0 and stdout.strip():
                    break
                if attempt <= MAX_RETRY:
                    wait = attempt * 5
                    tag = "TIMEOUT" if stderr == "TIMEOUT" else f"rc={rc}"
                    print(f" {tag}, retry {attempt}/{MAX_RETRY} in {wait}s...", end="", flush=True)
                    time.sleep(wait)

            if rc != 0 or not stdout.strip():
                print(f" FAILED (rc={rc})")
                print(f"      stdout: {repr(stdout[:300])}")
                print(f"      stderr: {repr(stderr[:300])}")
                for idx, ts, text in batch:
                    translated_blocks.append((idx, ts, text))
                continue
            result_stdout = stdout

            translated_lines = {}
            for line in result_stdout.strip().split("\n"):
                m = re.match(r"\[(\d+)\]\s*(.*)", line.strip())
                if m:
                    translated_lines[m.group(1)] = m.group(2)

            matched = sum(1 for idx, _, _ in batch if idx in translated_lines)
            print(f" OK ({matched}/{len(batch)} match)")

            debug_file = os.path.join(tmp_dir, f"batch_{batch_num:04d}_raw.txt")
            with open(debug_file, "w", encoding="utf-8") as f:
                f.write(result_stdout)

            if matched > 0:
                with open(tmp_file, "w", encoding="utf-8") as f:
                    for idx, _, _ in batch:
                        text_out = translated_lines.get(idx, "")
                        f.write(f"[{idx}] {text_out}\n")
            else:
                print(f"      [!] 0 matches - cache not saved, will retry next run")

            for idx, ts, text in batch:
                translated_blocks.append((idx, ts, translated_lines.get(idx, text)))

        except FileNotFoundError as e:
            print(f" ERROR")
            print(f"  [ERROR] Cannot run {engine_label}: {e}")
            print(f"          Path: {claude_cmd}")
            return False
        except Exception as e:
            print(f" ERROR: {type(e).__name__}: {e}")
            for idx, ts, text in batch:
                translated_blocks.append((idx, ts, text))

    with open(output_path, "w", encoding="utf-8") as f:
        for idx, ts, text in translated_blocks:
            f.write(f"{idx}\n{ts}\n{text}\n\n")

    translated_count = sum(
        1 for orig, trans in zip(blocks, translated_blocks)
        if orig[2] != trans[2]
    )

    if translated_count == total:
        import shutil as _shutil
        _shutil.rmtree(tmp_dir, ignore_errors=True)
        print(f"  [OK] Temp folder removed")
    elif translated_count > 0:
        print(f"  [!] Partial translation — temp folder kept for resume: {tmp_dir}")
    else:
        print(f"  [!] Temp folder kept for debugging: {tmp_dir}")
        print(f"      Check *_raw.txt files to see engine output")

    print(f"  [DONE] {translated_count}/{total} segments translated")
    print(f"  Saved  : {output_path}")
    return True


if __name__ == "__main__":
    # Special mode: detect source language of an SRT file
    if len(sys.argv) >= 3 and sys.argv[1] == "--detect-lang":
        print(detect_language(sys.argv[2]))
        sys.exit(0)

    if len(sys.argv) < 2:
        print("Usage: python translate_srt.py <file.srt> [engine_cmd] [engine_type] [target_lang]")
        sys.exit(1)

    srt_path          = sys.argv[1]
    forced_engine_cmd = sys.argv[2] if len(sys.argv) >= 3 else None
    forced_engine_type= sys.argv[3] if len(sys.argv) >= 4 else None
    target_lang       = sys.argv[4] if len(sys.argv) >= 5 else "Indonesian"

    if not os.path.exists(srt_path):
        print(f"[ERROR] File not found: {srt_path}")
        sys.exit(1)

    # Determine output filename suffix from target language
    LANG_SUFFIX = {
        "english":           "_EN",
        "indonesian":        "_ID",
        "japanese":          "_JA",
        "korean":            "_KO",
        "chinese":           "_ZH",
        "chinese (mandarin)":"_ZH",
        "mandarin":          "_ZH",
    }
    suffix = LANG_SUFFIX.get(target_lang.lower(), "_TRANSLATED")
    output_path = os.path.splitext(srt_path)[0] + suffix + ".srt"

    # Skip if SRT is already in the target language
    LANG_CODES = {
        "english": "en", "indonesian": "id", "japanese": "ja",
        "korean": "ko", "chinese": "zh", "chinese (mandarin)": "zh",
    }
    target_code   = LANG_CODES.get(target_lang.lower(), "")
    detected_lang = detect_language(srt_path)
    if target_code and detected_lang == target_code:
        print(f"[INFO] SRT is already in {target_lang}, skipping translation.")
        sys.exit(0)

    # Called from bat with engine pre-selected
    if forced_engine_cmd and forced_engine_type:
        chosen_cmd  = forced_engine_cmd
        chosen_type = forced_engine_type
        print(f"[OK] Engine: {chosen_type} -> {chosen_cmd}")
    else:
        # Interactive mode: show engine selection
        engines = detect_available_engines()
        if not engines:
            print("[ERROR] No translation engine found.")
            print("  Install Claude : npm install -g @anthropic-ai/claude-code")
            print("  Install Gemini : npm install -g @google/gemini-cli")
            sys.exit(1)

        print("\n  Available engines:")
        engine_list = list(engines.items())
        for i, (etype, ecmd) in enumerate(engine_list, 1):
            label = "Claude Code" if etype == "claude" else "Gemini CLI"
            print(f"   [{i}] {label}")
            print(f"       {ecmd}")

        if len(engine_list) == 1:
            print(f"  (only 1 engine available, auto-selected)")
            chosen_type, chosen_cmd = engine_list[0]
        else:
            choice = input(f"  Choose [1-{len(engine_list)}]: ").strip()
            try:
                idx = int(choice) - 1
                chosen_type, chosen_cmd = engine_list[idx]
            except (ValueError, IndexError):
                chosen_type, chosen_cmd = engine_list[0]
                print(f"  Invalid input, using {chosen_type}")

        answer = input(f"  Translate to {target_lang}? (Y/N): ").strip().lower()
        if answer != "y":
            print("[INFO] Translation skipped.")
            sys.exit(0)

    print(f"\n  Translating  : {os.path.basename(srt_path)}")
    print(f"  Target       : {target_lang}")
    print(f"  Output       : {os.path.basename(output_path)}")
    print(f"  Original SRT : preserved")
    print()

    success = translate_with_claude(chosen_cmd, srt_path, output_path, chosen_type, target_lang, detected_lang)
    sys.exit(0 if success else 1)
