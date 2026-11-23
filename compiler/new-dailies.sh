#!/usr/bin/env bash
# The compiler's watermark — lists the dailies the next compiler run must process.
# Usage: new-dailies.sh [input-dir]   (default: daily)
# stdout: info lines start with '# '; every other line is one file path.
#
# Watermark = the newest commit whose SUBJECT starts with 'compiler: YYYY-MM-DD'
# (the run-commit format), searched on HEAD and on open compiler PR branches
# (origin/compiler/*). Not watermarks:
#   - merge commit BODIES: GitHub puts the PR title ("compiler: <date> run")
#     into the body, and `git log --grep` would match it;
#   - undated 'compiler:' subjects: human commits touching compiler/ and the
#     compiler's own "merge main into the branch" commits — their trees carry
#     dailies that were never compiled.
# New daily = a file under the top-level daily/ that is in HEAD but NOT in the
# watermark commit's tree (a tree comparison, not dates: a daily pushed late
# is still caught). Archive moves and TEMPLATE.md are excluded.
set -u
cd "$(dirname "$0")/.." || exit 1

dir="${1:-daily}"; dir="${dir%/}"
if [ "$dir" != "daily" ]; then
  echo "# test input directory: $dir — no watermark, every file"
  find "$dir" -maxdepth 1 -name '*.md' ! -name TEMPLATE.md | sort
  exit 0
fi

top_level_dailies() { grep -E '^daily/[^/]+\.md$' | grep -v '^daily/TEMPLATE\.md$' | sort; }

# shellcheck disable=SC2046 — the ref list is split into words on purpose
mark="$(git log --format='%H%x09%cI%x09%s' HEAD $(git for-each-ref --format='%(refname)' refs/remotes/origin/compiler/ 2>/dev/null) 2>/dev/null \
  | awk -F'\t' '$3 ~ /^compiler: [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ {print; exit}')"

if [ -z "$mark" ]; then
  echo "# no watermark (no compiler run commit yet) — every daily is new"
  git ls-files -- daily | top_level_dailies
  exit 0
fi

sha="${mark%%$'\t'*}"; rest="${mark#*$'\t'}"
echo "# watermark: ${sha:0:7} ${rest%%$'\t'*} ${rest#*$'\t'}"
git diff --name-only --no-renames --diff-filter=A "$sha" HEAD -- daily | top_level_dailies
