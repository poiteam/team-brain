# team-brain

A shared, git-backed memory for a team's AI coding sessions. Every Claude Code
session in your repos starts with what the team already knows — recent work,
open incidents, known traps — and ends by writing down what it learned. A nightly
compiler turns those notes into reviewed cards through pull requests. It is plain
Markdown in a private repo you own; hooks and CI enforce the habits so nobody has
to remember them.

Built and run in production at Poilabs.

## Use this template — do not fork

Click **Use this template → Create a new repository** and make the new repo
**private**. Do not fork: GitHub keeps a fork of a public repo public, and your
brain will fill up with your team's systems, customers and incidents.

## Quickstart

On each team member's machine, in a clone of your new private repo:

```bash
bash install.sh --name Atlas --org "Acme"    # skeleton, Claude Code hooks, pre-push scan
bash install.sh doctor                       # every line should say OK
```

On Windows, from PowerShell (it checks for Git Bash and Python 3, then runs the same installer):

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1 -Name Atlas -Org "Acme"
```

Commit what `init` created, push, and open a Claude Code session in the brain
repo: ask "who are you?". Then pick **one** machine to run the nightly compiler —
see [docs/kit/runner.md](docs/kit/runner.md).

## Updating

```bash
bash install.sh update      # latest release; --version vX.Y.Z to pin one
```

`update` replaces only the kit's own files (listed in `kit.manifest`), shows what
it will change and asks before writing. Your cards, dailies, `locked/`,
`brain.conf` and this README are never touched. It does not commit: review the
diff and commit it yourself.

## Documentation

- [Getting started](docs/kit/getting-started.md) — set up the brain for a team
- [Daily flow](docs/kit/daily-flow.md) — what happens in a session, at night, in a PR
- [Runner](docs/kit/runner.md) — the nightly compiler machine
- [Content contracts](docs/kit/contracts.md) — the formats the kit reads
- [Reference](docs/kit/reference.md) — every file, hook and rule in the kit

Problems: run `bash install.sh doctor` and include its output in the issue.

## License

MIT — see [LICENSE](LICENSE). Contributions: [CONTRIBUTING.md](CONTRIBUTING.md).
