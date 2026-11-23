#!/usr/bin/env bash
# The compiler's summarizing sub-step: one daily → candidate blocks (COMPILER.md step 2).
# Usage: summarize.sh <daily-file>  → stdout: CANDIDATE/TARGET/BODY blocks + a SOURCE line
#
# Runs the CLI on the SUBSCRIPTION with the cheap model. ANTHROPIC_API_KEY is
# unset on purpose: if it leaks in from the environment, the CLI bills per token
# instead — a nightly loop over many dailies turns that into a large bill fast.
set -u

f="${1:?usage: summarize.sh <daily-file>}"
[ -r "$f" ] || { echo "ERROR: cannot read $f" >&2; exit 1; }

unset ANTHROPIC_API_KEY
export BRAIN_HOOKS_OFF=1   # the session hooks must stay quiet inside this nested claude run

here="$(dirname "$0")"
# Valid targets (from the INDEX projection) — the model must not invent card ids.
ids="$(grep -oE '^\| [a-z0-9][a-z0-9-]* \|' "$here/../projects/INDEX.md" 2>/dev/null | awk '{print $2}' | grep -vx 'id' | sort -u | tr '\n' ' ')"
# Existing policy ids — the same class must reuse its id so the "seen" counter
# accumulates instead of fragmenting into one-off ids.
# id + RULE TEXT: with ids alone the model guesses the class from the name.
pids="$(for f in "$here/../policies/candidates"/*.md; do [ -e "$f" ] || continue
  printf -- '- %s: %s\n' "$(basename "$f" .md)" "$(sed -n 's/^- policy: *//p' "$f" | head -1 | cut -c1-160)"; done)"
[ -n "$pids" ] || pids="(none yet)"
# Locked decisions (locked/*.md): table rows "| ID | **title** |" and headings
# "## ID — title", plus the identity. locked-change means changing ONE OF THESE —
# not every design decision a daily records (that inflation dilutes locked/).
locked="$here/../locked"
decisions="$( { grep -hoE '^\| [A-Z]+[0-9]+ \| \*\*[^*]+\*\*' "$locked"/*.md 2>/dev/null | sed -E 's/^\| ([A-Z]+[0-9]+) \| \*\*([^*]+)\*\*/\1: \2/'
  grep -hoE '^## [A-Z]+[0-9]+ — .+' "$locked"/*.md 2>/dev/null | sed -E 's/^## ([A-Z]+[0-9]+) — /\1: /'
  [ -f "$locked/identity.md" ] && echo "identity (locked/identity.md): the brain's name, role, tone, limits"; } | sed 's/^/- /')"
[ -n "$decisions" ] || decisions="(none)"

out="$(claude -p --model haiku "Below is a session summary (a daily) from a team's shared brain. Your job: extract the CANDIDATES for promotion into permanent knowledge. For each candidate write EXACTLY these three lines (nothing else — no explanations, no code fences, plain text):
CANDIDATE: card-feed|new-card|alias|locked-change|policy-candidate
TARGET: <the related card id; for new-card a proposed short id; for policy-candidate one of the EXISTING POLICY IDS, or a new short kebab-case id if none fits>
FORMAT: the CANDIDATE line carries ONLY the type; the target goes on the TARGET line. RIGHT: 'CANDIDATE: card-feed' then 'TARGET: billing-api'. WRONG: CANDIDATE: card-feed|billing-api
BODY: <one paragraph, in the daily's language, faithful to the source — add no interpretation, invent nothing>

VALID CARD IDS (for card-feed and alias the TARGET MUST be from this list — never invent an id; if the knowledge fits none of these cards, propose a new-card or produce no candidate): $ids

EXISTING POLICY IDS (id: rule) — for policy-candidate, if the violation falls into the class of one of these rules the TARGET MUST be that id. Match the class by the RULE TEXT, not by the id's name; the same class is the same id even when the daily words it differently (e.g. a secret landing in a diff, a log, a cache, a transcript or a config file is ONE class). A new id ONLY if no rule covers the violation:
$pids

LOCKED DECISIONS (locked/ — only humans change these):
$decisions

Rules: the 'Card candidate' and 'Traps' sections are the strongest sources. Produce no candidate for routine work without lasting value. LOCKED-CHANGE: produce a locked-change ONLY when the daily proposes changing, loosening or removing one of the LOCKED DECISIONS listed above (by id or by content); never answer 'NO CANDIDATES' for such a proposal. Ordinary design or implementation decisions in the 'Decisions' section (how a script behaves, a file format, the order of a flow, a tool choice) are NOT locked-changes — if they have lasting value they are a card-feed for the related card, otherwise produce no candidate.
POLICY-CANDIDATE: the bar is HIGH — produce one only if (a) the daily ITSELF says the violation recurs ('again', 'once more', 'third time', 'same class', a reference to a known debt), OR (b) the class is security or data integrity (secret leak, TLS/SSL softening, cross-tenant leak, injection, weakening a test / a test that silently does not run). One-off tool quirks, process-improvement ideas and portability notes (sed/CLI/API version differences) are NOT policy candidates — they are card-feed (known traps) candidates. At most 2 policy candidates per daily; pick the strongest two. BODY MUST contain concrete evidence of the violation from the daily (what happened, where — file, command, number); if the daily has no sentence showing the violation (only a summary of work done), produce no policy candidate. In BODY write the violated rule + the evidence; IMPLY the suggested skill/hook but do NOT write it. Difference: locked-change protects an existing locked decision; policy-candidate proposes a new enforcement. If there really is no candidate, write only 'NO CANDIDATES'.

--- DAILY ---
$(cat "$f")"
)" || { echo "ERROR: claude CLI run failed" >&2; exit 1; }

printf '%s\n' "$out"
printf 'SOURCE: %s\n' "${f##*/}"
