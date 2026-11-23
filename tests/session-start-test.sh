#!/usr/bin/env bash
# Tests for hooks/session-start.sh — context budget, section order, compiler health.
# Run: bash tests/session-start-test.sh   → exit 0 = all passed.
#
# Why a budget: in the reference brain the start hook's output grew to 17.5 KB;
# Claude Code put only a ~2 KB preview into context and saved the rest to a
# file — the routing index never reached the model and nobody noticed.
set -u
. "$(dirname "$0")/lib.sh"

BUDGET="${BRAIN_START_BUDGET:-8000}"
run_hook() { # $1 = brain dir, [$2 = cwd] → hook stdout
  ( cd "${2:-$1}" && BRAIN_OFFLINE=1 bash "$1/hooks/session-start.sh" </dev/null )
}

H="$(new_home)"; B="$H/brain"; make_brain "$B"
out="$(run_hook "$B")"
n="$(printf '%s' "$out" | bytes)"

[ "$n" -le "$BUDGET" ] && pass "output within budget ($n ≤ $BUDGET)" || fail "output within budget" "$n > $BUDGET"
case "$out" in *"=== Atlas — Acme shared brain"*) pass "header uses NAME and ORG from brain.conf" ;;
  *) fail "header uses NAME and ORG from brain.conf" "$(printf '%s' "$out" | head -1)" ;; esac

identity="$(cat "$B/locked/identity.md")"
k="$(offset "$out" "$identity")"
[ "$k" -ge 0 ] && [ "$k" -le 600 ] && pass "identity complete and first (byte $k)" || fail "identity complete and first" "offset=$k"

inc="$(offset "$out" "--- Open incidents")"; rt="$(offset "$out" "--- Routing")"; dl="$(offset "$out" "--- Dailies, last 7 days")"
if [ "$k" -ge 0 ] && [ "$inc" -gt "$k" ] && [ "$rt" -gt "$inc" ] && [ "$dl" -gt "$rt" ]; then
  pass "order: identity → open incidents → routing → dailies"
else fail "order: identity → open incidents → routing → dailies" "identity=$k inc=$inc routing=$rt dailies=$dl"; fi

sect="${out#*"--- Open incidents"}"; sect="${sect%%"--- Routing"*}"
case "$sect" in *index-stale-2026-09*cache-flap-2026-08*) pass "open and watching incidents listed" ;;
  *) fail "open and watching incidents listed" "[$sect]" ;; esac
case "$sect" in *old-bug-2026-07*) fail "resolved incidents not listed" "listed" ;; *) pass "resolved incidents not listed" ;; esac
case "$sect" in *" …"*) pass "long incident aliases are cut at a word boundary" ;; *) fail "long incident aliases are cut at a word boundary" "no ellipsis" ;; esac

missing=""; for id in billing-api web-app search-worker; do case "$out" in *"$id"*) ;; *) missing="$missing $id" ;; esac; done
[ -z "$missing" ] && pass "every card id is in the routing summary" || fail "every card id is in the routing summary" "missing:$missing"
case "$out" in *"projects/INDEX.md"*"FIRST"*) pass "points to the full INDEX" ;; *) fail "points to the full INDEX" "no pointer" ;; esac
case "$out" in *"$(date +%F)-mert-bbbb2222.md [web-app, search-worker]"*) pass "dailies are one line: file + related" ;;
  *) fail "dailies are one line: file + related" "not found" ;; esac

last="$(printf '%s\n' "$out" | awk 'NF{l=$0} END{print l}')"
case "$last" in "Rule: at session end"*) pass "rule line is last" ;; *) fail "rule line is last" "[$last]" ;; esac

# Outside the brain's directories: silent.
mkdir -p "$H/elsewhere"
[ -z "$(run_hook "$B" "$H/elsewhere")" ] && pass "silent outside configured directories" || fail "silent outside configured directories" "printed"
# ...unless listed in hooks/brain-dirs.txt (with ~ expansion).
printf '# dirs\n%s\n' "$H/elsewhere" > "$B/hooks/brain-dirs.txt"
[ -n "$(run_hook "$B" "$H/elsewhere")" ] && pass "active in a directory listed in brain-dirs.txt" || fail "active in a directory listed in brain-dirs.txt" "silent"
rm -f "$B/hooks/brain-dirs.txt"

# Kill switch for nested runs (the compiler's own claude -p calls).
[ -z "$( cd "$B" && BRAIN_HOOKS_OFF=1 BRAIN_OFFLINE=1 bash hooks/session-start.sh </dev/null)" ] \
  && pass "BRAIN_HOOKS_OFF=1 silences the hook" || fail "BRAIN_HOOKS_OFF=1 silences the hook" "printed"
rm -rf "$H"

# Stress: 60 open incidents + 40 dailies — budget holds, identity and rule survive,
# truncation is announced.
H="$(new_home)"; B="$H/brain"; make_brain "$B"
for i in $(seq 1 60); do
  printf '| fake-incident-%02d | Incidents | open | %s |\n' "$i" "a long description that eats the budget detail detail detail detail detail" >> "$B/projects/INDEX.md"
done
for i in $(seq 1 40); do
  printf -- '---\nauthor: load\nrelated: [billing-api]\n---\n' > "$B/daily/$(date +%F)-load-s$(printf '%02d' "$i").md"
done
out="$(run_hook "$B")"; n="$(printf '%s' "$out" | bytes)"
[ "$n" -le "$BUDGET" ] && pass "stress: within budget ($n ≤ $BUDGET)" || fail "stress: within budget" "$n > $BUDGET"
[ "$(offset "$out" "$(cat "$B/locked/identity.md")")" -ge 0 ] && pass "stress: identity complete" || fail "stress: identity complete" "cut"
case "$out" in *"budget:"*"truncated"*) pass "stress: truncation announced" ;; *) fail "stress: truncation announced" "silent" ;; esac
last="$(printf '%s\n' "$out" | awk 'NF{l=$0} END{print l}')"
case "$last" in "Rule: at session end"*) pass "stress: rule line is last" ;; *) fail "stress: rule line is last" "[$last]" ;; esac
rm -rf "$H"

# Compiler health — derived from git so every teammate sees it (the nightly
# run's log lives only on the machine that runs it): if the oldest pending
# daily is ≥2 days old, the first incident line says the compiler is not running.
git_brain() { # $1 = brain: everything committed in an old compiler run commit
  g -C "$1" init -q; g -C "$1" add -A
  GIT_COMMITTER_DATE="2026-01-01T03:30:00+00:00" GIT_AUTHOR_DATE="2026-01-01T03:30:00+00:00" \
    g -C "$1" commit -q -m "compiler: 2026-01-01 run"
}
add_daily() { printf -- '---\nauthor: t\n---\n' > "$1/daily/$2"; g -C "$1" add -A; g -C "$1" commit -q -m "daily: $2"; }

H="$(new_home)"; B="$H/brain"; make_brain "$B"; git_brain "$B"; add_daily "$B" "2026-01-05-t-cccc3333.md"
out="$(run_hook "$B")"
w="$(offset "$out" "· compiler — not running — ")"; inc="$(offset "$out" "--- Open incidents")"; first="$(offset "$out" "· index-stale-2026-09")"
if [ "$w" -gt "$inc" ] && [ "$inc" -ge 0 ] && [ "$w" -lt "$first" ]; then pass "stale pending daily → compiler warning is the first incident line"
else fail "stale pending daily → compiler warning is the first incident line" "warning=$w header=$inc first=$first"; fi
case "$out" in *"· compiler — "*"2026-01-05"*) pass "warning names the oldest pending daily" ;; *) fail "warning names the oldest pending daily" "no date" ;; esac
rm -rf "$H"

# Backlog mode: a candidate waiting in the queue for more than 7 days = the queue is not draining.
queue_with() { # $1 = brain, $2 = ADDED date
  mkdir -p "$1/queue" "$1/daily/archive/2026-09"; : > "$1/daily/archive/2026-09/2026-09-22-z-aaaa1111.md"
  printf '# Q\n\n<!-- QUEUE:BEGIN -->\nCANDIDATE: card-feed\nTARGET: billing-api\nBODY: x\nSOURCE: 2026-09-22-z-aaaa1111.md\nADDED: %s\n<!-- QUEUE:END -->\n' "$2" > "$1/queue/candidates.md"
}
H="$(new_home)"; B="$H/brain"; make_brain "$B"; queue_with "$B" "2026-01-01"
out="$(run_hook "$B")"
w="$(offset "$out" "· compiler queue — ")"; inc="$(offset "$out" "--- Open incidents")"; rt="$(offset "$out" "--- Routing")"
if [ "$w" -gt "$inc" ] && [ "$inc" -ge 0 ] && [ "$w" -lt "$rt" ]; then pass "stale queue → warning in the incidents section"
else fail "stale queue → warning in the incidents section" "warning=$w header=$inc routing=$rt"; fi
rm -rf "$H"
H="$(new_home)"; B="$H/brain"; make_brain "$B"; queue_with "$B" "$(date +%F)"
case "$(run_hook "$B")" in *"· compiler queue — "*) fail "fresh queue → no warning" "warned" ;; *) pass "fresh queue → no warning (normal flow)" ;; esac
rm -rf "$H"

H="$(new_home)"; B="$H/brain"; make_brain "$B"; git_brain "$B"; add_daily "$B" "$(date +%F)-t-dddd4444.md"
case "$(run_hook "$B")" in *"· compiler — "*) fail "only today's daily pending → no warning" "warned" ;; *) pass "only today's daily pending → no warning" ;; esac
rm -rf "$H"

finish
