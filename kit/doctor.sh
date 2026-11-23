#!/usr/bin/env bash
# Why does this brain not work on this machine? One line per check:
#   OK   <check>[ — detail]      FAIL <check> — <how to fix>      SKIP <check> — <why>
# Exit 0 when nothing FAILs. Run it as `bash install.sh doctor [--runner]`;
# paste its output into any issue you open.
#
#   --runner   also check what the nightly compiler needs on this machine:
#              gh login, a GitHub remote, a logged-in claude, the schedule.
# BRAIN_OFFLINE=1 skips the one network check (latest kit version).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
. "$ROOT/hooks/common.sh"
RUNNER=0
for a in "$@"; do
  case "$a" in --runner) RUNNER=1 ;; *) echo "unknown argument: $a" >&2; exit 2 ;; esac
done

fails=0
ok()   { printf 'OK   %s\n' "$*"; }
bad()  { printf 'FAIL %s — %s\n' "$1" "$2"; fails=$((fails+1)); }
skip() { printf 'SKIP %s — %s\n' "$1" "$2"; }

# --- tools
command -v git >/dev/null 2>&1 && ok git || bad git "install git (Windows: Git for Windows, which also brings Git Bash)"
PY="$(pick_python || true)"
[ -n "$PY" ] && ok "python3 — $("$PY" --version 2>&1)" || bad python3 "install Python 3 (on Windows the Microsoft Store 'python' stub does not count)"
command -v claude >/dev/null 2>&1 && ok claude || bad claude "install Claude Code (the 'claude' CLI) and make sure it is on PATH"

# --- this brain's configuration
name="$(conf NAME '')"
if [ -f "$BRAIN/brain.conf" ] && [ -n "$name" ]; then ok "brain.conf — $name"
else bad brain.conf "run 'bash install.sh init' (brain.conf missing or NAME empty)"; fi

kit_contract="$(tr -d '[:space:]' < "$ROOT/kit/CONTRACT" 2>/dev/null)"
have="$(conf CONTRACT_VERSION '')"
if [ -z "$have" ]; then
  bad contract "brain.conf has no CONTRACT_VERSION — add 'CONTRACT_VERSION=$kit_contract' (docs/kit/contracts.md)"
elif [ "$have" = "$kit_contract" ]; then ok "contract — v$have"
elif [ "$have" -lt "$kit_contract" ] 2>/dev/null; then
  bad contract "your content follows contract v$have, the kit expects v$kit_contract: apply the steps in CHANGELOG.md, then set CONTRACT_VERSION=$kit_contract"
else
  bad contract "your content follows contract v$have, newer than this kit (v$kit_contract): run 'bash install.sh update'"
fi

# --- Claude Code hook registration
settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
if [ -z "$PY" ]; then skip settings.json "needs Python 3"
elif [ ! -f "$settings" ]; then bad settings.json "$settings does not exist — run 'bash install.sh hooks'"
else
  why="$("$PY" - "$settings" "$BRAIN" <<'PY'
import json, os, sys
path, brain = sys.argv[1], sys.argv[2]
try:
    d = json.load(open(path, encoding="utf-8"))
except ValueError as e:
    print(f"{path} is not valid JSON ({e}) — fix it, then run 'bash install.sh hooks'"); sys.exit(0)
for event, script in (("SessionStart", "session-start.sh"), ("Stop", "session-end.sh")):
    target = f"{brain}/hooks/{script}"
    cmds = [h.get("command") or "" for e in d.get("hooks", {}).get(event, []) for h in e.get("hooks", [])]
    if not any(target in c for c in cmds):
        print(f"no {event} hook for this brain ({target}) — run 'bash install.sh hooks'"); sys.exit(0)
    if not os.path.isfile(target):
        print(f"{target} is missing — run 'bash install.sh update' or restore it from git"); sys.exit(0)
PY
)"; prc=$?
  # fail closed: a crashed check is a FAIL, never an empty (= OK) answer
  if [ "$prc" -ne 0 ]; then bad settings.json "could not check $settings (python exited $prc)"
  elif [ -z "$why" ]; then ok settings.json
  else bad settings.json "$why"; fi
fi

[ "$(git -C "$BRAIN" config core.hooksPath 2>/dev/null)" = "hooks" ] && ok pre-push \
  || bad pre-push "the pre-push secret scan is not wired — run 'bash install.sh hooks'"

budget="$(conf START_BUDGET 8000)"
out="$(cd "$BRAIN" && BRAIN_OFFLINE=1 bash hooks/session-start.sh </dev/null 2>&1)"
size="$(printf '%s' "$out" | LC_ALL=C wc -c | tr -d ' ')"
case "$out" in
  "=== $name — "*)
    if [ "$size" -le "$budget" ]; then ok "session-start — $size/$budget bytes"
    else bad session-start "printed $size bytes, over START_BUDGET=$budget"; fi ;;
  *) bad session-start "did not print the brain's header; first line: $(printf '%s' "$out" | head -1)" ;;
esac

# --- kit version (the only network check)
installed="$(tr -d '[:space:]' < "$BRAIN/.brain-kit/version" 2>/dev/null)"
if [ "${BRAIN_OFFLINE:-0}" = "1" ]; then skip "kit version" "offline (BRAIN_OFFLINE=1)"
elif [ -z "$installed" ]; then
  if [ -f "$BRAIN/kit.manifest" ]; then bad "kit version" "no .brain-kit/version — run 'bash install.sh init'"
  else skip "kit version" "development checkout (no kit.manifest)"; fi
else
  upstream="${KIT_UPSTREAM:-$(head -1 "$BRAIN/kit/UPSTREAM" 2>/dev/null)}"
  latest="$(GIT_TERMINAL_PROMPT=0 git -c http.lowSpeedLimit=1 -c http.lowSpeedTime=10 ls-remote --tags --refs "$upstream" 'v*' 2>/dev/null \
    | sed -n 's|.*refs/tags/\(v[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)$|\1|p' | sort -t. -k1.2,1n -k2,2n -k3,3n | tail -1)"
  if [ -z "$latest" ]; then skip "kit version" "v$installed installed; upstream unreachable ($upstream)"
  elif [ "$latest" = "v$installed" ]; then ok "kit version — v$installed (latest)"
  else ok "kit version — v$installed installed, $latest available: bash install.sh update"; fi
fi

# --- runner: what the nightly compiler needs
host_os="${RUNNER_OS:-$(uname -s | tr '[:upper:]' '[:lower:]')}"
case "$host_os" in
  mingw*|msys*|cygwin*)
    if [ "$RUNNER" -eq 1 ]; then
      bad runner "Windows is not a runner platform in this version — run the nightly compiler on a macOS or Linux machine (docs/kit/runner.md)"
      RUNNER=0
    fi ;;
esac
if [ "$RUNNER" -eq 1 ]; then
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then ok gh
  else bad gh "install the GitHub CLI and run 'gh auth login' (the compiler opens and merges PRs)"; fi
  url="$(git -C "$BRAIN" remote get-url origin 2>/dev/null)"
  [ -n "$url" ] && ok "remote — $url" || bad remote "the brain has no 'origin' remote — push it to a private GitHub repo"
  if [ -z "$PY" ] || ! command -v claude >/dev/null 2>&1; then
    bad "claude login" "needs python3 and claude (see above)"
  elif BRAIN_HOOKS_OFF=1 "$PY" - <<'PY'
import os, subprocess, sys
env = dict(os.environ); env.pop("ANTHROPIC_API_KEY", None)   # the run uses the subscription
try:
    r = subprocess.run(["claude", "-p", "reply with OK"], capture_output=True, text=True, timeout=60, env=env)
except (OSError, subprocess.TimeoutExpired):
    sys.exit(1)
sys.exit(0 if r.returncode == 0 and "OK" in r.stdout else 1)
PY
  then ok "claude login"
  else bad "claude login" "'claude -p' did not answer — run 'claude' once on this machine and log in"; fi
  if [ -f "$ROOT/kit/runner.sh" ]; then
    if bash "$ROOT/kit/runner.sh" --status >/dev/null 2>&1; then ok schedule
    else bad schedule "the nightly run is not scheduled — run 'bash install.sh runner'"; fi
  else
    skip schedule "kit/runner.sh not installed"
  fi
fi

exit $(( fails > 0 ))
