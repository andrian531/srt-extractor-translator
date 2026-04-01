import re, sys, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

path = r'video/EYAN-203 A beautiful wife who shakes her rocket tits an.srt'
with open(path, encoding='utf-8', errors='replace') as f:
    content = f.read()

blocks = []
pattern = re.compile(
    r'(\d+)\r?\n'
    r'(\d{2}:\d{2}:\d{2},\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2},\d{3})\r?\n'
    r'([\s\S]*?)(?=\r?\n\r?\n|\Z)',
    re.MULTILINE
)
for m in pattern.finditer(content.strip() + '\n\n'):
    t = m.group(4).strip()
    if t:
        blocks.append((int(m.group(1)), m.group(2), m.group(3), t))

def ts2ms(ts):
    h, m, rest = ts.split(':')
    s, ms = rest.split(',')
    return int(h)*3600000 + int(m)*60000 + int(s)*1000 + int(ms)

# 1. Karakter bocor / repeat berurutan
repeat = [(b[0], b[1], b[3]) for i, b in enumerate(blocks)
          if i > 0 and b[3].strip() == blocks[i-1][3].strip()]

# 2. Halusinasi / teks aneh (pola-pola non-dialog)
WEIRD = [r'あなたが', r'彼は私を', r'戦闘', r'討ち', r'ロークで', r'大いなミスなんだ',
         r'仕事に対するイメージ']
weird = [(b[0], b[1], b[3]) for b in blocks
         if any(re.search(p, b[3]) for p in WEIRD)]

# 3. Segmen sangat pendek < 300ms
shorts = [(b[0], b[1], b[2], ts2ms(b[2])-ts2ms(b[1]), b[3])
          for b in blocks if 0 < ts2ms(b[2])-ts2ms(b[1]) < 300]

# 4. Teks berulang > 2x total
from collections import Counter
tc = Counter(b[3] for b in blocks)
dupes = [(t, c) for t, c in tc.items() if c > 2]

print('='*60)
print(f'TOTAL SEGMEN: {len(blocks)}')
print('='*60)

print(f'\n[1] KARAKTER BOCOR (repeat berurutan): {len(repeat)}')
for idx, ts, txt in repeat:
    print(f'    Seg {idx} @ {ts}: {txt[:60]}')
if not repeat:
    print('    OK - tidak ada')

print(f'\n[2] HALUSINASI / TEKS ANEH: {len(weird)}')
for idx, ts, txt in weird:
    print(f'    Seg {idx} @ {ts}: {txt[:80]}')
if not weird:
    print('    OK - tidak ada')

print(f'\n[3] SEGMEN DURASI < 300ms: {len(shorts)}')
for idx, ts_s, ts_e, dur, txt in shorts[:20]:
    print(f'    Seg {idx} @ {ts_s}: {dur}ms | {txt[:40]}')
if len(shorts) > 20:
    print(f'    ... dan {len(shorts)-20} lagi')
if not shorts:
    print('    OK - tidak ada')

print(f'\n[4] TEKS DUPLIKAT > 2x: {len(dupes)}')
for t, c in sorted(dupes, key=lambda x: -x[1])[:10]:
    print(f'    ({c}x) {t[:60]}')
if not dupes:
    print('    OK - tidak ada')
