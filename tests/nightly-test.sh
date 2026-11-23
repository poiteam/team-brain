#!/usr/bin/env bash
# Tests for compiler/nightly.sh — failure reporting and portability.
# Run: bash tests/nightly-test.sh   → exit 0 = all passed.
#
# Why: in the reference brain the nightly run hit the CLI's weekly limit four
# nights in a row (exit 1, message on STDOUT) while its log said "done (exit 0)"
# — the trailing $? belonged to the last for loop. And a PATH pinned to one nvm
# version would turn a node upgrade into a silent "command not found".
set -u
. "$(dirname "$0")/lib.sh"

# setup <claude body> [nvm version | none] [brain path relative to HOME] → "HOME<TAB>BRAIN"
setup() {
  local body="$1" ver="${2:-v24.14.1}" rel="${3:-brain}" h b
  h="$(new_home)"; b="$h/$rel"
  make_brain "$b"
  if [ "$ver" != "none" ]; then
    mkdir -p "$h/.nvm/versions/node/$ver/bin"
    printf '#!/usr/bin/env bash\n%s\n' "$body" > "$h/.nvm/versions/node/$ver/bin/claude"
    chmod +x "$h/.nvm/versions/node/$ver/bin/claude"
  fi
  g -C "$b" init -q 2>/dev/null
  printf '%s\t%s' "$h" "$b"
}
split() { H="${1%%$'\t'*}"; B="${1#*$'\t'}"; }
# A real claude on the system PATH must not rescue the "claude missing" case:
# the script builds its own PATH; the test calls it with a minimal one.
run() { HOME="$1" PATH="/usr/bin:/bin" bash "$2/compiler/nightly.sh" >/dev/null 2>&1; echo $?; }
log() { cat "$1/.compiler.log" 2>/dev/null; }

split "$(setup "echo \"You've hit your weekly limit · resets 3am\"; exit 1")"
rc="$(run "$H" "$B")"
[ "$rc" -ne 0 ] && pass "limit → non-zero exit (rc=$rc)" || fail "limit → non-zero exit" "rc=0"
case "$(log "$B")" in *"FAILED"*"limit"*) pass "log says FAILED with the reason" ;; *) fail "log says FAILED with the reason" "$(log "$B" | tail -2 | tr '\n' ' ')" ;; esac
case "$(log "$B")" in *"done (exit 0)"*) fail "log does not claim success" "'done (exit 0)'" ;; *) pass "log does not claim success" ;; esac
rm -rf "$H"

split "$(setup "echo \"You've hit your session limit · resets 3:40am\"; exit 0")"
[ "$(run "$H" "$B")" -ne 0 ] && pass "limit message with exit 0 is still a failure" || fail "limit message with exit 0 is still a failure" "rc=0"
rm -rf "$H"

split "$(setup "echo 'card-feed: the docs page explains the API rate limit and the usage limit'; exit 0")"
[ "$(run "$H" "$B")" -eq 0 ] && pass "'rate limit' as content is not a false alarm" || fail "'rate limit' as content is not a false alarm" "rc≠0"
rm -rf "$H"

split "$(setup "echo 'nothing to compile'; exit 0")"
rc="$(run "$H" "$B")"
[ "$rc" -eq 0 ] && pass "successful run exits 0" || fail "successful run exits 0" "rc=$rc"
case "$(log "$B")" in *"done (exit 0)"*) pass "successful run logs 'done (exit 0)'" ;; *) fail "successful run logs 'done (exit 0)'" "$(log "$B" | tail -1)" ;; esac
rm -rf "$H"

split "$(setup "echo 'nothing to compile'; exit 0" v25.1.0)"
[ "$(run "$H" "$B")" -eq 0 ] && pass "a different nvm node version still finds claude" || fail "a different nvm node version still finds claude" "$(log "$B" | tail -1)"
rm -rf "$H"

# A newer node without claude installed (nvm install, globals not migrated):
# pick the newest version that CONTAINS claude, not the newest version.
split "$(setup "echo 'nothing to compile'; exit 0" v24.14.1)"
mkdir -p "$H/.nvm/versions/node/v25.1.0/bin"
[ "$(run "$H" "$B")" -eq 0 ] && pass "a newer node without claude does not break the run" || fail "a newer node without claude does not break the run" "$(log "$B" | tail -1)"
rm -rf "$H"

split "$(setup "echo 'nothing to compile'; exit 0" v24.14.1 work/some/brain)"
rc="$(run "$H" "$B")"
if [ "$rc" -eq 0 ] && [ -n "$(log "$B")" ]; then pass "brain path comes from the script's location"
else fail "brain path comes from the script's location" "rc=$rc"; fi
rm -rf "$H"

# Backlog mode: no new dailies but a non-empty queue must not stop the run.
split "$(setup "for a in \"\$@\"; do last=\"\$a\"; done; printf '%s' \"\$last\" > \"\$HOME/prompt.txt\"; echo 'nothing to compile'; exit 0")"
run "$H" "$B" >/dev/null
case "$(cat "$H/prompt.txt" 2>/dev/null)" in *"queue/candidates.md"*"queued candidates"*) pass "nightly prompt: run even without new dailies if the queue has candidates" ;;
  *) fail "nightly prompt: run even without new dailies if the queue has candidates" "no queue condition" ;; esac
rm -rf "$H"

# claude installed outside nvm/Homebrew (Linux package, custom prefix): the caller's
# PATH is kept, after the known locations.
split "$(setup "" none)"
mkdir -p "$H/bin"; printf '#!/usr/bin/env bash\necho "nothing to compile"\n' > "$H/bin/claude"; chmod +x "$H/bin/claude"
rc="$(HOME="$H" PATH="$H/bin:/usr/bin:/bin" bash "$B/compiler/nightly.sh" >/dev/null 2>&1; echo $?)"
[ "$rc" -eq 0 ] && pass "claude only on the inherited PATH is found" || fail "claude only on the inherited PATH is found" "$(log "$B" | tail -1)"
rm -rf "$H"

split "$(setup "" none)"
rc="$(run "$H" "$B")"
[ "$rc" -ne 0 ] && pass "no claude → non-zero exit" || fail "no claude → non-zero exit" "rc=0"
case "$(log "$B")" in *"FAILED"*"claude not found"*) pass "no claude → log says so" ;; *) fail "no claude → log says so" "$(log "$B" | tail -1)" ;; esac
rm -rf "$H"

finish
