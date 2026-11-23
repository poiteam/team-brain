#!/usr/bin/env bash
# Tests for install.sh — skeleton (init) and hook registration (hooks).
# Run: bash tests/install-test.sh   → exit 0 = all passed.
#
# Safety contract: init never overwrites a file; hooks never duplicates an entry,
# never drops other tools' hooks or settings, and REFUSES to touch a
# settings.json that is not valid JSON (writing {} over it would wipe the
# user's whole configuration).
set -u
. "$(dirname "$0")/lib.sh"

fresh() { # → a physical temp HOME with a fresh kit copy at $H/brain (git repo, no skeleton)
  H="$(new_home)"; B="$H/brain"; mkdir -p "$B"
  copy_kit "$B"
  g -C "$B" init -q
}
inst() { ( cd "$B" && HOME="$H" bash install.sh "$@" ) >"$H/install.out" 2>&1; echo $?; }
settings() { cat "$H/.claude/settings.json" 2>/dev/null; }
count() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(sum(1 for e in d.get("hooks",{}).get(sys.argv[2],[]) for h in e.get("hooks",[]) if sys.argv[3] in h.get("command","")))' "$H/.claude/settings.json" "$1" "$2"; }

# --- init: skeleton from template/, NAME/ORG into brain.conf, never overwrite
fresh
rc="$(inst init --name Atlas --org Acme)"
[ "$rc" -eq 0 ] && pass "init exits 0" || fail "init exits 0" "rc=$rc: $(cat "$H/install.out")"
missing=""; for f in brain.conf locked/identity.md projects/INDEX.md daily/TEMPLATE.md policies/CANDIDATES.md; do [ -f "$B/$f" ] || missing="$missing $f"; done
[ -z "$missing" ] && pass "init creates the skeleton" || fail "init creates the skeleton" "missing:$missing"
grep -qx 'NAME=Atlas' "$B/brain.conf" && grep -qx 'ORG=Acme' "$B/brain.conf" && pass "init writes NAME/ORG into brain.conf" || fail "init writes NAME/ORG into brain.conf" "$(cat "$B/brain.conf")"
grep -qx 'hooks/\*.local.txt' "$B/.gitignore" && grep -qx '.compiler.log' "$B/.gitignore" && pass "init adds the local files to .gitignore" || fail "init adds the local files to .gitignore" "$(cat "$B/.gitignore" 2>/dev/null)"
(cd "$B" && python3 compiler/candidates.py --check >/dev/null 2>&1) && pass "fresh CANDIDATES.md passes candidates.py --check" || fail "fresh CANDIDATES.md passes candidates.py --check" "stale"

printf 'my own identity\n' > "$B/locked/identity.md"
inst init --name Other --org Else >/dev/null
[ "$(cat "$B/locked/identity.md")" = "my own identity" ] && pass "init never overwrites an existing file" || fail "init never overwrites an existing file" "overwritten"
grep -qx 'NAME=Atlas' "$B/brain.conf" && pass "init keeps an existing brain.conf" || fail "init keeps an existing brain.conf" "changed"
[ "$(grep -cx '.compiler.log' "$B/.gitignore")" -eq 1 ] && pass "init does not duplicate .gitignore lines" || fail "init does not duplicate .gitignore lines" "duplicated"

# --- hooks: register, idempotent, hooksPath, smoke test
rc="$(inst hooks)"
[ "$rc" -eq 0 ] && pass "hooks exits 0" || fail "hooks exits 0" "rc=$rc: $(cat "$H/install.out")"
[ "$(count SessionStart "$B/hooks/session-start.sh")" = "1" ] && [ "$(count Stop "$B/hooks/session-end.sh")" = "1" ] \
  && pass "hooks registers SessionStart and Stop" || fail "hooks registers SessionStart and Stop" "$(settings)"
[ "$(git -C "$B" config core.hooksPath)" = "hooks" ] && pass "hooks sets core.hooksPath" || fail "hooks sets core.hooksPath" "not set"
grep -q "smoke test passed" "$H/install.out" && pass "hooks runs a smoke test of session-start" || fail "hooks runs a smoke test of session-start" "$(tail -3 "$H/install.out")"
inst hooks >/dev/null
[ "$(count SessionStart "$B/hooks/session-start.sh")" = "1" ] && [ "$(count Stop "$B/hooks/session-end.sh")" = "1" ] \
  && pass "hooks is idempotent (no duplicate entries)" || fail "hooks is idempotent" "$(settings)"
rm -rf "$H"

# --- existing settings: other tools' hooks and keys survive; a backup is kept
fresh; inst init --name Atlas --org Acme >/dev/null
mkdir -p "$H/.claude"
cat > "$H/.claude/settings.json" <<'EOF'
{"model": "opus", "hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "/opt/other-tool/start"}]}],
 "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "/opt/guard"}]}]}}
EOF
inst hooks >/dev/null
python3 - "$H/.claude/settings.json" <<'PY' && pass "other tools' hooks and settings survive" || fail "other tools' hooks and settings survive" "$(settings)"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["model"] == "opus"
assert any("/opt/other-tool/start" in h["command"] for e in d["hooks"]["SessionStart"] for h in e["hooks"])
assert d["hooks"]["PreToolUse"][0]["hooks"][0]["command"] == "/opt/guard"
PY
ls "$H/.claude/" | grep -q '^settings.json.bak-' && pass "a backup of the previous settings.json is kept" || fail "a backup of the previous settings.json is kept" "$(ls "$H/.claude")"
rm -rf "$H"

# --- invalid settings.json: refuse, leave it byte-for-byte unchanged
fresh; inst init --name Atlas --org Acme >/dev/null
mkdir -p "$H/.claude"; printf '{ "model": "opus", broken\n' > "$H/.claude/settings.json"
before="$(settings)"
rc="$(inst hooks)"
[ "$rc" -ne 0 ] && pass "invalid settings.json → non-zero exit" || fail "invalid settings.json → non-zero exit" "rc=0"
[ "$(settings)" = "$before" ] && pass "invalid settings.json is left untouched" || fail "invalid settings.json is left untouched" "modified"
rm -rf "$H"

# --- CLAUDE_CONFIG_DIR is honoured
fresh; inst init --name Atlas --org Acme >/dev/null
( cd "$B" && HOME="$H" CLAUDE_CONFIG_DIR="$H/alt-claude" bash install.sh hooks ) >/dev/null 2>&1
[ -f "$H/alt-claude/settings.json" ] && [ ! -f "$H/.claude/settings.json" ] && pass "CLAUDE_CONFIG_DIR is honoured" || fail "CLAUDE_CONFIG_DIR is honoured" "wrong location"
rm -rf "$H"

# --- no argument = init + hooks
fresh
rc="$(inst --name Atlas --org Acme)"
[ "$rc" -eq 0 ] && [ -f "$B/locked/identity.md" ] && [ "$(count Stop "$B/hooks/session-end.sh")" = "1" ] \
  && pass "no subcommand runs init and hooks" || fail "no subcommand runs init and hooks" "rc=$rc"
rm -rf "$H"

# --- init records the installed kit version (.brain-kit/) when the release has a kit.manifest
fresh
( cd "$B" && python3 kit/manifest.py build --root . hooks/common.sh > kit.manifest )
inst init --name Atlas --org Acme >/dev/null
[ -f "$B/.brain-kit/manifest" ] && cmp -s "$B/.brain-kit/manifest" "$B/kit.manifest" \
  && [ "$(cat "$B/.brain-kit/version")" = "$(cat "$B/kit/VERSION")" ] \
  && pass "init writes .brain-kit/manifest and version" || fail "init writes .brain-kit/manifest and version" "$(ls -a "$B/.brain-kit" 2>&1)"
printf 'keep\n' > "$B/.brain-kit/version"
inst init >/dev/null
[ "$(cat "$B/.brain-kit/version")" = "keep" ] && pass "init keeps existing .brain-kit state" || fail "init keeps existing .brain-kit state" "overwritten"
rm -rf "$H"
fresh; rm -f "$B/kit.manifest"   # a development checkout of the kit has none (a release does)
inst init --name Atlas --org Acme >/dev/null
[ ! -e "$B/.brain-kit" ] && grep -q "kit.manifest" "$H/install.out" \
  && pass "init without kit.manifest (dev checkout) skips state and says so" || fail "init without kit.manifest skips state" "$(cat "$H/install.out")"
rm -rf "$H"

# --- hooks prunes this brain's entries whose script no longer exists (an update removed it)
fresh; inst init --name Atlas --org Acme >/dev/null
mkdir -p "$H/.claude"
BM="$B"; command -v cygpath >/dev/null 2>&1 && BM="$(cygpath -m "$B")"   # Windows: install writes C:/… paths
cat > "$H/.claude/settings.json" <<EOF
{"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "$BM/hooks/old-hook.sh"}]},
                            {"hooks": [{"type": "command", "command": "other-tool --on-start"}]}]}}
EOF
inst hooks >/dev/null
# the other tool's marker must not look like a path: Git Bash rewrites /opt/… arguments to C:/…
[ "$(count SessionStart "$B/hooks/old-hook.sh")" = "0" ] && [ "$(count SessionStart "other-tool --on-start")" = "1" ] \
  && [ "$(count SessionStart "$B/hooks/session-start.sh")" = "1" ] \
  && pass "hooks prunes stale entries of this brain, keeps others" || fail "hooks prunes stale entries" "$(settings)"
rm -rf "$H"

# --- Windows: Python writes to a cp1252 console; the kit prints ✓/→ and must not crash
fresh
rc="$( ( cd "$B" && HOME="$H" PYTHONIOENCODING=cp1252 bash install.sh --name Atlas --org Acme ) >"$H/install.out" 2>&1; echo $?)"
[ "$rc" -eq 0 ] && [ "$(count Stop "$B/hooks/session-end.sh")" = "1" ] \
  && pass "install works when Python's console is cp1252 (Windows)" || fail "install with a cp1252 console" "rc=$rc $(tail -3 "$H/install.out")"
rm -rf "$H"

# --- a brain path with a space: the registered command must still run
H="$(new_home)"; B="$H/My Brain"; mkdir -p "$B"
copy_kit "$B"
g -C "$B" init -q
rc="$(inst --name Atlas --org Acme)"
[ "$rc" -eq 0 ] && grep -q "smoke test passed" "$H/install.out" \
  && pass "install works with a space in the brain path" || fail "install works with a space in the brain path" "rc=$rc $(tail -3 "$H/install.out")"
cmd="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(next(h["command"] for e in d["hooks"]["SessionStart"] for h in e["hooks"] if "session-start" in h["command"]))' "$H/.claude/settings.json")"
out="$(cd "$B" && HOME="$H" BRAIN_OFFLINE=1 sh -c "$cmd" </dev/null 2>&1)"
case "$out" in "=== Atlas — "*) pass "registered command runs from a path with a space" ;; *) fail "registered command runs from a path with a space" "$cmd → $(printf '%s' "$out" | head -2)" ;; esac
rm -rf "$H"

finish
