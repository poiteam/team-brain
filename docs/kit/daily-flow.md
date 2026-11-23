# Daily flow

## In a session

1. **Start.** The SessionStart hook prints the brain's context: identity, open and
   watching incidents, compiler health, the routing index and the latest dailies.
   You do nothing; it is in the session before your first message.
2. **Work.** The `brain-routing` skill maps what you ask about to a card in
   `projects/INDEX.md` and opens that card only when the match is clear. When it is
   not, it says which card it assumed (reading) or stops and asks (writing).
3. **End.** If today's daily for this session does not exist, the Stop hook
   blocks the session from closing and asks for one: `daily/<date>-<user>-<session>.md`
   from `daily/TEMPLATE.md`. The session writes it, runs `hooks/scan-secrets.sh`
   on it, commits and pushes. The push itself is scanned again by the pre-push hook.

Dailies are summaries, never raw transcripts. An existing daily is not edited;
a second topic in the same session gets its own file.

## At night

The runner machine runs `compiler/nightly.sh`, which has Claude follow
`compiler/COMPILER.md`:

1. find the dailies no run has processed yet;
2. summarise each into candidates (a card feed, a new incident, a runbook, an
   alias, a policy candidate);
3. apply them on a branch `compiler/<date>` — cards are fed, never rewritten;
   `locked/` is never touched;
4. open one pull request per run, with an account of every input daily.

## The pull request

The `brain-merge-gate` check decides whether the compiler may merge alone:

- **Merges itself** when it only touches new-knowledge surfaces (`incidents/`,
  `runbooks/`, `daily/`, `queue/`, policy candidates, `projects/INDEX.md`) or
  appends under a card's `Known traps` / `Archive`, and every check is green.
- **Waits for a human** when it changes a card's fields or other sections,
  deletes a line, opens a new card, or touches anything else.

The gate runs the copy of `compiler/merge_gate.py` from the base branch, so a
pull request cannot loosen its own gate.

## Rules the hooks and CI enforce

| Rule | Enforced by |
|---|---|
| Every session leaves a daily | Stop hook |
| No secret reaches the remote | `hooks/scan-secrets.sh` before commit, pre-push hook, `brain-secret-scan` |
| Permanent knowledge changes only through a compiler PR | review + `brain-merge-gate` |
| The compiler never changes `locked/` | `brain-locked-guard` |
| Generated tables match their sources | `brain-checks` |

## When something goes wrong

- **A session closed without a daily** (crash, power loss): write a catch-up
  summary in the next session, with the real date in the file name and
  "(catch-up)" in the body.
- **Scripts that call `claude` themselves** (the compiler does) set
  `BRAIN_HOOKS_OFF=1` first, so the nested run is not asked for a daily.
- **Anything else:** `bash install.sh doctor`.
