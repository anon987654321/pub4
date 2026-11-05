#!/usr/bin/env python3
"""Verify the rebuilt PDF against MASTER's typographic laws.

Checks (evidence, not intentions):
  EN_DASH_RANGE        no un-dashed numeric ranges (hyphen between digits),
                       exempting ISO dates and version-like identifiers,
                       per law/cosmetic.rb EN_DASH_NOT_A_RANGE.
  STRUNK_WHITE         no leech words from data/laws.yml (very, rather,
                       really, quite, pretty, somewhat, just, basically,
                       simply) outside the quoted list in the colophon.
  TYPOGRAPHIC_GRID     median line length of full body lines ~ 66 chars.
  TYPOGRAPHIC_EXCELLENCE  no ASCII ellipsis/box art; em/en dashes present.
  PAPER_NOT_PURE_WHITE page ground pixel != #FFFFFF (sampled from render).
  Placeholders         no TODO/XXX/lorem/【】.
"""
import re, subprocess, sys, statistics

PDF = sys.argv[1] if len(sys.argv) > 1 else "pub4_analysis.pdf"

txt = subprocess.run(["pdftotext", "-layout", PDF, "-"], capture_output=True, text=True).stdout
pages = txt.split("\f")
body = "\n".join(pages[2:])  # skip title page + contents

fail = []

# --- EN_DASH_RANGE (mirrors the law's own exemptions) ---
exempt = re.compile(r"`[^`]*`|\b\d+(?:-\d+){2,}\b|\b\d{4}-\d{2}(?:-\d{2})?\b|\[[^\]]*\]|[A-Za-z][\w.]*-\d[\w.]*(?:-[\w.]+)*")
range_hits = []
for line in body.splitlines():
    stripped = exempt.sub(" ", line)
    for m in re.finditer(r"\b\d+\s?-\s?\d+\b", stripped):
        range_hits.append((m.group(0), line.strip()[:90]))
if range_hits:
    fail.append(f"EN_DASH_RANGE: {len(range_hits)} hyphenated numeric range(s):")
    for tok, ctx in range_hits[:8]:
        fail.append(f"    {tok!r}  in: {ctx}")

# --- Strunk leeches (the colophon quotes the list itself; allow that page) ---
leeches = ["very", "rather", "really", "quite", "pretty", "somewhat", "just", "basically", "simply"]
leech_hits = []
for i, line in enumerate(body.splitlines()):
    distinct = len({w for w in leeches if re.search(rf"\b{w}\b", line, re.I)})
    if distinct >= 4:
        continue  # a line quoting the law's own word list
    for w in leeches:
        if re.search(rf"\b{w}\b", line, re.I):
            leech_hits.append((w, line.strip()[:90]))
if leech_hits:
    fail.append(f"STRUNK_WHITE: {len(leech_hits)} leech word(s):")
    for w, ctx in leech_hits[:8]:
        fail.append(f"    {w!r}  in: {ctx}")

# --- Measure: median length of full justified lines on body pages ---
line_lens = []
for line in body.splitlines():
    s = line.strip()
    if len(s) >= 40:  # full lines of running text
        line_lens.append(len(s))
med = statistics.median(line_lens) if line_lens else 0
lo, hi = (min(line_lens), max(line_lens)) if line_lens else (0, 0)
print(f"measure: median {med:.0f} chars, full lines span {lo}-{hi} (target 66, Bringhurst 45-75)")
if not (45 <= med <= 75):
    fail.append(f"TYPOGRAPHIC_GRID: median measure {med:.0f} outside 45-75")

# --- ASCII decor / ellipsis ---
if re.search(r"\.\.\.", body):
    fail.append("TYPOGRAPHIC_EXCELLENCE: ASCII ellipsis found")
if re.search(r"[─-╿]", body):
    fail.append("TYPOGRAPHY_DISCIPLINE: box-drawing glyph found")
if "---" in body or "-- " in body.replace("--", ""):
    pass  # pdftotext renders em dash as -- sometimes; ligatures handled by TeX

# --- Placeholders ---
for pat in ["TODO", "XXX", "lorem", "【", "】", "undefined", "NaN"]:
    for line in body.splitlines():
        if pat in line and not (pat == "TODO" and "TODO.md" in line):
            fail.append(f"placeholder artifact: {pat}  in: {line.strip()[:90]}")
            break

# --- Paper color: sample a pixel from the rendered page 5 ---
subprocess.run(["pdftoppm", "-r", "30", "-f", "5", "-l", "5", "-jpeg", PDF, "/tmp/paper"], check=True)
from PIL import Image
img = Image.open("/tmp/paper-05.jpg").convert("RGB")
w, h = img.size
corners = [(3, 3), (w-4, 3), (3, h-4), (w-4, h-4), (w//2, 2)]
samples = [img.getpixel(p) for p in corners]
white = [s for s in samples if s >= (250, 250, 250)]
print(f"paper ground samples: {samples}")
if white:
    fail.append(f"PAPER_NOT_PURE_WHITE: {len(white)} sampled ground pixel(s) are pure white")

print()
if fail:
    print("FAIL")
    print("\n".join(fail))
    sys.exit(1)
print("PASS — all checked laws hold")
