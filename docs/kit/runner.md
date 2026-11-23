# Runner — the nightly compiler machine

Pick **one** machine per team, macOS or Linux, that is on at night. (Windows is
not supported as a runner in this version; Windows members are fine as
participants.)

## Set it up

```bash
gh auth login                    # the compiler opens and merges pull requests
claude                           # log in once, then exit
bash install.sh runner           # macOS: LaunchAgent · Linux: one crontab line
bash install.sh doctor --runner  # every line should say OK
```

**macOS:** a LaunchAgent cannot read `~/Documents`, `~/Desktop` or `~/Downloads`
(macOS privacy protection) — the run would fail with "Operation not permitted".
Keep the runner's brain checkout elsewhere (for example `~/brain`), or give
`/bin/bash` Full Disk Access in System Settings → Privacy & Security.

The run starts at 03:30 local time. Change it with `NIGHTLY_AT=HH:MM` in
`brain.conf` and run `bash install.sh runner` again. Remove it with
`bash install.sh runner --remove`.

Test a run by hand: `bash compiler/nightly.sh`, then read `.compiler.log`.

## What it costs

The compiler runs `claude -p` on your Claude subscription, not on an API key
(`ANTHROPIC_API_KEY` is unset for the run). It shares the subscription's limits
with your interactive sessions; a heavy week can exhaust them. A run that hits a
limit writes `FAILED (claude exit N): <reason>` to `.compiler.log` and exits
non-zero — the next run picks up the same dailies. Every teammate sees
"compiler — not running" at session start once the oldest unprocessed daily is
two days old.

## Security: what the run is allowed to do

The nightly run calls `claude -p --dangerously-skip-permissions`: nobody is there
at night to approve each command, so Claude runs git, gh and the compiler scripts
without asking. Treat the runner accordingly:

- run it under a dedicated OS user whose only checkout is the brain repo;
- give that user's `gh` login access to the brain repo only (a fine-grained token
  or a machine account), not to your organisation;
- keep no other credentials in that user's environment.

What limits the damage regardless: the run works in the brain repo, every change
it makes reaches the remote as a pull request, and the `brain-merge-gate`,
`brain-locked-guard` and `brain-secret-scan` checks run on it in CI.

## Logs and health

- `.compiler.log` in the brain root (not committed): one block per run, ending in
  `done (exit 0)` or `FAILED …`.
- `bash install.sh doctor --runner`: gh login, the `origin` remote, the claude
  login and the schedule.
