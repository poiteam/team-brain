#!/usr/bin/env bash
# Schedule the nightly compiler (compiler/nightly.sh) on THIS machine — one machine
# per team is the runner. Run it as `bash install.sh runner [--remove|--status]`.
#
#   macOS  ~/Library/LaunchAgents/com.team-brain.<slug>.nightly.plist + launchctl
#   Linux  one crontab line tagged "# team-brain:<slug>"
# <slug> = first 8 hex of sha256(brain path): two brains on one machine never collide.
# Time: NIGHTLY_AT=HH:MM in brain.conf (default 03:30).
# Test seams: RUNNER_OS=darwin|linux, LAUNCHD_DIR, LAUNCHCTL, CRONTAB.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
. "$ROOT/hooks/common.sh"

OS="${RUNNER_OS:-$(uname -s | tr '[:upper:]' '[:lower:]')}"
case "$OS" in
  darwin|linux) ;;
  mingw*|msys*|cygwin*) echo "runner: Windows is not a runner platform in this version — run the nightly compiler on a macOS or Linux machine (docs/kit/runner.md)" >&2; exit 1 ;;
  *) echo "runner: unsupported OS '$OS'" >&2; exit 1 ;;
esac
LAUNCHD_DIR="${LAUNCHD_DIR:-$HOME/Library/LaunchAgents}"
LAUNCHCTL="${LAUNCHCTL:-launchctl}"
CRONTAB="${CRONTAB:-crontab}"
SCRIPT="$BRAIN/compiler/nightly.sh"
PY="$(pick_python)" || { echo "runner: no Python 3 found" >&2; exit 1; }
SLUG="$("$PY" -c 'import hashlib,sys; print(hashlib.sha256(sys.argv[1].encode()).hexdigest()[:8])' "$BRAIN")"
LABEL="com.team-brain.$SLUG.nightly"
PLIST="$LAUNCHD_DIR/$LABEL.plist"
TAG="# team-brain:$SLUG"

nightly_at() { # → "H M" or error
  local at h m
  at="$(conf NIGHTLY_AT 03:30)"
  case "$at" in [0-9][0-9]:[0-9][0-9]) ;; *) echo "runner: NIGHTLY_AT must be HH:MM (got '$at')" >&2; return 1 ;; esac
  h=$((10#${at%:*})); m=$((10#${at#*:}))
  [ "$h" -le 23 ] && [ "$m" -le 59 ] || { echo "runner: NIGHTLY_AT out of range (got '$at')" >&2; return 1; }
  printf '%s %s' "$h" "$m"
}

cron_without_ours() { "$CRONTAB" -l 2>/dev/null | grep -vF "$TAG" || true; }

runner_installed() {
  case "$OS" in
    darwin) [ -f "$PLIST" ] ;;
    linux)  "$CRONTAB" -l 2>/dev/null | grep -qF "$TAG" ;;
  esac
}

runner_install() {
  local hm h m q cur
  hm="$(nightly_at)" || return 1
  h="${hm% *}"; m="${hm#* }"
  case "$OS" in
    darwin)
      mkdir -p "$LAUNCHD_DIR"
      [ -f "$PLIST" ] && "$LAUNCHCTL" bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1
      # plistlib writes the XML: the path is escaped properly whatever it contains
      "$PY" - "$PLIST" "$LABEL" "$SCRIPT" "$h" "$m" <<'PY' || return 1
import plistlib, sys
path, label, script, h, m = sys.argv[1:]
with open(path, "wb") as f:
    plistlib.dump({"Label": label, "ProgramArguments": ["/bin/bash", script],
                   "StartCalendarInterval": {"Hour": int(h), "Minute": int(m)}}, f)
PY
      "$LAUNCHCTL" bootstrap "gui/$(id -u)" "$PLIST" || { echo "runner: launchctl bootstrap failed" >&2; return 1; }
      echo "  ✓ nightly run scheduled at $(printf '%02d:%02d' "$h" "$m") (launchd: $LABEL)" ;;
    linux)
      # single-quote the path for the shell; escape ' for it and % for cron (% = newline)
      q="$(printf '%s' "$SCRIPT" | sed -e "s/'/'\\\\''/g" -e 's/%/\\%/g')"
      cur="$(cron_without_ours)"   # read fully BEFORE writing: never stream crontab -l into crontab -
      { [ -n "$cur" ] && printf '%s\n' "$cur"; printf "%s %s * * * /bin/bash '%s' %s\n" "$m" "$h" "$q" "$TAG"; } | "$CRONTAB" - \
        || { echo "runner: could not write the crontab" >&2; return 1; }
      echo "  ✓ nightly run scheduled at $(printf '%02d:%02d' "$h" "$m") (crontab, $TAG)" ;;
  esac
  echo "  log: $BRAIN/.compiler.log — check it with 'bash install.sh doctor --runner'"
}

runner_remove() {
  local cur
  case "$OS" in
    darwin)
      [ -f "$PLIST" ] || { echo "  = not scheduled"; return 0; }
      "$LAUNCHCTL" bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1
      rm -f "$PLIST" && echo "  ✓ removed $LABEL" ;;
    linux)
      cur="$(cron_without_ours)"
      { [ -n "$cur" ] && printf '%s\n' "$cur"; } | "$CRONTAB" - && echo "  ✓ removed the crontab line ($TAG)" ;;
  esac
}

# sourced → only define the functions
[ "${BASH_SOURCE[0]}" = "$0" ] || return 0
case "${1:-}" in
  "")       runner_install ;;
  --remove) runner_remove ;;
  --status) if runner_installed; then echo "scheduled"; else echo "not scheduled"; exit 1; fi ;;
  *) echo "usage: bash install.sh runner [--remove|--status]" >&2; exit 2 ;;
esac
