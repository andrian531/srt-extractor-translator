import sys
import os
import re
import subprocess


def detect_claude_cmd():
    """Cek keberadaan Claude Code tanpa menjalankannya"""
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
    """Cek keberadaan Gemini CLI tanpa menjalankannya"""
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
    """Deteksi semua engine translate yang tersedia"""
    engines = {}
    claude = detect_claude_cmd()
    if claude:
        engines["claude"] = claude
    gemini = detect_gemini_cmd()
    if gemini:
        engines["gemini"] = gemini
    return engines


def resolve_cmd(cmd):
    """Pastikan cmd adalah full path yang bisa dijalankan di Windows"""
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


def resolve_claude_cmd(claude_cmd):
    return resolve_cmd(claude_cmd)


def detect_language(srt_path):
    """Deteksi apakah SRT sudah Indonesian atau belum"""
    try:
        with open(srt_path, "r", encoding="utf-8", errors="replace") as f:
            raw = f.read(8000)

        # Ambil hanya teks (bukan timestamp dan nomor)
        lines = []
        for line in raw.split("\n"):
            line = line.strip()
            if not line or line.isdigit() or "-->" in line:
                continue
            lines.append(line.lower())
        text = " ".join(lines)

        if not text.strip():
            return "unknown"

        # Cek karakter CJK - pasti non-indonesian
        cjk = re.findall(r"[\u3000-\u9fff\uac00-\ud7af\uf900-\ufaff]", text)
        if len(cjk) > 5:
            return "non-indonesian"

        # Cek kata khas Indonesian
        id_words = [
            "yang", "dan", "ini", "itu", "tidak", "ada", "dengan",
            "untuk", "saya", "kamu", "aku", "dia", "mereka", "kami",
            "adalah", "sudah", "akan", "bisa", "dari", "ke", "di",
            "juga", "sudah", "belum", "kalau", "karena", "tapi",
        ]
        found_id = sum(1 for w in id_words if re.search(r'\b' + w + r'\b', text))

        # Cek kata khas English
        en_words = [
            "the", "and", "you", "that", "this", "with", "have",
            "for", "are", "but", "not", "your", "from", "they",
            "what", "just", "know", "was", "will", "its", "been",
            "when", "who", "her", "him", "she", "he",
        ]
        found_en = sum(1 for w in en_words if re.search(r'\b' + w + r'\b', text))

        print(f"  [detect_language] ID={found_id} EN={found_en}")

        if found_id >= 4 and found_id > found_en:
            return "indonesian"
        return "non-indonesian"

    except Exception as e:
        print(f"  [detect_language error] {e}")
        return "unknown"


def parse_srt(content):
    """Parse SRT menjadi list of (index, timestamp, text)"""
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
    """Estimasi token yang dibutuhkan untuk menerjemahkan semua block"""
    total_chars = sum(len(text) for _, _, text in blocks)
    estimated_input  = int(total_chars / 4 * 1.3)
    estimated_output = int(total_chars / 4)
    return estimated_input, estimated_output


def check_engine_responsive(engine_cmd, engine_type):
    """Ping engine translate via stdin pipe untuk cek apakah masih bisa dipanggil"""
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
        return False, f"File tidak ditemukan: {e}"
    except subprocess.TimeoutExpired:
        return False, "Timeout (>60 detik)"
    except Exception as e:
        return False, str(e)


def check_claude_responsive(claude_cmd):
    return check_engine_responsive(claude_cmd, "claude")


def run_translate_prompt(engine_cmd, engine_type, prompt):
    """Jalankan prompt terjemahan via stdin pipe (bekerja untuk Claude dan Gemini)"""
    try:
        # Kedua engine bekerja via stdin pipe, bukan -p flag
        cmd = [engine_cmd]
        result = subprocess.run(
            cmd,
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


def translate_with_claude(claude_cmd, srt_path, output_path, engine_type="claude"):
    """Terjemahkan SRT menggunakan Claude atau Gemini CLI"""
    claude_cmd = resolve_cmd(claude_cmd)
    engine_label = "Claude" if engine_type == "claude" else "Gemini"
    print(f"  Engine         : {engine_label}")
    print(f"  Path           : {claude_cmd}")

    with open(srt_path, "r", encoding="utf-8", errors="replace") as f:
        content = f.read()

    blocks = parse_srt(content)
    if not blocks:
        print("  [ERROR] Tidak ada teks ditemukan di SRT")
        return False

    total = len(blocks)
    print(f"  Total segment  : {total}")

    # Estimasi token dan biaya
    est_input, est_output = estimate_token_cost(blocks)
    est_total = est_input + est_output
    cost = (est_input / 1_000_000 * 3.0) + (est_output / 1_000_000 * 15.0)
    print(f"  Estimasi token : ~{est_total:,} ({est_input:,} input + {est_output:,} output)")
    print(f"  Estimasi biaya : ~${cost:.4f} (~Rp {cost * 16000:,.0f})")
    if est_total > 50_000:
        print(f"  [!] File besar - proses bisa memakan waktu lama")

    # Ping Claude sebelum mulai
    print(f"  Mengecek {engine_label}...")
    ok, msg = check_engine_responsive(claude_cmd, engine_type)
    if not ok:
        print(f"  [ERROR] {engine_label} tidak responsive: {msg}")
        print(f"          Kemungkinan token limit habis atau koneksi bermasalah.")
        return False
    print(f"  [OK] {engine_label} responsive ({msg[:50]})")
    print(f"  Menerjemahkan dalam batch...")

    # Bagi batch berdasarkan estimasi token
    MAX_TOKENS_PER_BATCH = 300

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
    print(f"  Total batch    : {total_batch} (maks ~{MAX_TOKENS_PER_BATCH} token/batch)")

    # Folder temporary di sebelah file output
    tmp_dir = output_path + "_tmp"
    os.makedirs(tmp_dir, exist_ok=True)
    print(f"  Temp folder    : {tmp_dir}")

    translated_blocks = []

    for batch_num, batch in enumerate(batches, 1):
        batch_tokens = sum(est_tok(t) for _, _, t in batch)
        tmp_file = os.path.join(tmp_dir, f"batch_{batch_num:04d}.txt")

        # Cek apakah batch ini sudah ada dari run sebelumnya (resume)
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
                print(f"  Batch {batch_num}/{total_batch} - resume dari cache... OK ({matched}/{len(batch)} match, cached)")
                for idx, ts, text in batch:
                    translated_blocks.append((idx, ts, translated_lines.get(idx, text)))
                continue
            else:
                print(f"  Batch {batch_num}/{total_batch} - cache kosong/invalid, akan diproses ulang")
                os.remove(tmp_file)

        print(f"  Batch {batch_num}/{total_batch} ({len(batch)} segment, ~{batch_tokens} token)...", end="", flush=True)

        lines_to_translate = [f"[{idx}] {text}" for idx, ts, text in batch]
        prompt = (
            "Terjemahkan baris-baris berikut ke Bahasa Indonesia. "
            "Pertahankan prefix [angka] di tiap baris persis seperti aslinya. "
            "Output HANYA baris terjemahan, tanpa komentar atau penjelasan lain.\n\n"
            + "\n".join(lines_to_translate)
        )

        try:
            rc, stdout, stderr = run_translate_prompt(claude_cmd, engine_type, prompt)

            if rc != 0 or not stdout.strip():
                print(f" GAGAL (rc={rc})")
                print(f"      stdout: {repr(stdout[:300])}")
                print(f"      stderr: {repr(stderr[:300])}")
                for idx, ts, text in batch:
                    translated_blocks.append((idx, ts, text))
                continue
            result_stdout = stdout

            # Parse hasil
            translated_lines = {}
            for line in result_stdout.strip().split("\n"):
                m = re.match(r"\[(\d+)\]\s*(.*)", line.strip())
                if m:
                    translated_lines[m.group(1)] = m.group(2)

            matched = sum(1 for idx, _, _ in batch if idx in translated_lines)
            print(f" OK ({matched}/{len(batch)} match)")

            # Simpan raw output ke file debug
            debug_file = os.path.join(tmp_dir, f"batch_{batch_num:04d}_raw.txt")
            with open(debug_file, "w", encoding="utf-8") as f:
                f.write(result_stdout)

            # Hanya simpan cache jika ada hasil terjemahan
            if matched > 0:
                with open(tmp_file, "w", encoding="utf-8") as f:
                    for idx, _, _ in batch:
                        text_out = translated_lines.get(idx, "")
                        f.write(f"[{idx}] {text_out}\n")
            else:
                print(f"      [!] 0 match - cache tidak disimpan, akan dicoba ulang berikutnya")

            for idx, ts, text in batch:
                translated_blocks.append((idx, ts, translated_lines.get(idx, text)))

        except subprocess.TimeoutExpired:
            print(f" TIMEOUT")
            for idx, ts, text in batch:
                translated_blocks.append((idx, ts, text))
        except FileNotFoundError as e:
            print(f" ERROR")
            print(f"  [ERROR] Claude tidak bisa dijalankan: {e}")
            print(f"          Path: {claude_cmd}")
            return False
        except Exception as e:
            print(f" ERROR: {type(e).__name__}: {e}")
            for idx, ts, text in batch:
                translated_blocks.append((idx, ts, text))

    # Gabung semua hasil ke file output final
    with open(output_path, "w", encoding="utf-8") as f:
        for idx, ts, text in translated_blocks:
            f.write(f"{idx}\n{ts}\n{text}\n\n")

    translated_count = sum(
        1 for orig, trans in zip(blocks, translated_blocks)
        if orig[2] != trans[2]
    )

    # Hapus folder temporary hanya jika ada hasil terjemahan
    if translated_count > 0:
        import shutil as _shutil
        _shutil.rmtree(tmp_dir, ignore_errors=True)
        print(f"  [OK] Temp folder dihapus")
    else:
        print(f"  [!] Temp folder dipertahankan untuk debug: {tmp_dir}")
        print(f"      Cek file *_raw.txt untuk melihat output engine yang sebenarnya")

    print(f"  [SELESAI] {translated_count}/{total} segment berhasil diterjemahkan")
    print(f"  Disimpan : {output_path}")
    return True


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python translate_srt.py <file.srt> [claude_cmd]")
        sys.exit(1)

    srt_path = sys.argv[1]
    forced_claude_cmd = sys.argv[2] if len(sys.argv) >= 3 else None

    if not os.path.exists(srt_path):
        print(f"[ERROR] File tidak ditemukan: {srt_path}")
        sys.exit(1)

    # Cek bahasa
    lang = detect_language(srt_path)
    print(f"[INFO] Bahasa terdeteksi: {lang}")
    if lang == "indonesian":
        print("[INFO] SRT sudah dalam Bahasa Indonesia, skip terjemahan.")
        sys.exit(0)

    # Jika dipanggil dari .bat dengan engine argument
    forced_engine_type = sys.argv[3] if len(sys.argv) >= 4 else None

    # Deteksi semua engine yang tersedia
    engines = detect_available_engines()

    if forced_claude_cmd and forced_engine_type:
        # Dipanggil dari .bat dengan engine sudah ditentukan
        chosen_cmd = forced_claude_cmd
        chosen_type = forced_engine_type
        print(f"[OK] Engine dari .bat: {chosen_type} -> {chosen_cmd}")
    else:
        # Tampilkan pilihan engine yang tersedia
        if not engines:
            print("[ERROR] Tidak ada engine translate ditemukan.")
            print("  Install Claude : npm install -g @anthropic-ai/claude-code")
            print("  Install Gemini : npm install -g @google/gemini-cli")
            sys.exit(1)

        print("\n  Pilih engine translate:")
        engine_list = list(engines.items())
        for i, (etype, ecmd) in enumerate(engine_list, 1):
            label = "Claude Code" if etype == "claude" else "Gemini CLI"
            print(f"   [{i}] {label}")
            print(f"       {ecmd}")

        if len(engine_list) == 1:
            print(f"  (hanya 1 engine tersedia, otomatis dipilih)")
            chosen_type, chosen_cmd = engine_list[0]
        else:
            choice = input(f"  Pilih [1-{len(engine_list)}]: ").strip()
            try:
                idx = int(choice) - 1
                chosen_type, chosen_cmd = engine_list[idx]
            except (ValueError, IndexError):
                chosen_type, chosen_cmd = engine_list[0]
                print(f"  Input tidak valid, pakai {chosen_type}")

    # Tanya konfirmasi terjemahan
    answer = input("  Mau diterjemahkan ke Bahasa Indonesia? (Y/N): ").strip().lower()
    if answer != "y":
        print("[INFO] Terjemahan dilewati.")
        sys.exit(0)

    # Buat nama output
    base = os.path.splitext(srt_path)[0]
    output_path = base + "_ID.srt"

    print(f"\n  Menerjemahkan : {os.path.basename(srt_path)}")
    print(f"  Output        : {os.path.basename(output_path)}")
    print(f"  SRT asli tetap tersimpan.")
    print()

    success = translate_with_claude(chosen_cmd, srt_path, output_path, chosen_type)
    sys.exit(0 if success else 1)