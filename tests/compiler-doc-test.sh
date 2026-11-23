#!/usr/bin/env bash
# Contract between compiler/COMPILER.md (the procedure an agent follows) and the
# scripts it names. Docs drift silently — in the reference brain a skill kept
# describing its index as "22 rows, ~1 KB" long after it had grown to 60+ rows
# and 13 KB. These checks make drift a red test.
# Run: bash tests/compiler-doc-test.sh   → exit 0 = all passed.
set -u
. "$(dirname "$0")/lib.sh"

DOC="${COMPILER_DOC:-$KIT/compiler/COMPILER.md}"

# 1) Every kit path the procedure names exists — anywhere in the text, including
#    inside commands (`bash compiler/summarize.sh <file>`), not only bare `path`s.
missing=""
for p in $(grep -oE '(compiler|hooks)/[A-Za-z0-9_.-]+\.(sh|py|md)' "$DOC" | sort -u); do
  [ -e "$KIT/$p" ] || missing="$missing $p"
done
[ -z "$missing" ] && pass "every script the procedure names exists" || fail "every script the procedure names exists" "missing:$missing"

# 2) The candidate types in the procedure = the types summarize.sh asks the model for.
doc_types="$(grep -oE 'CANDIDATE: [a-z|-]+' "$DOC" | head -1 | sed 's/CANDIDATE: //' | tr '|' '\n' | sort | tr '\n' ' ')"
sh_types="$(grep -oE 'CANDIDATE: [a-z|-]+' "$KIT/compiler/summarize.sh" | head -1 | sed 's/CANDIDATE: //' | tr '|' '\n' | sort | tr '\n' ' ')"
[ -n "$doc_types" ] && [ "$doc_types" = "$sh_types" ] && pass "candidate types match summarize.sh ($doc_types)" \
  || fail "candidate types match summarize.sh" "doc=[$doc_types] script=[$sh_types]"

# 3) Every candidate type has an application rule in step 3.
for t in $doc_types; do
  grep -qE "^   - \`$t\` →" "$DOC" && pass "step 3 has a rule for $t" || fail "step 3 has a rule for $t" "missing"
done

# 4) The run-commit format the procedure prescribes is the one new-dailies.sh recognises.
grep -q 'compiler: <YYYY-MM-DD> run' "$DOC" && grep -q '\^compiler: \[0-9\]' "$KIT/compiler/new-dailies.sh" \
  && pass "run-commit format matches the watermark pattern" || fail "run-commit format matches the watermark pattern" "drift"

# 6) Every input daily is accounted for in the PR (reference brain, first backlog run:
#    2 of 73 dailies appeared in no list at all and fell behind the watermark unseen).
grep -q 'Input accounting' "$DOC" && grep -q 'full file name' "$DOC" \
  && pass "procedure requires input accounting by full file name" || fail "procedure requires input accounting by full file name" "missing"

# 7) Merge decision = the brain-merge-gate check (compiler/merge_gate.py, run from the
#    base branch). The old rule "card bodies → a human" held every card feed for review.
grep -q 'compiler/merge_gate.py' "$DOC" && grep -q 'brain-merge-gate' "$DOC" \
  && pass "step 9 names merge_gate.py and the brain-merge-gate check" || fail "step 9 names the merge gate" "missing"
grep -q 'did not run' "$DOC" && pass "step 9: a gate check that did not run means a human" || fail "step 9: gate that did not run" "missing"
! grep -q 'merged by a human |' "$DOC" && pass "card feeds are no longer human-only in the surfaces table" || fail "surfaces table still says cards are human-only" "stale"

grep -q 'head branch is `compiler/<YYYY-MM-DD>`' "$DOC" \
  && pass "step 9: merge only a PR positively identified as this run's" || fail "step 9: positive compiler-PR identity" "missing"

# 5) The nightly runner points the agent at this procedure.
grep -q 'compiler/COMPILER.md' "$KIT/compiler/nightly.sh" && pass "nightly.sh names compiler/COMPILER.md" || fail "nightly.sh names compiler/COMPILER.md" "missing"

finish
