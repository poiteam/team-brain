#!/usr/bin/env bash
# Tests for compiler/new-dailies.sh — the compiler's watermark.
# Run: bash tests/new-dailies-test.sh   → exit 0 = all passed.
#
# Why: a watermark described in prose ("the latest compiler commit") gets
# interpreted by the agent, and two readings silently skip uncompiled dailies:
#   - `git log --grep` also matches the BODY of a GitHub merge commit, which
#     carries the PR title ("compiler: 2026-09-22 run") → the mark jumps to the
#     merge moment;
#   - any human commit whose subject starts with "compiler:" becomes the mark.
# The script only accepts run commits: subject "compiler: YYYY-MM-DD …".
set -u

KIT="$(cd "$(dirname "$0")/.." && pwd -P)"
fails=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s — %s\n' "$1" "$2"; fails=$((fails+1)); }

T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"
g() { git -c user.email=t@t -c user.name=t -c maintenance.auto=false -c gc.auto=0 "$@"; }
g init -q --bare "$T/origin.git"
g clone -q "$T/origin.git" "$T/w" 2>/dev/null
cd "$T/w" || exit 1
g checkout -q -b main
mkdir -p compiler daily/archive/2026-09
cp "$KIT/compiler/new-dailies.sh" compiler/
# Equal-second commits make `git log` order ambiguous → strictly increasing dates.
n=0; tick() { n=$((n+1)); export GIT_COMMITTER_DATE="2026-09-26T10:00:$(printf %02d $n)+00:00" GIT_AUTHOR_DATE="2026-09-26T10:00:$(printf %02d $n)+00:00"; }
c() { tick; g add -A; g commit -q -m "$1"; }
d() { printf 'x\n' > "daily/$1"; c "daily: $1"; }
run() { bash compiler/new-dailies.sh "$@" 2>/dev/null | grep -v '^#'; }

printf 'template\n' > daily/TEMPLATE.md; c "init"

d 2026-09-20-a-1.md
got="$(run)"
[ "$got" = "daily/2026-09-20-a-1.md" ] && pass "no watermark yet: every daily is new" || fail "no watermark yet: every daily is new" "[$got]"

# Compiler branch: run commit + archive move, then merged into main with --no-ff.
g checkout -q -b compiler/2026-09-22
printf 'card\n' > card.md; c "compiler: 2026-09-22 run"
g mv daily/2026-09-20-a-1.md daily/archive/2026-09/2026-09-20-a-1.md; c "compiler: 2026-09-22 archive dailies"
g checkout -q main
d 2026-09-23-b-2.md
d 2026-09-24-c-3.md
tick; g merge -q --no-ff compiler/2026-09-22 -m "Merge pull request #20 from org/compiler/2026-09-22

compiler: 2026-09-22 run"
d 2026-09-26-d-4.md

got="$(run | tr '\n' ' ')"
[ "$got" = "daily/2026-09-23-b-2.md daily/2026-09-24-c-3.md daily/2026-09-26-d-4.md " ] \
  && pass "'compiler:' in a merge commit BODY does not move the watermark" \
  || fail "'compiler:' in a merge commit BODY does not move the watermark" "[$got]"
case "$(run)" in *archive*) fail "archive moves are not new dailies" "listed" ;; *) pass "archive moves are not new dailies" ;; esac
case "$(run)" in *TEMPLATE*) fail "TEMPLATE.md is never listed" "listed" ;; *) pass "TEMPLATE.md is never listed" ;; esac
hdr="$(bash compiler/new-dailies.sh 2>/dev/null | grep '^# watermark')"
case "$hdr" in *"compiler: 2026-09-22 archive dailies"*) pass "header names the watermark commit" ;;
  *) fail "header names the watermark commit" "[$hdr]" ;; esac

# Undated "compiler:" subjects are not watermarks: a human commit and the
# compiler's own "merge main into the branch" commit (its tree carries uncompiled dailies).
d 2026-09-26-f-6.md
printf 'fix\n' > script.txt; c "compiler: report failures in the nightly run"
g checkout -q -b compiler/old
tick; g merge -q --no-ff main -m "compiler: merge main into branch (2026-09-26 run input)"
g checkout -q main; g merge -q --ff-only compiler/old; g branch -q -D compiler/old
case "$(run | tr '\n' ' ')" in *"2026-09-26-f-6.md"*) pass "undated 'compiler:' commits do not move the watermark" ;;
  *) fail "undated 'compiler:' commits do not move the watermark" "[$(run | tr '\n' ' ')]" ;; esac

# An open (unmerged) compiler PR: its branch commits are watermarks too.
g push -q origin main 2>/dev/null
g checkout -q -b compiler/2026-09-27
printf 'card2\n' > card2.md; c "compiler: 2026-09-27 run"
g push -q origin compiler/2026-09-27 2>/dev/null
g checkout -q main
g branch -q -D compiler/2026-09-27
g fetch -q origin
d 2026-09-27-e-5.md
got="$(run | tr '\n' ' ')"
[ "$got" = "daily/2026-09-27-e-5.md " ] \
  && pass "a run on an open compiler PR branch advances the watermark" \
  || fail "a run on an open compiler PR branch advances the watermark" "[$got]"

# Test input directory: every file (no watermark).
mkdir -p tests/fx; printf 'x\n' > tests/fx/f1.md; printf 'x\n' > tests/fx/f2.md; c "fixture"
got="$(run tests/fx | tr '\n' ' ')"
[ "$got" = "tests/fx/f1.md tests/fx/f2.md " ] && pass "test input directory lists every file" || fail "test input directory lists every file" "[$got]"

cd /; rm -rf "$T"
echo
[ "$fails" -eq 0 ] && { echo "ALL PASSED"; exit 0; }
echo "$fails failed"; exit 1
