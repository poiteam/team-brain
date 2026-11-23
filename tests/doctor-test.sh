#!/usr/bin/env bash
# Tests for `install.sh doctor` — one screen that says why an install does not work.
# Run: bash tests/doctor-test.sh   → exit 0 = all passed.
#
# Every check prints one line: "OK   <check>", "FAIL <check> — <how to fix>" or
# "SKIP <check> — <why>". Exit 0 only when nothing FAILs. Stub tools (claude, gh)
# come first on PATH; git and python3 come from the system.
set -u
. "$(dirname "$0")/lib.sh"

# git and Python from the system; on Windows CI python3 is a shim that execs `python`
SYS_PATH="$(dirname "$(command -v git)"):$(dirname "$(command -v python3)")"
command -v python >/dev/null 2>&1 && SYS_PATH="$SYS_PATH:$(dirname "$(command -v python)")"
SYS_PATH="$SYS_PATH:/usr/bin:/bin"

setup() { # → $H, $B (initialised + hooked brain), $STUB (stub bin dir with claude)
  H="$(new_home)"; B="$H/brain"; STUB="$H/stub"; mkdir -p "$B" "$STUB"
  copy_kit "$B"
  g -C "$B" init -q
  ( cd "$B" && HOME="$H" bash install.sh --name Atlas --org Acme ) >/dev/null 2>&1
  printf '#!/bin/sh\necho OK\n' > "$STUB/claude"; chmod +x "$STUB/claude"
}
doc() { ( cd "$B" && HOME="$H" PATH="${P:-$STUB:$SYS_PATH}" BRAIN_OFFLINE="${OFF-1}" bash install.sh doctor "$@" ) >"$H/doc.out" 2>&1; echo $?; }
line() { grep -E "^(OK|FAIL|SKIP) +$1( |$)" "$H/doc.out"; }
has_fail() { line "$1" | grep -q '^FAIL'; }

# --- healthy install
setup
rc="$(doc)"
[ "$rc" -eq 0 ] && ! grep -q '^FAIL' "$H/doc.out" && pass "healthy install: exit 0, no FAIL" || fail "healthy install" "rc=$rc $(grep FAIL "$H/doc.out")"
for c in git python3 claude brain.conf contract settings.json pre-push session-start; do
  line "$c" | grep -q '^OK' && pass "healthy: $c OK" || fail "healthy: $c OK" "$(line "$c")"
done
line "kit version" | grep -q '^SKIP' && pass "offline: kit version SKIP" || fail "offline: kit version SKIP" "$(line "kit version")"

# --- Windows: a cp1252 console must not crash a check (a crash must never read as OK)
rc="$( ( cd "$B" && HOME="$H" PATH="$STUB:$SYS_PATH" BRAIN_OFFLINE=1 PYTHONIOENCODING=cp1252 bash install.sh doctor ) >"$H/doc.out" 2>&1; echo $?)"
[ "$rc" -eq 0 ] && line settings.json | grep -q '^OK' && pass "cp1252 console: doctor still OK" || fail "cp1252 console" "rc=$rc $(grep -v '^OK' "$H/doc.out" | head -3)"
cp "$H/.claude/settings.json" "$H/settings.keep"
printf '{ broken \xe2\x80\x94\n' > "$H/.claude/settings.json"
rc="$( ( cd "$B" && HOME="$H" PATH="$STUB:$SYS_PATH" BRAIN_OFFLINE=1 PYTHONIOENCODING=cp1252 bash install.sh doctor ) >"$H/doc.out" 2>&1; echo $?)"
[ "$rc" -eq 1 ] && has_fail settings.json && pass "cp1252 console: broken settings.json still FAILs" || fail "cp1252: broken settings" "rc=$rc $(line settings.json)"
cp "$H/settings.keep" "$H/.claude/settings.json"
mkdir -p "$H/cfg✓"; printf '{ broken\n' > "$H/cfg✓/settings.json"
rc="$( ( cd "$B" && HOME="$H" CLAUDE_CONFIG_DIR="$H/cfg✓" PATH="$STUB:$SYS_PATH" BRAIN_OFFLINE=1 PYTHONIOENCODING=cp1252 bash install.sh doctor ) >"$H/doc.out" 2>&1; echo $?)"
[ "$rc" -eq 1 ] && has_fail settings.json && pass "a check whose Python crashes is a FAIL, never OK" || fail "crashing check fails closed" "rc=$rc $(line settings.json)"

# --- Windows: brain.conf checked out with CRLF (core.autocrlf=true) must still be read
cp "$B/brain.conf" "$H/conf.keep"; python3 -c 'import sys; p=sys.argv[1]; d=open(p,"rb").read().replace(b"\r\n",b"\n").replace(b"\n",b"\r\n"); open(p,"wb").write(d)' "$B/brain.conf"
rc="$(doc)"
[ "$rc" -eq 0 ] && line contract | grep -q '^OK' && line session-start | grep -q '^OK' \
  && pass "CRLF brain.conf: contract and session-start OK" || fail "CRLF brain.conf" "rc=$rc $(grep -v '^OK' "$H/doc.out" | head -3)"
cp "$H/conf.keep" "$B/brain.conf"

# --- missing claude
rc="$(P="$SYS_PATH" doc)"
[ "$rc" -eq 1 ] && has_fail claude && line claude | grep -qi install && pass "missing claude → FAIL with install hint" || fail "missing claude" "rc=$rc $(line claude)"

# --- contract older / newer than the kit
sed -i.bak 's/^CONTRACT_VERSION=.*/CONTRACT_VERSION=0/' "$B/brain.conf"
rc="$(doc)"; [ "$rc" -eq 1 ] && line contract | grep -q CHANGELOG && pass "older contract → FAIL pointing at CHANGELOG" || fail "older contract" "$(line contract)"
sed -i.bak 's/^CONTRACT_VERSION=.*/CONTRACT_VERSION=99/' "$B/brain.conf"
rc="$(doc)"; [ "$rc" -eq 1 ] && line contract | grep -q "install.sh update" && pass "newer contract → FAIL pointing at update" || fail "newer contract" "$(line contract)"
sed -i.bak '/^CONTRACT_VERSION=/d' "$B/brain.conf"
rc="$(doc)"; [ "$rc" -eq 1 ] && has_fail contract && pass "missing CONTRACT_VERSION → FAIL" || fail "missing CONTRACT_VERSION" "$(line contract)"
printf 'CONTRACT_VERSION=%s\n' "$(cat "$B/kit/CONTRACT")" >> "$B/brain.conf"

# --- settings.json: invalid, or hooks pointing at another brain
cp "$H/.claude/settings.json" "$H/settings.good"
printf '{ broken\n' > "$H/.claude/settings.json"
rc="$(doc)"; [ "$rc" -eq 1 ] && has_fail settings.json && pass "invalid settings.json → FAIL" || fail "invalid settings.json" "$(line settings.json)"
BM="$B"; command -v cygpath >/dev/null 2>&1 && BM="$(cygpath -m "$B")"   # Windows: registered as C:/…
sed "s|$BM/hooks|/elsewhere/hooks|g" "$H/settings.good" > "$H/.claude/settings.json"
rc="$(doc)"; [ "$rc" -eq 1 ] && has_fail settings.json && pass "hooks pointing elsewhere → FAIL" || fail "hooks pointing elsewhere" "$(line settings.json)"
cp "$H/settings.good" "$H/.claude/settings.json"

# --- pre-push scan not wired
g -C "$B" config --unset core.hooksPath
rc="$(doc)"; [ "$rc" -eq 1 ] && has_fail pre-push && pass "no core.hooksPath → FAIL pre-push" || fail "no core.hooksPath" "$(line pre-push)"
g -C "$B" config core.hooksPath hooks

# --- kit version against the upstream (online)
U="$H/upstream"; mkdir -p "$U"; g -C "$U" init -q; g -C "$U" commit -q --allow-empty -m x; g -C "$U" tag v0.9.0
mkdir -p "$B/.brain-kit"; printf '0.1.0\n' > "$B/.brain-kit/version"
rc="$( ( cd "$B" && HOME="$H" PATH="$STUB:$SYS_PATH" KIT_UPSTREAM="$U" bash install.sh doctor ) >"$H/doc.out" 2>&1; echo $?)"
[ "$rc" -eq 0 ] && line "kit version" | grep -q "v0.9.0" && pass "online: newer release is reported, not a failure" || fail "online kit version" "rc=$rc $(line "kit version")"
rc="$( ( cd "$B" && HOME="$H" PATH="$STUB:$SYS_PATH" KIT_UPSTREAM="$H/nowhere" bash install.sh doctor ) >"$H/doc.out" 2>&1; echo $?)"
[ "$rc" -eq 0 ] && line "kit version" | grep -q '^SKIP' && pass "unreachable upstream → SKIP" || fail "unreachable upstream" "rc=$rc $(line "kit version")"

# --- --runner on Windows: not a runner platform in this version → one clear FAIL
rc="$( ( cd "$B" && HOME="$H" PATH="$STUB:$SYS_PATH" BRAIN_OFFLINE=1 RUNNER_OS=mingw64_nt-10.0 bash install.sh doctor --runner ) >"$H/doc.out" 2>&1; echo $?)"
[ "$rc" -eq 1 ] && line runner | grep -qi windows && ! line gh >/dev/null \
  && pass "--runner on Windows → FAIL runner (Windows), no runner checks" || fail "--runner on Windows" "rc=$rc $(line runner) $(line gh)"

case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) echo "SKIP --runner checks on a Windows host"; rm -rf "$H"; finish ;; esac
# --- --runner: gh, remote, claude login, schedule
rc="$(doc --runner)"
[ "$rc" -eq 1 ] && has_fail gh && has_fail remote && pass "--runner without gh/remote → FAIL" || fail "--runner without gh/remote" "$(line gh) | $(line remote)"
printf '#!/bin/sh\n[ "$1 $2" = "auth status" ] && exit 0\nexit 1\n' > "$STUB/gh"; chmod +x "$STUB/gh"
g -C "$B" remote add origin https://example.com/acme/brain.git
rc="$(doc --runner)"
line gh | grep -q '^OK' && line remote | grep -q '^OK' && line "claude login" | grep -q '^OK' \
  && pass "--runner: gh, remote, claude login OK" || fail "--runner checks" "$(line gh) | $(line remote) | $(line "claude login")"
printf '#!/bin/sh\necho "Invalid API key · Please run /login"\nexit 1\n' > "$STUB/claude"
rc="$(doc --runner)"; [ "$rc" -eq 1 ] && has_fail "claude login" && pass "--runner: claude not logged in → FAIL" || fail "claude not logged in" "$(line "claude login")"
line schedule >/dev/null && pass "--runner reports the schedule" || fail "--runner reports the schedule" "no schedule line"
rm -rf "$H"

finish
