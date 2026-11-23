#!/usr/bin/env bash
# Tests for compiler/summarize.sh — the prompt it gives the cheap model, verified
# with a stub `claude` that records its arguments and environment (no network,
# no subscription).
# Run: bash tests/summarize-test.sh   → exit 0 = all passed.
#
# Why the policy-id list: without it the model invents a new policy id for the
# same class on every run; in the reference brain 93 of 109 policy candidates
# ended at seen=1, which made "most seen first" triage meaningless.
set -u
. "$(dirname "$0")/lib.sh"

H="$(new_home)"; B="$H/brain"; make_brain "$B"
mkdir -p "$B/policies/candidates" "$H/bin"
for id in secret-in-diff no-tls-softening test-discovery; do printf '# %s\n- policy: rule-text-%s\n' "$id" "$id" > "$B/policies/candidates/$id.md"; done
cat > "$B/locked/decisions.md" <<'EOF'
| id | decision | why |
|---|---|---|
| D1 | **Dailies go straight to main** | append-only |

## D2 — Cards change only via compiler PRs
EOF
printf -- '---\nauthor: t\n---\n## Traps\n- a secret leaked again\n' > "$H/daily.md"

cat > "$H/bin/claude" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do last="\$a"; done
printf '%s' "\$last" > "$H/prompt.txt"
printf 'key=%s hooks_off=%s model=%s\n' "\${ANTHROPIC_API_KEY-UNSET}" "\${BRAIN_HOOKS_OFF-UNSET}" "\$*" > "$H/env.txt"
printf 'CANDIDATE: policy-candidate\nTARGET: secret-in-diff\nBODY: x\n'
EOF
chmod +x "$H/bin/claude"

out="$(PATH="$H/bin:$PATH" ANTHROPIC_API_KEY=sk-test bash "$B/compiler/summarize.sh" "$H/daily.md")"; rc=$?
[ "$rc" -eq 0 ] && pass "runs with a stub claude" || fail "runs with a stub claude" "exit $rc"
prompt="$(cat "$H/prompt.txt" 2>/dev/null)"; env="$(cat "$H/env.txt" 2>/dev/null)"

case "$prompt" in *"EXISTING POLICY IDS"*) pass "prompt has the existing policy ids section" ;; *) fail "prompt has the existing policy ids section" "missing" ;; esac
missing=""; for id in secret-in-diff no-tls-softening test-discovery; do case "$prompt" in *"$id"*) ;; *) missing="$missing $id" ;; esac; done
[ -z "$missing" ] && pass "every existing policy id is in the prompt" || fail "every existing policy id is in the prompt" "missing:$missing"
case "$prompt" in *"VALID CARD IDS"*"billing-api"*"search-worker"*) pass "card ids come from projects/INDEX.md" ;; *) fail "card ids come from projects/INDEX.md" "missing" ;; esac
case "$prompt" in *"index-stale-2026-09"*) pass "incident ids are valid targets too" ;; *) fail "incident ids are valid targets too" "missing" ;; esac
case "$prompt" in *"--- DAILY ---"*"a secret leaked again"*) pass "the daily itself is in the prompt" ;; *) fail "the daily itself is in the prompt" "missing" ;; esac
# From the reference brain's first real backlog run: most "human decision needed"
# items were ordinary design decisions; 14 of 24 policy candidates opened new ids;
# 5 had no evidence in the daily; 8 blocks wrote "type|target".
case "$prompt" in *"rule-text-secret-in-diff"*"rule-text-test-discovery"*) pass "policy ids come WITH their rule text (match the class by meaning)" ;; *) fail "policy ids come WITH their rule text" "missing" ;; esac
case "$prompt" in *"LOCKED DECISIONS"*"D1: Dailies go straight to main"*"D2: Cards change only via compiler PRs"*) pass "locked decisions listed (table rows and headings)" ;; *) fail "locked decisions listed" "missing" ;; esac
case "$prompt" in *"locked-change ONLY"*) pass "locked-change narrowed to the listed decisions" ;; *) fail "locked-change narrowed to the listed decisions" "missing" ;; esac
case "$prompt" in *"ALWAYS a locked-change"*) fail "the old broad rule is gone" "still there" ;; *) pass "the old broad rule ('ALWAYS a locked-change') is gone" ;; esac
case "$prompt" in *"WRONG: CANDIDATE: card-feed|"*) pass "format: no 'type|target' on the CANDIDATE line" ;; *) fail "format: no 'type|target' on the CANDIDATE line" "missing" ;; esac
case "$prompt" in *"concrete evidence"*) pass "policy candidates require concrete evidence" ;; *) fail "policy candidates require concrete evidence" "missing" ;; esac

case "$out" in *"SOURCE: daily.md"*) pass "SOURCE line is appended" ;; *) fail "SOURCE line is appended" "[$out]" ;; esac

# A metered API key in the environment must never reach the CLI: it would bill
# the run per token instead of using the subscription.
case "$env" in *"key=UNSET"*) pass "ANTHROPIC_API_KEY is unset for the CLI" ;; *) fail "ANTHROPIC_API_KEY is unset for the CLI" "[$env]" ;; esac
case "$env" in *"hooks_off=1"*) pass "BRAIN_HOOKS_OFF=1 for the nested run" ;; *) fail "BRAIN_HOOKS_OFF=1 for the nested run" "[$env]" ;; esac
case "$env" in *"--model haiku"*) pass "uses the cheap model" ;; *) fail "uses the cheap model" "[$env]" ;; esac

rm -f "$B/policies/candidates/"*.md
PATH="$H/bin:$PATH" bash "$B/compiler/summarize.sh" "$H/daily.md" >/dev/null
case "$(cat "$H/prompt.txt")" in *"EXISTING POLICY IDS"*"(none yet)"*) pass "empty queue says '(none yet)'" ;; *) fail "empty queue says '(none yet)'" "missing" ;; esac

# The CLI failing is an error, never an empty candidate list.
printf '#!/usr/bin/env bash\necho "You'"'"'ve hit your weekly limit"; exit 1\n' > "$H/bin/claude"
if PATH="$H/bin:$PATH" bash "$B/compiler/summarize.sh" "$H/daily.md" >/dev/null 2>&1; then fail "CLI failure is a non-zero exit" "exit 0"
else pass "CLI failure is a non-zero exit"; fi

rm -rf "$H"
finish
