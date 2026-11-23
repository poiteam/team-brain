#!/usr/bin/env bash
# Shared by session-start.sh and session-end.sh. Sourced, never executed.
#
# brain.conf is READ, not sourced: plain KEY=value lines, so a config file can
# never execute code. Keys: NAME, ORG, DEFAULT_BRANCH, START_BUDGET.

# Windows (Git Bash, non-login shell): HOME may be empty → derive from USERPROFILE.
if [ -z "${HOME:-}" ] && [ -n "${USERPROFILE:-}" ]; then
  HOME="$(cygpath -u "$USERPROFILE" 2>/dev/null || printf '%s' "$USERPROFILE")"; export HOME
fi

# Windows: Python's console encoding is cp1252 there, and the kit prints ✓, →, —.
# Without this, a print crashes the script (install, update, the Stop hook's JSON).
export PYTHONIOENCODING=utf-8 PYTHONUTF8=1

# The brain is the repo these hooks live in (hooks/..), unless BRAIN_DIR says otherwise.
BRAIN="${BRAIN_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"

conf() { # conf KEY DEFAULT — last KEY=value line in brain.conf wins
  local v
  v="$(sed -n "s/^$1=//p" "$BRAIN/brain.conf" 2>/dev/null | tail -1)"
  v="${v%$'\r'}"   # Windows checkout with core.autocrlf: brain.conf may be CRLF
  printf '%s' "${v:-$2}"
}

# Is the current directory one where the brain should speak? Always the brain
# itself; plus every path in hooks/brain-dirs.txt and hooks/brain-dirs.local.txt
# (one per line, '~' allowed, '#' comments). Everyone's checkout layout differs,
# so the .local file is for personal paths and stays out of git.
in_brain_dirs() {
  local cwd p
  cwd="$(pwd -P)"
  case "$cwd" in "$BRAIN"|"$BRAIN"/*) return 0 ;; esac
  while IFS= read -r p; do
    case "$p" in ''|'#'*) continue ;; esac
    p="${p/#\~/$HOME}"
    case "$cwd" in "$p"|"$p"/*) return 0 ;; esac
  done < <(cat "$BRAIN/hooks/brain-dirs.txt" "$BRAIN/hooks/brain-dirs.local.txt" 2>/dev/null)
  return 1
}

# Python: trust the OUTPUT, not the name — on Windows 'python3' may be the
# Microsoft Store stub. The first candidate that prints "Python 3" wins.
pick_python() {
  local c p v
  for c in python3 python py; do
    p="$(command -v "$c" 2>/dev/null)" || continue
    v="$("$p" --version 2>&1 </dev/null)" || true
    case "$v" in "Python 3"*) printf '%s' "$p"; return 0 ;; esac
  done
  return 1
}
