import sys
import os
import re
import subprocess
import time


# ---------------------------------------------------------------------------
# NLLB language mappings
# ---------------------------------------------------------------------------
NLLB_LANG_MAP = {
    "ja": "jpn_Jpan",
    "ko": "kor_Hang",
    "zh": "zho_Hans",
    "en": "eng_Latn",
    "id": "ind_Latn",
}

TARGET_LANG_TO_CODE = {
    "indonesian":        "id",
    "english":           "en",
    "japanese":          "ja",
    "korean":            "ko",
    "chinese":           "zh",
    "chinese (mandarin)":"zh",
    "mandarin":          "zh",
}


# ---------------------------------------------------------------------------
# Engine detection
# ---------------------------------------------------------------------------
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


def resolve_cmd(cmd):
    import shutil
    if not cmd:
        return cmd
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


# ---------------------------------------------------------------------------
# SRT utilities
# ---------------------------------------------------------------------------
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

        hiragana_kata = sum(1 for c in text if "\u3040" <= c <= "\u30ff")
        if hiragana_kata > 5:
            return "ja"

        hangul = sum(1 for c in text if "\uac00" <= c <= "\ud7a3")
        if hangul > 5:
            return "ko"

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


# ---------------------------------------------------------------------------
# Pre/post processing utilities
# ---------------------------------------------------------------------------
def preprocess_subtitle_text(text):
    """Normalize subtitle text before sending to translation engine."""
    # Join multi-line subtitle into single line
    text = re.sub(r'\n+', ' ', text).strip()
    # Collapse multiple spaces
    text = re.sub(r' {2,}', ' ', text)
    return text


def preprocess_for_nllb(text, source_lang=""):
    """Clean subtitle text before NLLB translation."""
    text = re.sub(r'\n+', ' ', text).strip()
    text = re.sub(r' {2,}', ' ', text)
    if source_lang == 'ja':
        # Collapse highly repetitive Japanese sounds (Whisper transcription artifact)
        # e.g. "はぁはぁはぁはぁはぁ" → "はぁはぁ..."
        text = re.sub(r'([ぁ-んァ-ン]{1,3})[、。　\s]*(?:\1[、。　\s]*){3,}', r'\1\1...', text)
    return text.strip()


def postprocess_nllb_output(text):
    """Fix common NLLB output issues."""
    # Collapse multiple spaces
    text = re.sub(r' {2,}', ' ', text).strip()
    # Fix space before punctuation
    text = re.sub(r'\s+([.,;!?])', r'\1', text)
    return text


def wrap_translated_line(text, max_chars=42):
    """Wrap translated text to max_chars per line, max 2 lines.
    Finds the best split point near the midpoint of the text.
    """
    if len(text) <= max_chars:
        return text
    # If already has newline, check if it's OK
    if '\n' in text:
        lines = [l.strip() for l in text.split('\n') if l.strip()]
        if all(len(l) <= max_chars for l in lines[:2]):
            return '\n'.join(lines[:2])

    # Find best split point near midpoint
    mid = len(text) // 2
    best_split = -1
    # Search outward from midpoint for a space
    for radius in range(mid):
        left = mid - radius
        right = mid + radius
        if left > 0 and text[left] == ' ':
            best_split = left
            break
        if right < len(text) - 1 and text[right] == ' ':
            best_split = right
            break

    if best_split > 0:
        line1 = text[:best_split].strip()
        line2 = text[best_split:].strip()
        return line1 + '\n' + line2
    return text


def get_register_note(genre, target_lang):
    """Return additional prompt note about language register based on genre."""
    if not genre:
        return ""
    genre_lower = genre.lower()
    casual_keywords = {"drama", "romance", "comedy", "adult", "role", "clinic",
                       "school", "office", "home", "family", "daily", "slice"}
    if any(k in genre_lower for k in casual_keywords):
        if target_lang.lower() == "indonesian":
            return (
                "- Use natural casual Indonesian for informal dialogue "
                "(prefer 'aku/kamu' over 'saya/Anda' when tone is casual)\n"
            )
        return "- Use natural casual language appropriate for informal conversation\n"
    return ""


def build_batches(blocks, max_tokens=200, min_tokens_for_break=100):
    """Build translation batches that prefer to end at sentence boundaries.
    Breaks at sentence-ending punctuation when past min_tokens_for_break,
    or at max_tokens regardless.
    """
    SENTENCE_END = re.compile(r'[。！？!?]\s*$')
    batches, cur_batch, cur_tokens = [], [], 0

    for block in blocks:
        t = max(1, len(block[2]) // 4)
        cur_batch.append(block)
        cur_tokens += t

        over_max = cur_tokens >= max_tokens
        at_sentence = bool(SENTENCE_END.search(block[2]))

        if over_max or (at_sentence and cur_tokens >= min_tokens_for_break):
            batches.append(cur_batch)
            cur_batch, cur_tokens = [], 0

    if cur_batch:
        batches.append(cur_batch)
    return batches


def detect_artifacts(translated_blocks, source_lang=""):
    """Detect translation quality issues for reporting."""
    issues = []

    for idx, ts, text in translated_blocks:
        stripped = text.strip()
        # Word-break artifacts
        if stripped.endswith('-'):
            issues.append(f"[{idx}] word-break at end")
        if re.match(r'^-[a-zA-Z\u00C0-\u017E]', stripped):
            issues.append(f"[{idx}] word-break at start")

    # Untranslated source language characters remaining
    if source_lang == 'ja':
        ja_pat = re.compile(r'[\u3040-\u30ff]')
        for idx, ts, text in translated_blocks:
            if ja_pat.search(text):
                issues.append(f"[{idx}] untranslated Japanese chars")
    elif source_lang == 'ko':
        ko_pat = re.compile(r'[\uac00-\ud7a3]')
        for idx, ts, text in translated_blocks:
            if ko_pat.search(text):
                issues.append(f"[{idx}] untranslated Korean chars")

    # Lines too long for subtitle display
    for idx, ts, text in translated_blocks:
        for line in text.split('\n'):
            if len(line) > 60:
                issues.append(f"[{idx}] long line ({len(line)} chars)")
                break

    return issues


# ---------------------------------------------------------------------------
# Gemini helpers
# ---------------------------------------------------------------------------
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


# ---------------------------------------------------------------------------
# NLLB local translation
# ---------------------------------------------------------------------------
def get_nllb_model(script_dir=None):
    """Return NLLB model name based on .nllb marker file."""
    if script_dir:
        nllb_file = os.path.join(script_dir, ".nllb")
        if os.path.exists(nllb_file):
            with open(nllb_file, "r", encoding="utf-8") as f:
                ver = f.read().strip()
            if "1.3B" in ver:
                return "facebook/nllb-200-distilled-1.3B"
    return "facebook/nllb-200-distilled-600M"


def translate_with_nllb(blocks, source_lang, target_lang_name, script_dir=None):
    """Translate blocks using local NLLB model.
    Returns dict {idx: translated_text} for successfully translated segments.
    Raises ImportError if transformers is not installed.
    """
    target_code = TARGET_LANG_TO_CODE.get(target_lang_name.lower(), "")
    if not target_code:
        print(f"  [NLLB] Unknown target language: {target_lang_name}")
        return {}, {}

    src_nllb = NLLB_LANG_MAP.get(source_lang, "")
    tgt_nllb = NLLB_LANG_MAP.get(target_code, "")

    if not src_nllb:
        print(f"  [NLLB] No NLLB mapping for source: {source_lang}")
        return {}, {}
    if not tgt_nllb:
        print(f"  [NLLB] No NLLB mapping for target: {target_lang_name}")
        return {}, {}

    from transformers import pipeline as hf_pipeline  # raises ImportError if missing

    try:
        import torch
        if torch.cuda.is_available():
            device = 0
            device_label = "GPU (CUDA/ROCm)"
        elif hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
            device = "mps"
            device_label = "GPU (Apple MPS)"
        else:
            device = -1
            device_label = "CPU"
    except ImportError:
        device = -1
        device_label = "CPU"

    model_name = get_nllb_model(script_dir)
    print(f"  [NLLB] Loading {model_name} on {device_label} (src={src_nllb} tgt={tgt_nllb})...")
    translator = hf_pipeline(
        "translation",
        model=model_name,
        src_lang=src_nllb,
        tgt_lang=tgt_nllb,
        device=device,
    )

    def _has_repetition(text, ngram=4, threshold=3):
        """Return True if any n-gram repeats more than threshold times."""
        words = text.split()
        if len(words) < ngram * threshold:
            return False
        counts = {}
        for i in range(len(words) - ngram + 1):
            key = tuple(words[i:i + ngram])
            counts[key] = counts.get(key, 0) + 1
            if counts[key] >= threshold:
                return True
        return False

    results = {}
    fallback = {}  # repetitive results — used if Gemini retry also fails
    for idx, ts, text in blocks:
        try:
            # Pre-process before NLLB
            clean_text = preprocess_for_nllb(text, source_lang)
            if not clean_text:
                continue
            out = translator(
                clean_text,
                max_length=512,
                no_repeat_ngram_size=3,
                repetition_penalty=1.2,
            )
            if out:
                translated = out[0].get("translation_text", "").strip()
                translated = postprocess_nllb_output(translated)
                if translated and not _has_repetition(translated):
                    results[idx] = translated
                elif translated:
                    print(f"  [NLLB] Repetition detected [{idx}], flagged for Gemini retry")
                    fallback[idx] = translated
        except Exception as e:
            print(f"  [NLLB] Error on [{idx}]: {e}")

    return results, fallback


def _translate_nllb_only(srt_path, output_path, target_lang, source_lang, script_dir):
    """Full NLLB-only translation (used when Gemini is not available)."""
    print(f"  Engine         : NLLB (offline)")
    print(f"  Target language: {target_lang}")

    with open(srt_path, "r", encoding="utf-8", errors="replace") as f:
        content = f.read()

    blocks = parse_srt(content)
    if not blocks:
        print("  [ERROR] No text found in SRT file")
        return 1

    total = len(blocks)
    print(f"  Total segments : {total}")

    try:
        results, nllb_fallback = translate_with_nllb(blocks, source_lang, target_lang, script_dir)
        # In NLLB-only mode: no Gemini available, use fallback directly for repetitive segments
        for idx, txt in nllb_fallback.items():
            if idx not in results:
                results[idx] = txt
    except ImportError:
        print("  [ERROR] transformers not installed. Run: pip install transformers sentencepiece sacremoses")
        return 1
    except Exception as e:
        print(f"  [ERROR] NLLB failed: {e}")
        return 1

    translated_blocks = []
    for idx, ts, text in blocks:
        trans = results.get(idx, text)
        trans = wrap_translated_line(trans)
        translated_blocks.append((idx, ts, trans))

    with open(output_path, "w", encoding="utf-8") as f:
        for idx, ts, text in translated_blocks:
            f.write(f"{idx}\n{ts}\n{text}\n\n")

    translated_count = sum(1 for orig, trans in zip(blocks, translated_blocks) if orig[2] != trans[2])

    # Preview first 5 translated segments
    shown = 0
    for orig, trans in zip(blocks, translated_blocks):
        if orig[2] != trans[2] and shown < 5:
            if shown == 0:
                print(f"\n  [Preview]")
            preview = trans[2][:70] + ("..." if len(trans[2]) > 70 else "")
            print(f"    [{trans[0]}] {preview}")
            shown += 1

    # Artifact report
    issues = detect_artifacts(translated_blocks, source_lang)
    if issues:
        print(f"  [Warn] {len(issues)} issue(s): " + " | ".join(issues[:5]))

    print(f"  [DONE] {translated_count}/{total} segments translated")
    print(f"  Saved  : {output_path}")

    if translated_count == total:
        return 0
    elif translated_count > 0:
        return 2
    return 1


# ---------------------------------------------------------------------------
# Main translation function (Gemini primary + NLLB second pass)
# ---------------------------------------------------------------------------
def translate_subtitles(engine_cmd, srt_path, output_path, engine_type="gemini",
                        target_lang="Indonesian", source_lang=""):
    script_dir = os.path.dirname(os.path.abspath(__file__))

    # NLLB-only mode
    if engine_type == "nllb":
        return _translate_nllb_only(srt_path, output_path, target_lang, source_lang, script_dir)

    # Gemini primary mode
    engine_cmd = resolve_cmd(engine_cmd)
    print(f"  Engine         : Gemini")
    print(f"  Path           : {engine_cmd}")
    print(f"  Target language: {target_lang}")

    with open(srt_path, "r", encoding="utf-8", errors="replace") as f:
        content = f.read()

    blocks = parse_srt(content)
    if not blocks:
        print("  [ERROR] No text found in SRT file")
        return 1

    tmp_dir = output_path + "_tmp"
    os.makedirs(tmp_dir, exist_ok=True)

    # Genre detection (cached in tmp_dir)
    genre_cache_file = os.path.join(tmp_dir, "genre.txt")
    print(f"  Detecting content genre...")
    if os.path.exists(genre_cache_file):
        with open(genre_cache_file, "r", encoding="utf-8") as f:
            genre = f.read().strip()
        print(f"  Genre          : {genre}")
    else:
        genre = detect_genre(engine_cmd, engine_type, srt_path)
        if genre:
            print(f"  Genre          : {genre}")
            with open(genre_cache_file, "w", encoding="utf-8") as f:
                f.write(genre)
        else:
            print(f"  Genre          : (not detected, proceeding without)")

    total = len(blocks)
    print(f"  Total segments : {total}")

    est_input, est_output = estimate_token_cost(blocks)
    est_total = est_input + est_output
    cost = (est_input / 1_000_000 * 3.0) + (est_output / 1_000_000 * 15.0)
    print(f"  Est. tokens    : ~{est_total:,} ({est_input:,} in + {est_output:,} out)")
    print(f"  Est. cost      : ~${cost:.4f}")
    if est_total > 50_000:
        print(f"  [!] Large file - this may take a while")

    print(f"  Checking Gemini...")
    ok, msg = check_engine_responsive(engine_cmd, engine_type)
    if not ok:
        print(f"  [ERROR] Gemini not responding: {msg}")
        return 1
    print(f"  [OK] Gemini responsive ({msg[:50]})")
    print(f"  Translating in batches...")

    MAX_TOKENS_PER_BATCH = 200   # increased from 150 for better context
    GEMINI_BATCH_DELAY   = 5
    MAX_RETRY            = 2
    CONTEXT_WINDOW       = 3     # recent translated lines passed as context

    def est_tok(text):
        return max(1, len(text) // 4)

    # Build batches with sentence-boundary awareness
    batches = build_batches(blocks, max_tokens=MAX_TOKENS_PER_BATCH)

    total_batch = len(batches)
    print(f"  Total batches  : {total_batch} (max ~{MAX_TOKENS_PER_BATCH} tokens/batch)")
    print(f"  Temp folder    : {tmp_dir}")

    translated_blocks = []
    source_map = {}  # idx -> engine that provided translation
    recent_context = []  # last CONTEXT_WINDOW translated (idx, translated_text) pairs

    LANG_NAMES = {
        "ja": "Japanese", "ko": "Korean", "zh": "Chinese",
        "en": "English",  "id": "Indonesian",
    }
    src_label   = LANG_NAMES.get(source_lang, "") if source_lang else ""
    from_clause = f" from {src_label}" if src_label else ""
    genre_line  = f"Content type: {genre}\n" if genre else ""
    register_note = get_register_note(genre, target_lang)

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
                    trans = translated_lines.get(idx, text)
                    translated_blocks.append((idx, ts, trans))
                    if idx in translated_lines:
                        recent_context.append((idx, trans))
                recent_context = recent_context[-CONTEXT_WINDOW:]
                continue
            else:
                print(f"  Batch {batch_num}/{total_batch} - cache invalid, reprocessing")
                os.remove(tmp_file)

        if batch_num > 1:
            time.sleep(GEMINI_BATCH_DELAY)

        print(f"  Batch {batch_num}/{total_batch} ({len(batch)} seg, ~{batch_tokens} tok)...", end="", flush=True)

        # Pre-process text before sending to Gemini
        lines_to_translate = [
            f"[{idx}] {preprocess_subtitle_text(text)}"
            for idx, ts, text in batch
        ]

        # Build context section from recent translated lines
        context_section = ""
        if recent_context:
            ctx_lines = "\n".join(f"[{idx}] {text}" for idx, text in recent_context)
            context_section = (
                f"Recent dialogue (already translated — for context only, do NOT retranslate):\n"
                f"{ctx_lines}\n\n"
                f"Now translate ONLY these lines:\n"
            )

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
            f"{register_note}"
            "- Non-verbal sounds (sighs, moans, gasps like 'ああ', 'はぁ') should be adapted "
            "as natural target-language expressions (e.g. 'haah', 'aah') — do not skip them\n"
            "- Some lines may be short fragments or continuations — translate them as short natural phrases\n"
            "- Keep the [number] prefix on each line exactly as-is\n"
            "- Output ONLY the translated lines, no comments or explanations\n\n"
            + context_section
            + "\n".join(lines_to_translate)
        )

        try:
            rc, stdout, stderr = -1, "", ""
            for attempt in range(1, MAX_RETRY + 2):
                rc, stdout, stderr = run_translate_prompt(engine_cmd, engine_type, prompt)
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

            translated_lines = {}
            for line in stdout.strip().split("\n"):
                m = re.match(r"\[(\d+)\]\s*(.*)", line.strip())
                if m:
                    translated_lines[m.group(1)] = m.group(2)

            matched = sum(1 for idx, _, _ in batch if idx in translated_lines)
            print(f" OK ({matched}/{len(batch)} match)")

            debug_file = os.path.join(tmp_dir, f"batch_{batch_num:04d}_raw.txt")
            with open(debug_file, "w", encoding="utf-8") as f:
                f.write(stdout)

            if matched > 0:
                with open(tmp_file, "w", encoding="utf-8") as f:
                    for idx, _, _ in batch:
                        text_out = translated_lines.get(idx, "")
                        f.write(f"[{idx}] {text_out}\n")
            else:
                print(f"      [!] 0 matches - cache not saved, will retry next run")

            for idx, ts, text in batch:
                trans = translated_lines.get(idx, text)
                translated_blocks.append((idx, ts, trans))
                if idx in translated_lines:
                    recent_context.append((idx, trans))
            recent_context = recent_context[-CONTEXT_WINDOW:]

        except FileNotFoundError as e:
            print(f" ERROR")
            print(f"  [ERROR] Cannot run Gemini: {e}")
            return 1
        except Exception as e:
            print(f" ERROR: {type(e).__name__}: {e}")
            for idx, ts, text in batch:
                translated_blocks.append((idx, ts, text))

    # Record which segments were translated by Gemini (pass 1)
    for orig, trans in zip(blocks, translated_blocks):
        if orig[2] != trans[2]:
            source_map[orig[0]] = "gemini"

    # -----------------------------------------------------------------------
    # Second pass: NLLB fills segments Gemini couldn't translate
    # -----------------------------------------------------------------------
    untranslated = [orig for orig, trans in zip(blocks, translated_blocks) if orig[2] == trans[2]]
    if untranslated:
        print(f"  [+] Second pass: {len(untranslated)} untranslated segment(s)")
        nllb_count = 0
        try:
            nllb_results, nllb_fallback = translate_with_nllb(untranslated, source_lang, target_lang, script_dir)
            if nllb_results:
                trans_map = {idx: txt for idx, ts, txt in translated_blocks}
                for idx, val in nllb_results.items():
                    trans_map[idx] = val
                    source_map[idx] = "nllb"
                    nllb_count += 1
                translated_blocks = [(idx, ts, trans_map.get(idx, txt)) for idx, ts, txt in blocks]
                print(f"  [NLLB] Filled {nllb_count}/{len(untranslated)} gap(s)")
            else:
                print(f"  [NLLB] No segments translated (language pair may not be supported)")

            # Retry segments NLLB missed (repetition detected or error) with Gemini
            still_missing = [b for b in untranslated if b[0] not in nllb_results]
            if still_missing and engine_cmd:
                print(f"  [Gemini] {len(still_missing)} NLLB-missed segment(s) — retrying with Gemini...")
                miss_batches = build_batches(still_missing, max_tokens=MAX_TOKENS_PER_BATCH)

                trans_map = {idx: txt for idx, ts, txt in translated_blocks}
                for mb_num, mb in enumerate(miss_batches, 1):
                    mb_tokens = sum(est_tok(t) for _, _, t in mb)
                    mb_cache = os.path.join(tmp_dir, f"nllb_miss_{mb[0][0]:06}.txt")

                    if os.path.exists(mb_cache):
                        with open(mb_cache, "r", encoding="utf-8") as f:
                            cached = f.read()
                        mb_cached = {}
                        for line in cached.strip().split("\n"):
                            mm = re.match(r"\[(\d+)\]\s*(.*)", line.strip())
                            if mm and mm.group(2).strip():
                                mb_cached[mm.group(1)] = mm.group(2)
                        matched = sum(1 for idx, _, _ in mb if idx in mb_cached)
                        if matched > 0:
                            print(f"  Gemini {mb_num}/{len(miss_batches)} - from cache ({matched}/{len(mb)})")
                            for idx, ts, text in mb:
                                if idx in mb_cached:
                                    trans_map[idx] = mb_cached[idx]
                            continue

                    time.sleep(GEMINI_BATCH_DELAY)
                    print(f"  Gemini {mb_num}/{len(miss_batches)} ({len(mb)} seg, ~{mb_tokens} tok)...", end="", flush=True)

                    lines_to_translate = [
                        f"[{idx}] {preprocess_subtitle_text(text)}"
                        for idx, ts, text in mb
                    ]
                    miss_prompt = (
                        f"You are a professional subtitle translator.\n"
                        f"Translate the following subtitle lines{from_clause} to {target_lang}.\n"
                        f"{genre_line}"
                        "\nGuidelines:\n"
                        "- Write natural, fluent translations that feel native in the target language\n"
                        "- Preserve the speaker's tone, emotion, and personality (casual, formal, excited, sad, etc.)\n"
                        "- Adapt idioms and cultural expressions naturally — avoid word-for-word literal translation\n"
                        "- Use vocabulary and phrasing appropriate to the content type above\n"
                        "- Keep translations concise so they are easy to read quickly as subtitles\n"
                        f"{register_note}"
                        "- Non-verbal sounds (sighs, moans, gasps like 'ああ', 'はぁ') should be adapted "
                        "as natural target-language expressions — do not skip them\n"
                        "- Some lines may be short fragments — translate them as short natural phrases\n"
                        "- Keep the [number] prefix on each line exactly as-is\n"
                        "- Output ONLY the translated lines, no comments or explanations\n\n"
                        + "\n".join(lines_to_translate)
                    )

                    rc, stdout, stderr = -1, "", ""
                    for attempt in range(1, MAX_RETRY + 2):
                        rc, stdout, stderr = run_translate_prompt(engine_cmd, engine_type, miss_prompt)
                        if rc == 0 and stdout.strip():
                            break
                        if attempt <= MAX_RETRY:
                            wait = attempt * 5
                            tag = "TIMEOUT" if stderr == "TIMEOUT" else f"rc={rc}"
                            print(f" {tag}, retry {attempt}/{MAX_RETRY} in {wait}s...", end="", flush=True)
                            time.sleep(wait)

                    if rc != 0 or not stdout.strip():
                        print(f" FAILED (rc={rc})")
                        continue

                    mb_translated = {}
                    for line in stdout.strip().split("\n"):
                        mm = re.match(r"\[(\d+)\]\s*(.*)", line.strip())
                        if mm:
                            mb_translated[mm.group(1)] = mm.group(2)

                    matched = sum(1 for idx, _, _ in mb if idx in mb_translated)
                    print(f" OK ({matched}/{len(mb)})")

                    if matched > 0:
                        with open(mb_cache, "w", encoding="utf-8") as f:
                            for idx, _, _ in mb:
                                f.write(f"[{idx}] {mb_translated.get(idx, '')}\n")
                        for idx, ts, text in mb:
                            if idx in mb_translated:
                                trans_map[idx] = mb_translated[idx]
                                source_map[idx] = "gemini_retry"
                    else:
                        # Gemini retry failed — use NLLB fallback (repetitive but still a translation)
                        nllb_used = 0
                        for idx, ts, text in mb:
                            if idx in nllb_fallback:
                                trans_map[idx] = nllb_fallback[idx]
                                source_map[idx] = "nllb_fallback"
                                nllb_used += 1
                        if nllb_used:
                            print(f"      [!] Using NLLB fallback for {nllb_used} segment(s)")

                translated_blocks = [(idx, ts, trans_map.get(idx, txt)) for idx, ts, txt in blocks]

        except ImportError:
            # NLLB not installed — fall back to Gemini retry (original second pass)
            print(f"  [!] NLLB not installed — retrying remaining with Gemini...")
            retry_batches = build_batches(untranslated, max_tokens=MAX_TOKENS_PER_BATCH)

            trans_map = {idx: txt for idx, ts, txt in translated_blocks}

            for rb_num, rb in enumerate(retry_batches, 1):
                rb_tokens = sum(est_tok(t) for _, _, t in rb)
                rb_cache = os.path.join(tmp_dir, f"retry_{rb[0][0]:06}.txt")

                if os.path.exists(rb_cache):
                    with open(rb_cache, "r", encoding="utf-8") as f:
                        cached = f.read()
                    rb_cached = {}
                    for line in cached.strip().split("\n"):
                        m = re.match(r"\[(\d+)\]\s*(.*)", line.strip())
                        if m and m.group(2).strip():
                            rb_cached[m.group(1)] = m.group(2)
                    matched = sum(1 for idx, _, _ in rb if idx in rb_cached)
                    if matched > 0:
                        print(f"  Retry {rb_num}/{len(retry_batches)} - from cache ({matched}/{len(rb)})")
                        for idx, ts, text in rb:
                            if idx in rb_cached:
                                trans_map[idx] = rb_cached[idx]
                        continue

                time.sleep(GEMINI_BATCH_DELAY)
                print(f"  Retry {rb_num}/{len(retry_batches)} ({len(rb)} seg, ~{rb_tokens} tok)...", end="", flush=True)

                lines_to_translate = [
                    f"[{idx}] {preprocess_subtitle_text(text)}"
                    for idx, ts, text in rb
                ]
                retry_prompt = (
                    f"You are a professional subtitle translator.\n"
                    f"Translate the following subtitle lines{from_clause} to {target_lang}.\n"
                    f"{genre_line}"
                    "\nGuidelines:\n"
                    "- Write natural, fluent translations that feel native in the target language\n"
                    "- Preserve the speaker's tone, emotion, and personality (casual, formal, excited, sad, etc.)\n"
                    "- Adapt idioms and cultural expressions naturally — avoid word-for-word literal translation\n"
                    "- Use vocabulary and phrasing appropriate to the content type above\n"
                    "- Keep translations concise so they are easy to read quickly as subtitles\n"
                    f"{register_note}"
                    "- Non-verbal sounds should be adapted as natural target-language expressions\n"
                    "- Some lines may be short fragments — translate them as short natural phrases\n"
                    "- Keep the [number] prefix on each line exactly as-is\n"
                    "- Output ONLY the translated lines, no comments or explanations\n\n"
                    + "\n".join(lines_to_translate)
                )

                rc, stdout, stderr = -1, "", ""
                for attempt in range(1, MAX_RETRY + 2):
                    rc, stdout, stderr = run_translate_prompt(engine_cmd, engine_type, retry_prompt)
                    if rc == 0 and stdout.strip():
                        break
                    if attempt <= MAX_RETRY:
                        wait = attempt * 5
                        tag = "TIMEOUT" if stderr == "TIMEOUT" else f"rc={rc}"
                        print(f" {tag}, retry {attempt}/{MAX_RETRY} in {wait}s...", end="", flush=True)
                        time.sleep(wait)

                if rc != 0 or not stdout.strip():
                    print(f" FAILED (rc={rc})")
                    continue

                rb_translated = {}
                for line in stdout.strip().split("\n"):
                    m = re.match(r"\[(\d+)\]\s*(.*)", line.strip())
                    if m:
                        rb_translated[m.group(1)] = m.group(2)

                matched = sum(1 for idx, _, _ in rb if idx in rb_translated)
                print(f" OK ({matched}/{len(rb)})")

                if matched > 0:
                    with open(rb_cache, "w", encoding="utf-8") as f:
                        for idx, _, _ in rb:
                            f.write(f"[{idx}] {rb_translated.get(idx, '')}\n")
                    for idx, ts, text in rb:
                        if idx in rb_translated:
                            trans_map[idx] = rb_translated[idx]
                            source_map[idx] = "gemini_retry"

            translated_blocks = [(idx, ts, trans_map.get(idx, txt)) for idx, ts, txt in blocks]

        except Exception as e:
            print(f"  [NLLB] Error: {e}")

    # -----------------------------------------------------------------------
    # Apply output line wrapping and write output file
    # -----------------------------------------------------------------------
    final_blocks = []
    for idx, ts, text in translated_blocks:
        final_blocks.append((idx, ts, wrap_translated_line(text)))

    with open(output_path, "w", encoding="utf-8") as f:
        for idx, ts, text in final_blocks:
            f.write(f"{idx}\n{ts}\n{text}\n\n")

    translated_count = sum(
        1 for orig, trans in zip(blocks, final_blocks)
        if orig[2] != trans[2]
    )

    if translated_count == total:
        import shutil as _shutil
        _shutil.rmtree(tmp_dir, ignore_errors=True)
        print(f"  [OK] Temp folder removed")
        exit_code = 0
    elif translated_count > 0:
        print(f"  [!] Partial translation — temp folder kept for resume: {tmp_dir}")
        exit_code = 2
    else:
        print(f"  [!] Temp folder kept for debugging: {tmp_dir}")
        print(f"      Check *_raw.txt files to see engine output")
        exit_code = 1

    # Quality report
    gemini_c   = sum(1 for v in source_map.values() if v == "gemini")
    nllb_c     = sum(1 for v in source_map.values() if v == "nllb")
    retry_c    = sum(1 for v in source_map.values() if v == "gemini_retry")
    fallback_c = sum(1 for v in source_map.values() if v == "nllb_fallback")
    untrans_c  = total - translated_count
    parts = []
    if gemini_c:   parts.append(f"Gemini: {gemini_c}")
    if nllb_c:     parts.append(f"NLLB: {nllb_c}")
    if retry_c:    parts.append(f"Retry: {retry_c}")
    if fallback_c: parts.append(f"Fallback: {fallback_c}")
    if untrans_c:  parts.append(f"Untranslated: {untrans_c}")
    if parts:
        print(f"  [Report] " + "  |  ".join(parts))

    # Artifact detection
    issues = detect_artifacts(final_blocks, source_lang)
    if issues:
        print(f"  [Warn] {len(issues)} issue(s) detected: " + " | ".join(issues[:5]))
        if len(issues) > 5:
            print(f"         ...and {len(issues) - 5} more")

    # Preview first 5 translated segments
    shown = 0
    for orig, trans in zip(blocks, final_blocks):
        if orig[2] != trans[2] and shown < 5:
            if shown == 0:
                print(f"\n  [Preview]")
            preview = trans[2][:70] + ("..." if len(trans[2]) > 70 else "")
            print(f"    [{trans[0]}] {preview}")
            shown += 1

    print(f"  [DONE] {translated_count}/{total} segments translated")
    print(f"  Saved  : {output_path}")
    return exit_code


if __name__ == "__main__":
    # Special mode: detect source language of an SRT file
    if len(sys.argv) >= 3 and sys.argv[1] == "--detect-lang":
        print(detect_language(sys.argv[2]))
        sys.exit(0)

    if len(sys.argv) < 2:
        print("Usage: python translate_srt.py <file.srt> [engine_cmd] [engine_type] [target_lang]")
        sys.exit(1)

    srt_path           = sys.argv[1]
    forced_engine_cmd  = sys.argv[2] if len(sys.argv) >= 3 else None
    forced_engine_type = sys.argv[3] if len(sys.argv) >= 4 else None
    target_lang        = sys.argv[4] if len(sys.argv) >= 5 else "Indonesian"

    if not os.path.exists(srt_path):
        print(f"[ERROR] File not found: {srt_path}")
        sys.exit(1)

    LANG_SUFFIX = {
        "english":           "_EN",
        "indonesian":        "_ID",
        "japanese":          "_JA",
        "korean":            "_KO",
        "chinese":           "_ZH",
        "chinese (mandarin)":"_ZH",
        "mandarin":          "_ZH",
    }
    suffix      = LANG_SUFFIX.get(target_lang.lower(), "_TRANSLATED")
    output_path = os.path.splitext(srt_path)[0] + suffix + ".srt"

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
    if forced_engine_cmd is not None and forced_engine_type:
        chosen_cmd  = forced_engine_cmd if forced_engine_cmd else ""
        chosen_type = forced_engine_type
        label = "NLLB (offline)" if chosen_type == "nllb" else f"{chosen_type} -> {chosen_cmd}"
        print(f"[OK] Engine: {label}")
    else:
        # Interactive mode
        gemini = detect_gemini_cmd()

        # Check NLLB
        nllb_ok = False
        try:
            import importlib.util
            nllb_ok = importlib.util.find_spec("transformers") is not None
        except Exception:
            pass

        if not gemini and not nllb_ok:
            print("[ERROR] No translation engine found.")
            print("  Install Gemini : npm install -g @google/gemini-cli")
            print("  Install NLLB   : pip install transformers sentencepiece sacremoses")
            sys.exit(1)

        print("\n  Available engines:")
        engine_list = []
        if gemini:
            engine_list.append(("gemini", gemini))
            print(f"   [1] Gemini CLI")
            print(f"       {gemini}")
        if nllb_ok:
            engine_list.append(("nllb", ""))
            print(f"   [{len(engine_list)}] NLLB (offline, local)")

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

    result = translate_subtitles(chosen_cmd, srt_path, output_path, chosen_type, target_lang, detected_lang)
    sys.exit(result if isinstance(result, int) else (0 if result else 1))
