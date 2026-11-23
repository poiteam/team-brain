#!/usr/bin/env bash
# Tests for `install.sh runner` — schedule the nightly compiler on ONE machine per team.
# Run: bash tests/runner-test.sh   → exit 0 = all passed.
#
# macOS: a LaunchAgent plist + launchctl bootstrap. Linux: one crontab line tagged
# "# team-brain:<slug>" (slug = first 8 hex of sha256 of the brain path, so two
# brains on one machine do not collide). Stubs stand in for launchctl and crontab;
# RUNNER_OS picks the platform. Paths with spaces must survive both.
set -u
. "$(dirname "$0")/lib.sh"

setup() { # [brain dir name] → $H, $B, stubs, env
  H="$(new_home)"; B="$H/${1:-brain}"; mkdir -p "$B" "$H/stub" "$H/LaunchAgents"
  (cd "$KIT" && tar cf - --exclude='tests/__pycache__' --exclude='compiler/__pycache__' --exclude='kit/__pycache__' .) | (cd "$B" && tar xf -)
  printf 'NAME=Atlas\nORG=Acme\n' > "$B/brain.conf"
  printf '#!/bin/sh\necho "$*" >> "%s/launchctl.log"\n' "$H" > "$H/stub/launchctl"
  cat > "$H/stub/crontab" <<STUB
#!/bin/sh
case "\$1" in
  -l) [ -f "$H/crontab" ] && cat "$H/crontab" || { echo "no crontab for user" >&2; exit 1; } ;;
  -)  cat > "$H/crontab" ;;
esac
STUB
  chmod +x "$H/stub/launchctl" "$H/stub/crontab"
}
rn() { ( cd "$B" && HOME="$H" RUNNER_OS="$1" LAUNCHD_DIR="$H/LaunchAgents" LAUNCHCTL="$H/stub/launchctl" CRONTAB="$H/stub/crontab" bash install.sh runner ${2:-} ) >"$H/runner.out" 2>&1; echo $?; }
plist() { ls "$H/LaunchAgents"/*.plist 2>/dev/null; }
pyget() { python3 -c 'import plistlib,sys; d=plistlib.load(open(sys.argv[1],"rb")); print(eval(sys.argv[2]))' "$(plist)" "$1"; }
tagged() { local n; n="$(grep -c '# team-brain:' "$H/crontab" 2>/dev/null)"; echo "${n:-0}"; }

# On a Windows host, Python sees C:/… paths: the darwin plist cases are meaningless there.
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) WINHOST=1 ;; *) WINHOST=0 ;; esac

# --- macOS
if [ "$WINHOST" -eq 1 ]; then echo "SKIP darwin cases on a Windows host"; else
setup
rc="$(rn darwin)"
[ "$rc" -eq 0 ] && [ "$(plist | wc -l | tr -d ' ')" = "1" ] && pass "darwin: install writes one plist" || fail "darwin: install writes one plist" "rc=$rc $(cat "$H/runner.out")"
[ "$(pyget 'd["StartCalendarInterval"]["Hour"], d["StartCalendarInterval"]["Minute"]')" = "(3, 30)" ] \
  && pass "darwin: default time 03:30" || fail "darwin: default time 03:30" "$(pyget 'd["StartCalendarInterval"]')"
[ "$(pyget 'd["ProgramArguments"]')" = "['/bin/bash', '$B/compiler/nightly.sh']" ] \
  && pass "darwin: runs compiler/nightly.sh with bash" || fail "darwin: ProgramArguments" "$(pyget 'd["ProgramArguments"]')"
grep -q '^bootstrap gui/' "$H/launchctl.log" && pass "darwin: launchctl bootstrap" || fail "darwin: launchctl bootstrap" "$(cat "$H/launchctl.log")"
rn darwin --status >/dev/null; [ "$(rn darwin --status)" -eq 0 ] && pass "darwin: --status after install = 0" || fail "darwin: --status" "$(cat "$H/runner.out")"
: > "$H/launchctl.log"; rn darwin >/dev/null
[ "$(plist | wc -l | tr -d ' ')" = "1" ] && [ "$(head -1 "$H/launchctl.log" | cut -d' ' -f1)" = "bootout" ] && grep -q '^bootstrap' "$H/launchctl.log" \
  && pass "darwin: reinstall is idempotent (bootout, then bootstrap)" || fail "darwin: reinstall" "$(cat "$H/launchctl.log")"
rc="$(rn darwin --remove)"
[ "$rc" -eq 0 ] && [ -z "$(plist)" ] && [ "$(rn darwin --status)" -ne 0 ] && pass "darwin: --remove deletes the plist" || fail "darwin: --remove" "$(plist)"
rm -rf "$H"
fi

# --- Linux
setup
printf '0 1 * * * /usr/bin/other-job\n' > "$H/crontab"
rc="$(rn linux)"
[ "$rc" -eq 0 ] && [ "$(tagged)" = "1" ] && grep -q '^30 3 \* \* \* /bin/bash ' "$H/crontab" \
  && pass "linux: install adds one 03:30 line" || fail "linux: install" "rc=$rc $(cat "$H/crontab")"
rn linux >/dev/null; [ "$(tagged)" = "1" ] && pass "linux: twice → still one line" || fail "linux: idempotent" "$(cat "$H/crontab")"
grep -qx '0 1 \* \* \* /usr/bin/other-job' "$H/crontab" && pass "linux: other cron lines kept" || fail "linux: other lines kept" "$(cat "$H/crontab")"
[ "$(rn linux --status)" -eq 0 ] && pass "linux: --status after install = 0" || fail "linux: --status" "$(cat "$H/runner.out")"
rn linux --remove >/dev/null
[ "$(tagged)" = "0" ] && grep -qx '0 1 \* \* \* /usr/bin/other-job' "$H/crontab" && pass "linux: --remove drops only our line" || fail "linux: --remove" "$(cat "$H/crontab")"
rm -rf "$H"
setup; rc="$(rn linux)"; [ "$rc" -eq 0 ] && [ "$(tagged)" = "1" ] && pass "linux: works with no crontab yet" || fail "linux: no crontab yet" "rc=$rc $(cat "$H/runner.out")"
rm -rf "$H"

# --- Windows is not a runner platform (docs/kit/runner.md)
setup; rc="$(rn mingw64_nt-10.0)"
[ "$rc" -ne 0 ] && grep -qi "windows" "$H/runner.out" && [ ! -f "$H/crontab" ] && pass "windows: refused with a clear message" || fail "windows: refused" "rc=$rc $(cat "$H/runner.out")"
rm -rf "$H"

# --- NIGHTLY_AT
setup; printf 'NIGHTLY_AT=04:05\n' >> "$B/brain.conf"; rn linux >/dev/null
grep -q '^5 4 \* \* \* ' "$H/crontab" && pass "NIGHTLY_AT=04:05 → '5 4 * * *'" || fail "NIGHTLY_AT" "$(cat "$H/crontab")"
printf 'NIGHTLY_AT=25:00\n' >> "$B/brain.conf"
rc="$(rn linux)"; [ "$rc" -ne 0 ] && grep -q "NIGHTLY_AT" "$H/runner.out" && pass "NIGHTLY_AT=25:00 rejected" || fail "NIGHTLY_AT=25:00 rejected" "rc=$rc"
rm -rf "$H"

# --- a brain path with a space (and a %, special in crontab)
setup "My Brain%1"
if [ "$WINHOST" -eq 0 ]; then
  rn darwin >/dev/null
  [ "$(pyget 'd["ProgramArguments"][1]')" = "$B/compiler/nightly.sh" ] && pass "darwin: space in path kept as one argument" || fail "darwin: space in path" "$(pyget 'd["ProgramArguments"]')"
fi
rn linux >/dev/null
line="$(grep '# team-brain:' "$H/crontab")"
cmd="${line#* * * * * }"; cmd="${cmd% # team-brain:*}"; cmd="$(printf '%s' "$cmd" | sed 's/\\%/%/g')"   # cron unescapes \%
( cd "$H" && HOME="$H" PATH=/usr/bin:/bin sh -c "$cmd" ) >/dev/null 2>&1
grep -q "nightly run started" "$B/.compiler.log" 2>/dev/null && pass "linux: cron command runs from a path with a space and %" \
  || fail "linux: cron command with space/%" "$line"
rm -rf "$H"

finish
