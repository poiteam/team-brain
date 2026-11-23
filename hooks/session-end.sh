#!/usr/bin/env bash
# Stop hook (Claude Code / Codex) — the session does not end until today's daily
# summary exists: daily/<date>-<user>-<session8>.md. If it is missing, prints
# {"decision":"block","reason":…}, which sends the instructions back to the model.
#
# Never holds a session hostage: re-entry (stop_hook_active), unparseable input,
# no Python, or a cwd outside the brain → exit silently.
set -u

[ "${BRAIN_HOOKS_OFF:-0}" = "1" ] && exit 0   # nested runs (the compiler's own claude -p calls)

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
in_brain_dirs || exit 0

PY="$(pick_python || true)"
[ -n "$PY" ] || exit 0

BRANCH="$(conf DEFAULT_BRANCH main)"

# User in the file name: hooks/user.local.txt > $USER > $USERNAME, normalised
# (accents, case, spaces removed) so macOS NFD / Windows NFC names never clash.
if [ -f "$BRAIN/hooks/user.local.txt" ]; then who="$(tr -d '[:space:]' < "$BRAIN/hooks/user.local.txt")"
else who="${USER:-${USERNAME:-}}"; fi
who="$("$PY" -c 'import sys, re, unicodedata
s = unicodedata.normalize("NFKD", sys.argv[1].replace("ı", "i")).encode("ascii", "ignore").decode().lower()
print(re.sub(r"[^a-z0-9._-]", "", s))' "$who" 2>/dev/null || printf '%s' "$who")"
[ -n "$who" ] || who="user"

parsed="$(cat | "$PY" -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    print("parse-fail x"); sys.exit(0)
print(("1" if d.get("stop_hook_active") else "0") + " " + (d.get("session_id") or "session")[:8])
')"
active="${parsed%% *}"; sid="${parsed#* }"
[ "$active" = "0" ] || exit 0   # re-entry or unparseable input: let the session end

daily="$BRAIN/daily/$(date +%F)-$who-$sid.md"
[ -e "$daily" ] && exit 0

"$PY" - "$daily" "$BRAIN" "$BRANCH" <<'PY'
import json, sys
daily, brain, branch = sys.argv[1:4]
reason = (
    "The session is ending without a daily summary. Do this, then finish: "
    f"0) the brain repo must be on {branch} — if not, 'git -C {brain} switch {branch}' "
    "(dailies go straight to the default branch; on another branch they would leak into an open compiler PR). "
    f"1) write this session's summary to {daily} following {brain}/daily/TEMPLATE.md "
    "(a summary, never the raw transcript; drop empty sections). "
    f"2) bash {brain}/hooks/scan-secrets.sh <that file> — on a finding, remove the secret from the daily; never mask it and continue. "
    f"3) commit and push to {branch} (message: 'daily: <date> <topic>'). "
    "If nothing in this session touched the brain, a one-line 'no changes' summary is enough."
)
print(json.dumps({"decision": "block", "reason": reason}, ensure_ascii=False))
PY
exit 0
