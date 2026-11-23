# COMPILER — from dailies to permanent knowledge

This file is a **procedure**, not a guideline: hand it to an agent and it is
followed literally. No step says "use your judgement"; every ambiguity ends
with **STOP and write it in the PR note**.

**Trigger:** (1) nightly — `compiler/nightly.sh` from cron or launchd; (2) on
request, when someone says "compile the brain".

**Input directory:** `daily/` by default. A test run may name another directory
(e.g. `tests/compiler-fixture/`). A test run's PR carries fixture content and
is **never merged**: record the evidence, close the PR, delete the branch.

## Surfaces

| Surface | What lives there | Who may change it |
|---|---|---|
| `daily/` | append-only session summaries | anyone, directly on the default branch |
| `projects/<id>.md` | cards: fields `id`, `family`, `status`, `aliases`; sections `Owns`, `Depends on`, `Known traps`, `Open debts`, `Archive` | compiler PR; appending under `Known traps`/`Archive` may auto-merge, anything else (fields, other sections, deleted lines, a new card) waits for a human |
| `projects/INDEX.md` | **projection** of card fields: `\| id \| family \| status \| aliases \|` | regenerated, never hand-edited |
| `incidents/`, `runbooks/` | new-knowledge cards | compiler PR, auto-merge allowed |
| `policies/candidates/<id>.md`, `policies/CANDIDATES.md` | descriptive policy queue + its generated table | compiler PR, auto-merge allowed |
| `queue/candidates.md` | backlog: candidates the size gate carried over to the next run | compiler PR, auto-merge allowed |
| `locked/` | architecture and contract decisions (`locked/decisions.md`: `\| ID \| **title** \|` rows or `## ID — title` headings — the summarizer lists these, and only a proposal to change one of them is a `locked-change`), the brain's identity | **humans only**, never the compiler |
| `hooks/`, `compiler/`, `skills/` | prescriptive artifacts | humans only |

## Steps

1. **List new dailies:** `bash compiler/new-dailies.sh [input-dir]` — every
   line not starting with `#` is this run's input; do not derive the list
   yourself. The watermark is the newest commit whose **subject** starts with
   `compiler: YYYY-MM-DD` (on the default branch and on open `origin/compiler/*`
   branches). Do **not** use `git log --grep`: it also matches merge-commit
   bodies, which carry the PR title, and moves the watermark past dailies that
   were never compiled. Then look at the queue: `python3 compiler/queue_candidates.py --summary`
   (backlog mode — candidates earlier runs could not fit, `queue/candidates.md`).
   No new dailies **and** an empty queue: say "nothing to compile" and STOP. A
   non-empty queue alone is enough to run (to drain it).
2. **Collect candidates:** first the blocks in `queue/candidates.md` (carried over —
   not re-summarized, taken as they are, their ADDED dates kept), then
   `bash compiler/summarize.sh <file>` for each new daily → candidate blocks:
   `CANDIDATE: card-feed|new-card|alias|locked-change|policy-candidate` /
   `TARGET: <card id | proposed new id | policy id>` / `BODY: <one paragraph>`.
   The script appends a `SOURCE:` line.
   **Enum tolerance:** an OBVIOUS misspelling of the candidate type
   (`card-feeds`→`card-feed`, `new card`→`new-card`) is normalized to the
   nearest valid type; record the mapping in the PR note. If a type maps to no
   valid type unambiguously, skip that daily and write "not compiled: <file>" —
   no guessing.
3. **Apply the candidates** on a new branch `compiler/<YYYY-MM-DD>`. Queued blocks
   go FIRST; delete every applied queued block from `queue/candidates.md` in the
   same commit. Same rules as for new candidates:
   - `card-feed` → append BODY to the target card's `Known traps` (only a trap
     that CAN RECUR) or `Archive`. **Cards are fed, never rewritten:** existing
     fields are never deleted or reworded.
   - `new-card` → a new file under `incidents/` or `runbooks/`, following that
     directory's schema.
   - `alias` → add to the target card's `aliases` field (the INDEX is
     refreshed in step 4).
   - `locked-change` → **do not touch the file.** Add "human decision needed:
     <summary>" to the PR description.
   - `policy-candidate` → only the policy queue. If
     `policies/candidates/<TARGET>.md` EXISTS: `seen` +1 and a new line under
     `evidence` (fed, not rewritten); never change its `status` (triage is a
     human's). Otherwise create it (`# <TARGET>`, `status: candidate`,
     `seen: 1`, evidence = the SOURCE daily). If that source daily is already
     in its evidence, do not increment (idempotent: a re-run must not inflate).
     **Never write a skill or hook file** from a candidate.
   - TARGET does not resolve (not in the INDEX; policy ids are queue ids, not
     card ids): apply nothing, write "unresolved: <target>".
4. **Regenerate projections:** rebuild the INDEX rows of every changed card
   from the card's own fields (row order is preserved). If any
   `policies/candidates/` file changed, run `python3 compiler/candidates.py`.
5. **Size gate — backlog mode:** if the branch diff exceeds 300 lines or 10
   files, apply the most valuable candidates (queued ones > new-card >
   policy-candidate > card-feed > alias; among queued ones of equal rank, the
   oldest ADDED first) and **do not drop the rest**: write each of them in full
   (`CANDIDATE` / `TARGET` / `BODY` / `SOURCE` / `ADDED: <today>`; a queued block
   that still does not fit KEEPS its ADDED) to `queue/candidates.md` in the same
   PR. The queue file and the projections (`projects/INDEX.md`,
   `policies/CANDIDATES.md`) do not count toward the gate. Then
   `python3 compiler/queue_candidates.py --check` must pass. PR note:
   "queued: N · applied from queue: M · left in queue: K". Why: the watermark
   moves past this run's dailies; a dropped candidate is never scanned again.
6. **Scan:** `bash hooks/scan-secrets.sh <every changed file>` — on a finding,
   NO push: the run STOPS and the finding is reported (fail-closed; never mask
   a value and continue).
7. **Archive dailies:** move dailies older than 7 days that a previous run
   already processed to `daily/archive/YYYY-MM/` with `git mv`, in the same
   PR. Never touch a daily inside the 7-day window.
8. **Branch and PR:**
   - An open PR whose title starts with `compiler:`? Then do not open a new
     branch — commit to that PR's branch and update its description.
     Otherwise push the branch and open a PR.
   - Title `compiler: <YYYY-MM-DD> run`, label `compiler`, base = the default branch.
   - The run commit's subject is `compiler: <YYYY-MM-DD> run` and **must start
     with the date** — the watermark (step 1) only recognises that form.
     Helper commits (e.g. merging the default branch into the PR branch) must
     **not** start with a date: `compiler: merge main into branch (…)`.
   - PR body = provenance: for every applied change
     `<file/card> ← <candidate type> ← <source daily>`; then everything not
     applied (locked-change / unresolved / not compiled / queued) with the reason.
   - **Input accounting (mandatory):** every input daily from step 1 appears in
     the PR body at least once, by its **full file name** — as the source of an
     applied change, or in one of the lists "queued", "no candidates", "not
     compiled". End the body with `Input accounting: N dailies = applied A +
     queued Q + no candidates E + not compiled F`. If the numbers do not add up,
     do NOT open the PR — process the missing dailies first. Why: in the
     reference brain's first backlog run 2 of 73 dailies appeared in no list at
     all; the watermark moved past them and nobody would have noticed.
9. **Merge decision:** `compiler/merge_gate.py` decides, and CI enforces it: the
   `brain-merge-gate` check runs the copy of the gate from the BASE branch, so a
   PR cannot loosen its own gate. Wait for the checks (`gh pr checks <n> --watch`).
   - Merge only a PR you can identify as this run's: its head branch is `compiler/<YYYY-MM-DD>`
     and its title starts with `compiler: `. The gate passes any other PR as "not a
     compiler PR", so a green check on a misnamed PR proves nothing — leave it to a human.
   - The `brain-merge-gate` check ran and is green AND every other check is green:
     merge (`gh pr merge <n> --merge --delete-branch`) and note "auto-merged".
     Green means: only new-knowledge surfaces (`incidents/`, `runbooks/`, `daily/`,
     `queue/`, `policies/candidates/`, `projects/INDEX.md`, `policies/CANDIDATES.md`)
     plus lines appended under a card's `Known traps` or `Archive`.
   - The gate is red, any other check is red, or the gate check did not run at all
     (missing, skipped, still pending after the watch): do not merge — leave the PR
     to a human. You may run `python3 compiler/merge_gate.py --base origin/<default
     branch>` locally to say why in the PR body.
10. **Stale branches:** `git fetch -p`; delete local `compiler/*` branches that
    are merged; delete merged remote `compiler/*` branches the host did not
    remove.

## Never

- Touch `locked/` (not even a PR that does).
- Delete or rewrite a card field — only feed it.
- Mask a scanner finding and continue.
- Open more than one compiler PR per run.
- Drop a candidate at the size gate without writing it to the queue.
- Write a skill or hook file from a policy candidate, or change a candidate's `status`.
- Start a non-run commit's subject with `compiler: <date>`.
