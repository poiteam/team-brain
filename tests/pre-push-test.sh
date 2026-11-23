#!/usr/bin/env bash
# Tests for hooks/pre-push — real pushes into a local bare remote.
# Run: bash tests/pre-push-test.sh   → exit 0 = all passed.
#
# The hook scans the COMMITTED blobs being pushed (not the working tree: what
# leaves the machine is the blob). The secret-shaped fixture is assembled at
# runtime so the kit ships no secret-looking file.
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
mkdir -p hooks
cp "$KIT/hooks/scan-secrets.sh" "$KIT/hooks/pre-push" hooks/
chmod +x hooks/pre-push
g config core.hooksPath hooks

printf 'hello\n' > notes.md; g add -A; g commit -q -m "clean"
g push -q origin main 2>/dev/null && pass "clean first push is accepted" || fail "clean first push is accepted" "rejected"

g checkout -q -b feature
printf 'aws: AK''IA''ABCDEFGHIJKLMNOP\n' > leak.md; g add -A; g commit -q -m "oops"
if g push -q origin feature 2>/dev/null; then fail "new branch with a secret is rejected" "accepted"
else pass "new branch with a secret is rejected"; fi

# Fixing the working tree is NOT enough: the secret is still in a pushed commit.
printf 'fixed\n' > leak.md
if g push -q origin feature 2>/dev/null; then fail "working-tree fix alone does not unblock" "accepted"
else pass "working-tree fix alone does not unblock"; fi

g checkout -q main; g branch -q -D feature
g checkout -q -b feature2
printf 'more docs\n' > more.md; g add -A; g commit -q -m "docs"
g push -q origin feature2 2>/dev/null && pass "clean new branch is accepted" || fail "clean new branch is accepted" "rejected"

g checkout -q main
printf 'x\n' >> notes.md; g add -A; g commit -q -m "update"
g push -q origin main 2>/dev/null && pass "clean update of an existing branch is accepted" || fail "clean update of an existing branch is accepted" "rejected"

g push -q origin --delete feature2 2>/dev/null && pass "branch deletion is accepted" || fail "branch deletion is accepted" "rejected"

cd /; rm -rf "$T"
echo
[ "$fails" -eq 0 ] && { echo "ALL PASSED"; exit 0; }
echo "$fails failed"; exit 1
