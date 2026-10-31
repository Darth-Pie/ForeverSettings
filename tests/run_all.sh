#!/usr/bin/env bash
# Runs every test_*.lua suite against the build. Exit 0 only if every suite passes.
# Usage: bash run_all.sh   (from anywhere; FSET_PKG and FSET_SRC override where fengari and the addon are)
set -u
T=$(cd "$(dirname "$0")" && pwd)
# In the repository the addon is the folder above this one and fengari is installed beside the tests (npm install);
# on the author's machine they live elsewhere.
if [ -f "$T/../ForeverSettings.toc" ]; then DEFAULT_SRC=$T/..; else DEFAULT_SRC=/c/tmp/fset/build/ForeverSettings; fi
if [ -d "$T/node_modules/fengari" ]; then DEFAULT_PKG=$T; else DEFAULT_PKG=/c/tmp/fset/pkg; fi
PKG=${FSET_PKG:-$DEFAULT_PKG}
SRC=${FSET_SRC:-$DEFAULT_SRC}
status=0
# --format-only skips the suites and the mutations and runs only the TOC and file checks (seconds, not minutes).
if [ "${1:-}" != "--format-only" ]; then
for t in "$T"/test_*.lua; do
  echo "== $(basename "$t")"
  out=$(node "$T/run.js" "$PKG" "$SRC" "$t" 2>&1)
  code=$?
  echo "$out" | tail -1
  if [ "$code" -ne 0 ]; then
    echo "$out" | grep -E '^FAIL|^ERROR|^LUA ERROR'
    status=1
  fi
done
# Every mutation must be killed by its named tests, and the three harness controls must land correctly.
echo "== mutations"
bash "$T/run_mutations.sh" | tail -1
[ "${PIPESTATUS[0]}" -eq 0 ] || status=1
fi

# TOC and file format. A Lua test cannot read files here, so these are shell assertions.
toc=$SRC/ForeverSettings.toc
tocfail() { echo "TOC FAIL: $1"; status=1; }
grep -q '^## Interface: 16001, 120105$' "$toc" || tocfail "the Interface line changed"
grep -q '^## SavedVariables: ForeverSettingsDB$' "$toc" || tocfail "the SavedVariables line is missing"
first=$(grep -n '^ForeverSettings\.lua$' "$toc" | cut -d: -f1)
second=$(grep -n '^Bench\.lua$' "$toc" | cut -d: -f1)
if [ -z "$first" ] || [ -z "$second" ] || [ "$first" -ge "$second" ]; then
  tocfail "Bench.lua must be listed after ForeverSettings.lua"
fi
third=$(grep -n '^UI\.lua$' "$toc" | cut -d: -f1)
if [ -z "$third" ] || [ -z "$second" ] || [ "$second" -ge "$third" ]; then
  tocfail "UI.lua must be listed after Bench.lua"
fi
profiles=$(grep -n '^Profiles\.lua$' "$toc" | cut -d: -f1)
if [ -z "$profiles" ] || [ -z "$second" ] || [ -z "$third" ] || [ "$second" -ge "$profiles" ] || [ "$profiles" -ge "$third" ]; then
  tocfail "Profiles.lua must be listed after Bench.lua and before UI.lua"
fi
guide=$(grep -n '^Guide\.lua$' "$toc" | cut -d: -f1)
if [ -z "$guide" ] || [ -z "$third" ] || [ "$third" -ge "$guide" ]; then
  tocfail "Guide.lua must be listed after UI.lua"
fi
results=$(grep -n '^Results\.lua$' "$toc" | cut -d: -f1)
if [ -z "$results" ] || [ -z "$guide" ] || [ "$guide" -ge "$results" ]; then
  tocfail "Results.lua must be listed after Guide.lua"
fi
recommend=$(grep -n '^Recommend\.lua$' "$toc" | cut -d: -f1)
if [ -z "$recommend" ] || [ -z "$profiles" ] || [ -z "$third" ] || [ "$profiles" -ge "$recommend" ] || [ "$recommend" -ge "$third" ]; then
  tocfail "Recommend.lua must be listed after Profiles.lua and before UI.lua"
fi
names=$(grep -n '^Names\.lua$' "$toc" | cut -d: -f1)
if [ -z "$names" ] || [ -z "$first" ] || [ -z "$second" ] || [ "$first" -ge "$names" ] || [ "$names" -ge "$second" ]; then
  tocfail "Names.lua must be listed after ForeverSettings.lua and before Bench.lua"
fi
settings=$(grep -n '^Settings\.lua$' "$toc" | cut -d: -f1)
if [ -z "$settings" ] || [ -z "$third" ] || [ -z "$guide" ] || [ "$third" -ge "$settings" ] || [ "$settings" -ge "$guide" ]; then
  tocfail "Settings.lua must be listed after UI.lua and before Guide.lua"
fi
graphLine=$(grep -n '^Graph\.lua$' "$toc" | cut -d: -f1)
if [ -z "$graphLine" ] || [ -z "$settings" ] || [ -z "$guide" ] || [ "$settings" -ge "$graphLine" ] || [ "$graphLine" -ge "$guide" ]; then
  tocfail "Graph.lua must be listed after Settings.lua and before Guide.lua"
fi
for f in ForeverSettings.toc ForeverSettings.lua Names.lua Bench.lua Profiles.lua Recommend.lua UI.lua Settings.lua Graph.lua Guide.lua Results.lua; do
  [ "$(head -c 3 "$SRC/$f" | od -An -tx1 | tr -d ' ')" != "efbbbf" ] || tocfail "$f has a byte order mark"
  [ "$(tr -cd '\r' < "$SRC/$f" | wc -c)" -eq 0 ] || tocfail "$f has carriage returns"
done
# The keybinding file is loaded by the game from the addon folder by itself, so it must exist, must not be in the TOC,
# and must run the same call as /fset profile toggle.
bindings=$SRC/Bindings.xml
if [ -f "$bindings" ]; then
  [ "$(tr -cd '\r' < "$bindings" | wc -c)" -eq 0 ] || tocfail "Bindings.xml has carriage returns"
  grep -q '<Binding name="FOREVERSETTINGS_TOGGLE"' "$bindings" || tocfail "Bindings.xml lacks the toggle binding"
  grep -q 'SlashCmdList.FOREVERSETTINGS("profile toggle")' "$bindings" || tocfail "Bindings.xml does not run the profile toggle"
  # The newer Key Bindings screen groups by category=; addons installed beside this one (Plumber, Porter, EnhanceQoL)
  # all use it. header= made it show the raw name HEADER_FOREVERSETTINGS under "Other" (seen in the owner's game).
  grep -q 'category="ForeverSettings"' "$bindings" || tocfail "Bindings.xml has no category=\"ForeverSettings\" on the binding"
  if grep -q 'header=' "$bindings"; then tocfail "Bindings.xml uses header=, which the new Key Bindings screen shows as a raw name"; fi
else
  tocfail "Bindings.xml is missing"
fi
if grep -q '^Bindings\.xml$' "$toc"; then tocfail "Bindings.xml must not be listed in the TOC (the game loads it by itself)"; fi
echo "== TOC and file format: $([ "$status" -eq 0 ] && echo OK || echo FAIL)"
echo "== all suites: $([ "$status" -eq 0 ] && echo PASS || echo FAIL)"
exit $status
