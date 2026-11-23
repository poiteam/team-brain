# Reference

Every file the kit ships, what it does, and the rules it is built on. Files marked
**engine** are listed in `kit.manifest` and replaced by `bash install.sh update`;
everything else in your repo is yours.

## Commands

| Command | What it does |
|---|---|
| `bash install.sh` | `init`, then `hooks` |
| `bash install.sh init [--name N --org O]` | copies the skeleton from `template/` (never overwrites); writes `brain.conf` from `brain.conf.example`; adds local files to `.gitignore`; records the installed kit version in `.brain-kit/` |
| `bash install.sh hooks` | registers the SessionStart/Stop hooks in `settings.json` (idempotent, keeps everything else, backs the file up, refuses invalid JSON, removes this brain's entries whose script is gone); sets `core.hooksPath` for the pre-push scan; smoke-tests session start |
| `bash install.sh update [--version vX.Y.Z] [--force] [--yes]` | fetches a release tag from `kit/UPSTREAM`, previews and applies the engine changes, then runs the new `init`, `hooks` and `doctor`; never commits; stops on engine files you edited unless `--force` (which backs them up to `.brain-kit/backup/`) |
| `bash install.sh doctor [--runner]` | one line per check: `OK`, `FAIL — <fix>` or `SKIP — <why>` |
| `bash install.sh runner [--remove\|--status]` | schedules the nightly compiler (macOS launchd, Linux cron) |
| `install.ps1 [-CheckOnly] [-Name N] [-Org O]` | Windows: checks Git Bash and Python 3, then runs `install.sh` |

## Engine files

| Path | Purpose |
|---|---|
| `hooks/session-start.sh` | SessionStart hook. Header → identity → open incidents (compiler health first) → routing summary → recent dailies → open compiler PR → rule line, never more than `START_BUDGET` bytes; a section that does not fit is cut and the cut is announced. |
| `hooks/session-end.sh` | Stop hook. Blocks the end of the session until `daily/<date>-<user>-<session8>.md` exists; never blocks on re-entry, bad input, missing Python or outside the brain. |
| `hooks/common.sh` | Shared: brain path, `brain.conf` reader (read, not sourced), directory allowlist, Python picker, Windows `HOME` fix. |
| `hooks/scan-secrets.sh` | Fail-closed secret scanner: anything it cannot vouch for (unreadable file, grep error) is a finding. |
| `hooks/pre-push` | Scans the **committed** blobs of every file in the pushed range — fixing the working tree does not unblock a push. |
| `compiler/COMPILER.md` | The compiler procedure an agent follows literally. |
| `compiler/summarize.sh` | One daily → candidate blocks, on the subscription with the cheap model (`ANTHROPIC_API_KEY` is unset on purpose). |
| `compiler/nightly.sh` | The nightly runner: finds `claude` (nvm, usual dirs, then your PATH), logs `FAILED (claude exit N): <reason>` on any failure or limit. |
| `compiler/new-dailies.sh` | The watermark: which dailies the next run must process. Only run commits (`compiler: YYYY-MM-DD …`) count. |
| `compiler/candidates.py`, `compiler/queue_candidates.py` | Policy-candidate table and the backlog queue; `--check` for CI. |
| `compiler/merge_gate.py` | May a compiler PR merge alone? Run from the base branch by `brain-merge-gate`. |
| `skills/brain-routing/SKILL.md` | Routes a request to the closed set of cards in `projects/INDEX.md`, with an asymmetric gate: state the assumption when reading, stop and ask when writing. |
| `kit/manifest.py`, `kit/update.py` | `kit.manifest` format and the update logic. |
| `kit/doctor.sh`, `kit/runner.sh` | `doctor` and `runner`. |
| `kit/VERSION`, `kit/CONTRACT`, `kit/UPSTREAM` | Kit version, content contract version, where updates come from. |
| `.github/workflows/brain-*.yml` | The team repo's checks: merge gate, locked guard, secret scan, projection checks. |
| `template/` | The skeleton `init` copies: identity, decisions, INDEX, daily template, policy queue, incident/runbook notes. |
| `docs/kit/` | These documents. |
| `tests/` | `bash tests/run-all.sh`. Secret-shaped fixtures are assembled at runtime — the kit ships no file that looks like a secret. |

## Brain layout the hooks expect

```
brain.conf                 locked/identity.md       projects/INDEX.md
daily/TEMPLATE.md          daily/<date>-<user>-<session8>.md
hooks/brain-dirs.txt       # optional: other repos where the brain should speak
hooks/brain-dirs.local.txt # optional, not committed: personal paths
hooks/user.local.txt       # optional, not committed: your name in daily file names
.brain-kit/                # installed kit version + manifest (committed)
```

`brain.conf` keys: `NAME`, `ORG`, `DEFAULT_BRANCH`, `START_BUDGET`,
`CONTRACT_VERSION`, optional `NIGHTLY_AT`. It is read, never sourced. The formats
of your content are in [contracts.md](contracts.md).

## Design rules

- **Enforced beats suggested.** In the reference brain, artifacts left to the
  model's discretion went unused, while hook- and CI-enforced ones ran every time.
- **Fail closed.** A scanner that cannot decide says "finding"; a nightly run that
  fails says `FAILED` in its log — never a quiet success.
- **Health comes from git, not logs.** The nightly log lives on one machine; the
  "compiler not running" line is derived from pending dailies, so every teammate
  sees it the next morning.
- **Projections are generated, never hand-edited.** Index tables are rebuilt from
  their source files and checked in CI.
- **The kit never touches your content.** `update` writes only paths in
  `kit.manifest` and refuses a manifest that names a team-owned path.
