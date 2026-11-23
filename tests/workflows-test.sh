#!/usr/bin/env bash
# Tests for .github/ — the workflows a team's brain repo runs, and the kit's own CI.
# Run: bash tests/workflows-test.sh   → exit 0 = all passed.
#
# "Use this template" copies .github/ into every team's private repo. So:
#   brain-*.yml  run in the TEAM repo (guard: not in the kit repo) — cheap, ubuntu only;
#   kit-ci.yml   runs ONLY in the kit repo (3-OS matrix would burn the team's minutes).
# The merge gate must run the BASE branch's copy, or a PR could loosen its own gate.
# The kit repo's name comes from kit/UPSTREAM — this test does not spell it.
set -u
. "$(dirname "$0")/lib.sh"

W="$KIT/.github/workflows"
SLUG="$(sed -n '1s|^https://github.com/||p' "$KIT/kit/UPSTREAM")"
[ -n "$SLUG" ] && pass "slug read from kit/UPSTREAM" || fail "slug read from kit/UPSTREAM" "empty"

for f in brain-merge-gate brain-locked-guard brain-secret-scan brain-checks kit-ci; do
  [ -f "$W/$f.yml" ] && pass "$f.yml exists" || fail "$f.yml exists" "missing"
done
[ -f "$KIT/.github/ISSUE_TEMPLATE/bug.yml" ] && grep -q 'install.sh doctor' "$KIT/.github/ISSUE_TEMPLATE/bug.yml" \
  && pass "issue template asks for doctor output" || fail "issue template asks for doctor output" "missing"

unpinned="$(grep -hE '^\s*-?\s*uses:' "$W"/*.yml | grep -vE '@[0-9a-f]{40}( |$)')"
[ -z "$unpinned" ] && pass "every action is pinned to a commit SHA" || fail "every action is pinned to a commit SHA" "$unpinned"

for f in "$W"/brain-*.yml; do
  n="$(basename "$f")"
  grep -qF "github.repository != '$SLUG'" "$f" && pass "$n: skipped in the kit repo" || fail "$n: skipped in the kit repo" "no guard"
  grep -q 'runs-on: ubuntu-latest' "$f" && ! grep -q 'matrix' "$f" && pass "$n: ubuntu only" || fail "$n: ubuntu only" "other runner"
done
grep -qF "github.repository == '$SLUG'" "$W/kit-ci.yml" && pass "kit-ci: only in the kit repo" || fail "kit-ci: only in the kit repo" "no guard"
for os in ubuntu-latest macos-latest windows-latest; do
  grep -q "$os" "$W/kit-ci.yml" && pass "kit-ci matrix has $os" || fail "kit-ci matrix has $os" "missing"
done
grep -q 'tests/run-all.sh' "$W/kit-ci.yml" && grep -q 'kit/manifest.py check' "$W/kit-ci.yml" \
  && pass "kit-ci runs the suite and checks kit.manifest" || fail "kit-ci runs the suite and checks kit.manifest" "missing"

grep -qF 'git show "origin/$BASE_REF:compiler/merge_gate.py"' "$W/brain-merge-gate.yml" \
  && pass "merge gate runs the base branch's copy" || fail "merge gate runs the base branch's copy" "missing"
! grep -q 'python3 compiler/merge_gate.py' "$W/brain-merge-gate.yml" \
  && pass "merge gate never runs the PR's own copy" || fail "merge gate never runs the PR's own copy" "found"
grep -q 'compiler/\*' "$W/brain-merge-gate.yml" && grep -q '"compiler:"' "$W/brain-merge-gate.yml" \
  && pass "merge gate recognises compiler PRs by branch and title" || fail "merge gate recognises compiler PRs" "missing"
for f in brain-merge-gate brain-locked-guard; do
  # pull_request would run the PR's OWN copy of this workflow: a PR could rewrite its gate
  grep -q '^  pull_request_target:' "$W/$f.yml" && ! grep -q '^  pull_request:' "$W/$f.yml" \
    && pass "$f runs the base branch's workflow (pull_request_target)" || fail "$f: pull_request_target" "missing"
  # the PR's files never land in the workspace: only base is checked out, the PR is a fetched ref
  ! grep -q 'pull_request.head' "$W/$f.yml" && grep -q 'refs/pull/' "$W/$f.yml" && grep -q 'contents: read' "$W/$f.yml" \
    && pass "$f: PR fetched as a ref, never checked out; read-only token" || fail "$f: PR checkout hygiene" "PR head checked out or no read-only token"
done
grep -q 'locked/' "$W/brain-locked-guard.yml" && grep -q 'compiler/\*' "$W/brain-locked-guard.yml" \
  && pass "locked guard: compiler PRs may not touch locked/" || fail "locked guard" "missing"
grep -q 'hooks/scan-secrets.sh' "$W/brain-secret-scan.yml" && grep -q 'push:' "$W/brain-secret-scan.yml" \
  && pass "secret scan runs on push and PR" || fail "secret scan runs on push and PR" "missing"
grep -q 'candidates.py --check' "$W/brain-checks.yml" && grep -q 'queue_candidates.py --check' "$W/brain-checks.yml" \
  && pass "brain-checks: both projection checks" || fail "brain-checks: both projection checks" "missing"

for f in "$W"/*.yml "$KIT/.github/ISSUE_TEMPLATE"/*.yml; do
  n="${f#$KIT/}"
  if grep -q "$(printf '\t')" "$f"; then fail "$n: no tabs" "tab found"; else pass "$n: no tabs"; fi
done
for f in "$W"/*.yml; do
  n="$(basename "$f")"
  grep -q '^name:' "$f" && grep -q '^on:' "$f" && grep -q '^jobs:' "$f" && pass "$n: has name/on/jobs" || fail "$n: has name/on/jobs" "missing key"
done
if python3 -c 'import yaml' 2>/dev/null; then
  python3 -c 'import sys,yaml; [yaml.safe_load(open(f)) for f in sys.argv[1:]]' "$W"/*.yml "$KIT/.github/ISSUE_TEMPLATE"/*.yml \
    && pass "every YAML parses" || fail "every YAML parses" "parse error"
fi

finish
