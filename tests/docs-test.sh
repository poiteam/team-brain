#!/usr/bin/env bash
# Tests for the kit's documentation — the facts in it that code depends on.
# Run: bash tests/docs-test.sh   → exit 0 = all passed.
#
# Docs drift silently; these checks pin what a reader acts on: the template-not-fork
# warning, links that resolve, the runner's permission warning, and the versions
# printed in docs matching kit/VERSION and kit/CONTRACT.
# README/LICENSE/CHANGELOG are the kit repo's front page: a team rewrites them after
# "Use this template", so those checks are skipped inside an initialised brain (.brain-kit/).
set -u
. "$(dirname "$0")/lib.sh"

links_ok() { # <md file> → prints the relative links that do not resolve
  local f="$1" dir l
  dir="$(dirname "$f")"
  grep -oE '\]\([^)#]+' "$f" | sed 's/^](//' | grep -vE '^(https?:|mailto:)' | while IFS= read -r l; do
    [ -e "$dir/$l" ] || echo "$l"
  done
}

for f in getting-started daily-flow runner contracts reference; do
  [ -f "$KIT/docs/kit/$f.md" ] && pass "docs/kit/$f.md exists" || fail "docs/kit/$f.md exists" "missing"
done
for f in "$KIT"/docs/kit/*.md; do
  bad="$(links_ok "$f")"
  [ -z "$bad" ] && pass "${f#$KIT/}: links resolve" || fail "${f#$KIT/}: links resolve" "$bad"
done
grep -q -- '--dangerously-skip-permissions' "$KIT/docs/kit/runner.md" \
  && pass "runner.md warns about --dangerously-skip-permissions" || fail "runner.md permission warning" "missing"
grep -q 'Full Disk Access' "$KIT/docs/kit/runner.md" \
  && pass "runner.md: macOS privacy (~/Documents needs Full Disk Access for launchd)" || fail "runner.md: macOS TCC note" "missing"
grep -q "Contract version: $(tr -d '[:space:]' < "$KIT/kit/CONTRACT")" "$KIT/docs/kit/contracts.md" \
  && pass "contracts.md version = kit/CONTRACT" || fail "contracts.md version = kit/CONTRACT" "drift"
grep -q '^CONTRACT_VERSION=' "$KIT/brain.conf.example" && pass "brain.conf.example has CONTRACT_VERSION" || fail "brain.conf.example has CONTRACT_VERSION" "missing"

if [ -d "$KIT/.brain-kit" ]; then
  echo "SKIP README/LICENSE/CHANGELOG checks — inside an initialised brain"
else
  grep -q 'Use this template' "$KIT/README.md" && grep -qi 'not fork' "$KIT/README.md" \
    && pass "README: use the template, do not fork" || fail "README: template-not-fork warning" "missing"
  bad="$(links_ok "$KIT/README.md")"
  [ -z "$bad" ] && pass "README: links resolve" || fail "README: links resolve" "$bad"
  [ "$(head -1 "$KIT/LICENSE")" = "MIT License" ] && pass "LICENSE is MIT" || fail "LICENSE is MIT" "$(head -1 "$KIT/LICENSE")"
  first="$(grep -m1 '^## ' "$KIT/CHANGELOG.md" | sed 's/^## //; s/ .*//')"
  [ "$first" = "$(tr -d '[:space:]' < "$KIT/kit/VERSION")" ] && pass "CHANGELOG top entry = kit/VERSION" || fail "CHANGELOG top entry = kit/VERSION" "$first"
  grep -q 'eol=lf' "$KIT/.gitattributes" && pass ".gitattributes keeps scripts LF" || fail ".gitattributes keeps scripts LF" "missing"
fi

finish
