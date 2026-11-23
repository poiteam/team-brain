#!/usr/bin/env bash
# Contract tests for template/ — the skeleton install.sh copies into a new brain.
# Run: bash tests/template-test.sh   → exit 0 = all passed.
#
# The templates are read by other parts of the kit; if a name drifts, those
# parts go quiet instead of failing (e.g. the summarizer is told "the 'Traps'
# section is the strongest source" — rename the section and it silently finds
# fewer candidates).
set -u
. "$(dirname "$0")/lib.sh"

T="$KIT/template"
for f in locked/identity.md locked/decisions.md projects/INDEX.md daily/TEMPLATE.md policies/CANDIDATES.md queue/candidates.md gitignore; do
  [ -f "$T/$f" ] && pass "template/$f exists" || fail "template/$f exists" "missing"
done

# Daily template sections = the ones summarize.sh points the model at.
for s in "Decisions" "Traps" "Card candidate"; do
  grep -q "'$s'" "$KIT/compiler/summarize.sh" || { fail "summarize.sh still names '$s'" "drift in summarize.sh"; continue; }
  grep -qE "^## $s\$" "$T/daily/TEMPLATE.md" && pass "daily template has '## $s' (named by summarize.sh)" || fail "daily template has '## $s'" "missing"
done
# Front matter keys the hooks read.
for k in author related; do
  grep -qE "^$k:" "$T/daily/TEMPLATE.md" && pass "daily template front matter has '$k:'" || fail "daily template front matter has '$k:'" "missing"
done

# INDEX template: the row format session-start parses, and an Incidents section.
grep -qF '| id | family | status | aliases |' "$T/projects/INDEX.md" && pass "INDEX template has the row header" || fail "INDEX template has the row header" "missing"
grep -qE '(open|watching|resolved)' "$T/projects/INDEX.md" && pass "INDEX template documents incident statuses" || fail "INDEX template documents incident statuses" "missing"

# The empty queue template passes the queue checker (a new brain starts valid).
H0="$(new_home)"; mkdir -p "$H0/queue"; cp "$T/queue/candidates.md" "$H0/queue/"
python3 "$KIT/compiler/queue_candidates.py" --root "$H0" --check >/dev/null 2>&1 && pass "empty queue template passes queue_candidates.py --check" || fail "empty queue template passes queue_candidates.py --check" "invalid"
rm -rf "$H0"

# Locked decisions template uses a format summarize.sh lists (table row "| ID | **title** |"
# or heading "## ID — title") — otherwise locked-change detection silently has nothing to match.
grep -qE '^\| [A-Z]+[0-9]+ \| \*\*[^*]+\*\*' "$T/locked/decisions.md" && grep -qF '| [A-Z]+[0-9]+ \| \*\*' "$KIT/compiler/summarize.sh" \
  && pass "locked/decisions.md rows are in the format summarize.sh lists" || fail "locked/decisions.md rows are in the format summarize.sh lists" "drift"

# CANDIDATES template carries the markers candidates.py rewrites between.
grep -qF '<!-- CANDIDATES:BEGIN -->' "$T/policies/CANDIDATES.md" && grep -qF '<!-- CANDIDATES:END -->' "$T/policies/CANDIDATES.md" \
  && pass "CANDIDATES template has the generator markers" || fail "CANDIDATES template has the generator markers" "missing"

# A brain built from the template alone makes session-start print its sections.
H="$(new_home)"; B="$H/brain"; mkdir -p "$B"
cp -R "$KIT/hooks" "$KIT/compiler" "$B/"; (cd "$T" && tar cf - --exclude=gitignore .) | (cd "$B" && tar xf -)
printf 'NAME=Atlas\nORG=Acme\n' > "$B/brain.conf"
out="$(cd "$B" && BRAIN_OFFLINE=1 bash hooks/session-start.sh </dev/null)"
case "$out" in *"=== Atlas — Acme"*"--- Identity"*"--- Routing"*"Rule: at session end"*) pass "session-start works on a template-only brain" ;;
  *) fail "session-start works on a template-only brain" "$(printf '%s' "$out" | head -5)" ;; esac
rm -rf "$H"

finish
