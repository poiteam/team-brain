# Getting started

## What you are setting up

A private git repo that every Claude Code session of your team reads at start and
writes to at the end:

- **Session start** puts the brain's identity, open incidents, a routing index of
  your systems and the last days' session notes into the session — within a fixed
  byte budget.
- **Session end** does not let the session close until a short daily summary is
  written to `daily/`, scanned for secrets, committed and pushed.
- **At night** one machine runs the compiler: it reads new dailies and proposes
  permanent knowledge (cards, incidents, runbooks) in a single pull request.

## Prerequisites

Every member: git, Python 3, the Claude Code CLI (`claude`), and write access to
the brain repo. On Windows: Git for Windows (for Git Bash). The runner machine
also needs the GitHub CLI (`gh`) — see [runner.md](runner.md).

## 1. Create the repo (one person, once)

1. On the kit's GitHub page: **Use this template → Create a new repository**,
   **private**. Never fork (a fork of a public repo stays public).
2. Clone it and run `bash install.sh --name <Name> --org "<Team>"`.
   - `--name` is what the brain calls itself; `--org` is your team or company.
   - `init` copies the skeleton from `template/` and never overwrites a file.
3. Edit `locked/identity.md` — who the brain is and how it talks — and
   `locked/decisions.md` — the few decisions it must never erode.
4. Add your first cards: one row per system in `projects/INDEX.md`, and a
   `projects/<id>.md` card for the ones that matter most (see
   [contracts.md](contracts.md) for the format).
5. Commit and push.

## 2. Join (every member)

```bash
git clone <your private brain repo>
cd <brain>
bash install.sh            # hooks + pre-push scan; brain.conf already exists
bash install.sh doctor
```

Windows: `powershell -ExecutionPolicy Bypass -File install.ps1`.

`install.sh hooks` adds two entries to `~/.claude/settings.json` (or
`$CLAUDE_CONFIG_DIR`) and keeps every other hook and setting; it backs the file
up first and refuses to touch one that is not valid JSON.

## 3. Tell the brain where to speak

The hooks run only when a session starts inside the brain repo or one of the
directories listed in `hooks/brain-dirs.txt` (shared, one path per line, `~`
allowed). Paths that differ per person go in `hooks/brain-dirs.local.txt`, which
is not committed. Everywhere else the hooks stay silent and nothing flows into
the brain.

## 4. Check it

- `bash install.sh doctor` — every line `OK`.
- Open a Claude Code session in one of those directories and ask "who are you?".
- End the session: it asks for a daily summary before it closes.

## 5. Schedule the compiler

On one machine only: [runner.md](runner.md).
