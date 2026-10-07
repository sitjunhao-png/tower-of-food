#!/usr/bin/env bash
# Usage: tools/assemble.lua.sh MODULE_IN MODULE_OUT [fragment files...]
# Replaces everything between the SECTIONS START/END markers with the fragments.
set -euo pipefail
in="$1"; out="$2"; shift 2
python3 - "$in" "$out" "$@" <<'PY'
import sys
src, dst, frags = sys.argv[1], sys.argv[2], sys.argv[3:]
text = open(src).read()
start, end = "-- >>> SECTIONS START\n", "-- <<< SECTIONS END"
a = text.index(start) + len(start); b = text.index(end)
body = ""
for f in frags:
    body += "\n-- ===== " + f.split("/")[-1] + " =====\n" + open(f).read().rstrip() + "\n"
open(dst, "w").write(text[:a] + body + text[b:])
PY
