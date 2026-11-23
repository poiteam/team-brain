# Changelog

Versions follow semver. A change to a content contract (docs/kit/contracts.md)
is a major version and lists the manual steps to convert your content.

## 0.1.1 — 2026-11-23

- Tests no longer copy the kit's `.git` into their fixture brains: inside a git
  checkout with an `origin` remote (this repository's own CI) `doctor-test`
  found that remote and failed. No change to the kit's behaviour.
- The release pipeline runs the kit's tests inside such a checkout.

## 0.1.0 — 2026-11-23

First public release, extracted from the brain Poilabs runs in production.
Tested with Claude Code 2.x on macOS, Linux and Windows (Git Bash).

- Session hooks: start context within a byte budget; end requires a daily.
- Fail-closed secret scan before commit, on push, and in CI.
- Nightly compiler with backlog queue, policy candidates and input accounting.
- Merge gate: compiler PRs that only add new knowledge or feed `Known traps` /
  `Archive` merge themselves; anything else waits for a human.
- `install.sh`: `init`, `hooks`, `update` (manifest-based), `doctor`, `runner`;
  `install.ps1` for Windows.
- Content contract version 1.
