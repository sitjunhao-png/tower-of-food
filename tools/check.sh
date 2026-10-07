#!/usr/bin/env bash
# Type-check every script against the Roblox API and run the section test harness.
#   tools/check.sh                     -> uses all build/sections/*.lua fragments (or the module as-is if none)
#   tools/check.sh build/sections/b.lua -> only those fragments in the module
# Works on a private temp copy, so several people can run it at once.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$ROOT/.tools"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp -r "$ROOT/src" "$TMP/src"; cp "$ROOT/sourcemap.json" "$TMP/"
MOD="$TMP/src/ServerScriptService/TowerSections.lua"
if [ "$#" -gt 0 ]; then FRAGS=("$@"); else shopt -s nullglob; FRAGS=("$ROOT"/build/sections/*.lua); fi
if [ "${#FRAGS[@]}" -gt 0 ]; then
  ABS=(); for f in "${FRAGS[@]}"; do ABS+=("$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"); done
  "$ROOT/tools/assemble.lua.sh" "$ROOT/src/ServerScriptService/TowerSections.lua" "$MOD" "${ABS[@]}"
fi
# Force strict mode on the temp copies (catches wrong property / method names). Line numbers are fixed up below.
for f in "$TMP"/src/ServerScriptService/*.lua "$TMP"/src/StarterPlayer/StarterPlayerScripts/*.lua; do
  [ -f "$f" ] && { printf -- '--!strict\n' | cat - "$f" > "$f.tmp" && mv "$f.tmp" "$f"; }
done
status=0
echo "=== Type check (strict, luau-lsp + Roblox API) ==="
FILES=()
for f in "$TMP"/src/ServerScriptService/*.lua "$TMP"/src/StarterPlayer/StarterPlayerScripts/*.lua; do [ -f "$f" ] && FILES+=("$f"); done
( cd "$TMP" && "$T/luau-lsp" analyze --platform=roblox --sourcemap=sourcemap.json --definitions=@roblox="$T/globalTypes.d.luau" "${FILES[@]}" 2>&1 \
  | grep -v '^\[INFO\]' | grep -v '^\[WARN\]' | sed "s#$TMP/##g; s#^\(\.\./\)*##" \
  | perl -pe 's/\((\d+),(\d+)\)/"(".($1-1).",$2)"/e' ) > "$TMP/lsp.txt"
cat "$TMP/lsp.txt"
if grep -q 'Error' "$TMP/lsp.txt"; then status=1; echo ">> TYPE ERRORS FOUND"; else echo ">> type check: no errors"; fi
if [ -f "$ROOT/tests/mocks.luau" ] && [ -f "$ROOT/tests/section_checks.luau" ]; then
  echo "=== Section harness ==="
  { cat "$ROOT/tests/mocks.luau"; echo; echo "local TowerSections = (function()";
    sed 's/^export type /type /' "$MOD"; echo; echo "end)()"; cat "$ROOT/tests/section_checks.luau"; } > "$TMP/harness_run.luau"
  if ! "$T/luau" "$TMP/harness_run.luau"; then status=1; echo ">> HARNESS FAILED"; fi
fi
exit $status
