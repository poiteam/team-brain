# Contributing

Thanks for helping. Two things to know first:

- **This repository is a mirror.** The kit is developed inside the brain Poilabs
  runs in production, and every release here is built from that source. A pull
  request here is not merged directly — a maintainer carries the change into the
  source, and it ships in the next release with credit in the CHANGELOG. Direct
  commits to this repo would be overwritten by the next release.
- **Bugs:** open an issue with the output of `bash install.sh doctor` (and
  `--runner` if the nightly compiler is involved). Leave out anything from your own
  brain — card contents, dailies, names, URLs.

Changes should come with a test in `tests/` that fails without them;
`bash tests/run-all.sh` must stay green on macOS, Linux and Windows (Git Bash).
Code style: bash that runs on macOS's bash 3.2, Python 3.8+ standard library only.

Maintained by Poilabs (github.com/poiteam).
