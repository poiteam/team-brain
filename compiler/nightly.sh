#!/usr/bin/env bash
# Nightly compiler run — schedule it with cron or launchd (see README).
# Log: .compiler.log in the brain root (gitignore it). Manual run: bash compiler/nightly.sh
#
# Failure is reported, never swallowed: the claude CLI can exit 1 with its limit
# message on STDOUT; a limit line with exit 0 counts as a failure too. On failure
# the log says "FAILED (claude exit N): <reason>" and the script exits non-zero.
#
# Portable: the brain is this script's repo (compiler/..); PATH is built from the
# newest nvm node version that CONTAINS claude, then the usual install dirs, then
# the caller's own PATH (a Linux package or custom prefix). A node upgrade or a newer
# claude-less version must not turn the run into "command not found"). Cron and
# launchd hand out a narrow PATH.
. "$(dirname "$0")/../hooks/common.sh"
BRANCH="$(conf DEFAULT_BRANCH main)"
nvm_bin=""
for d in $(ls -d "$HOME"/.nvm/versions/node/*/bin 2>/dev/null | sort -rV); do
  [ -x "$d/claude" ] && { nvm_bin="$d"; break; }
done
export PATH="${nvm_bin:+$nvm_bin:}$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:${PATH:+$PATH:}/usr/bin:/bin"
LOG="$BRAIN/.compiler.log"
{
  echo "=== $(date '+%F %T') nightly run started ==="
  cd "$BRAIN" || { echo "ERROR: no repo"; exit 1; }
  if ! command -v claude >/dev/null 2>&1; then
    echo "=== $(date '+%F %T') FAILED (claude exit 127): claude not found (PATH=$PATH) ==="
    exit 127
  fi
  export BRAIN_HOOKS_OFF=1
  unset ANTHROPIC_API_KEY
  git pull --ff-only 2>&1
  out="$(mktemp)"
  claude -p --dangerously-skip-permissions "compile the brain: follow compiler/COMPILER.md exactly. Input directory: daily/. If there are no new dailies AND queue/candidates.md is empty, change nothing, print the single line 'nothing to compile' and stop; with queued candidates, run even without new dailies. If a compiler PR is already open, do not open a new one; update its branch." 2>&1 | tee "$out"
  rc=${PIPESTATUS[0]}
  # Only the CLI's own limit line ("You've hit your weekly/session limit · …");
  # "rate limit" as compiled CONTENT must not raise a false alarm.
  reason="$(grep -E "^You've hit your [a-z ]*limit" "$out" | head -1)"
  rm -f "$out"
  if [ "$rc" -ne 0 ] || [ -n "$reason" ]; then
    [ "$rc" -ne 0 ] || rc=1
    echo "=== $(date '+%F %T') FAILED (claude exit $rc): ${reason:-see above} — the watermark did not move; the next run retries the same dailies ==="
    exit "$rc"
  fi
  git fetch -p 2>&1
  for b in $(git branch --merged "$BRANCH" | grep "compiler/" | tr -d " "); do git branch -d "$b"; done
  for rb in $(git branch -r --merged "$BRANCH" | grep "origin/compiler/" | sed "s|.*origin/||"); do git push origin --delete "$rb" 2>&1; done
  echo "=== $(date '+%F %T') done (exit $rc) ==="
} >> "$LOG" 2>&1
