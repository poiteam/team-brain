#!/usr/bin/env bash
# Tests for hooks/session-end.sh — the Stop hook that refuses to end a session
# until today's daily summary exists.
# Run: bash tests/session-end-test.sh   → exit 0 = all passed.
#
# Contract (Claude Code / Codex Stop hook): stdin is JSON with session_id and
# stop_hook_active; printing {"decision":"block","reason":…} sends the reason
# back to the model instead of ending the session. It must never hold a session
# hostage: re-entry (stop_hook_active), unparseable input, no Python, or a cwd
# outside the brain all exit silently.
set -u
. "$(dirname "$0")/lib.sh"

stop() { # $1 = brain, $2 = stdin json, [$3 = cwd], [$4 = user] → hook stdout
  ( cd "${3:-$1}" && USER="${4:-zeynep}" bash "$1/hooks/session-end.sh" <<<"$2" )
}
today="$(date +%F)"

H="$(new_home)"; B="$H/brain"; make_brain "$B"
out="$(stop "$B" '{"session_id":"abcd1234-ffff-0000","stop_hook_active":false}')"
case "$out" in *'"decision": "block"'*) pass "no daily yet → block" ;; *) fail "no daily yet → block" "[$out]" ;; esac
case "$out" in *"daily/$today-zeynep-abcd1234.md"*) pass "reason names daily/<date>-<user>-<session8>.md" ;;
  *) fail "reason names daily/<date>-<user>-<session8>.md" "[$out]" ;; esac
case "$out" in *"hooks/scan-secrets.sh"*"main"*) pass "reason says: scan, commit to the default branch" ;;
  *) fail "reason says: scan, commit to the default branch" "[$out]" ;; esac
printf '%s' "$out" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null \
  && pass "output is valid JSON" || fail "output is valid JSON" "[$out]"

printf 'summary\n' > "$B/daily/$today-zeynep-abcd1234.md"
[ -z "$(stop "$B" '{"session_id":"abcd1234-ffff-0000"}')" ] && pass "daily exists → silent" || fail "daily exists → silent" "blocked"

[ -z "$(stop "$B" '{"session_id":"eeee5555","stop_hook_active":true}')" ] && pass "stop_hook_active → silent (no loop)" || fail "stop_hook_active → silent (no loop)" "blocked"
[ -z "$(stop "$B" 'not json')" ] && pass "unparseable input → silent (never hostage)" || fail "unparseable input → silent" "blocked"

mkdir -p "$H/elsewhere"
[ -z "$(stop "$B" '{"session_id":"ffff6666"}' "$H/elsewhere")" ] && pass "outside the brain's directories → silent" || fail "outside the brain's directories → silent" "blocked"

[ -z "$( cd "$B" && BRAIN_HOOKS_OFF=1 bash hooks/session-end.sh <<<'{"session_id":"ffff6666"}')" ] \
  && pass "BRAIN_HOOKS_OFF=1 → silent" || fail "BRAIN_HOOKS_OFF=1 → silent" "blocked"

# User names are normalised for file names (accents, case, spaces): no NFC/NFD clashes.
out="$(stop "$B" '{"session_id":"99998888"}' "$B" "Zeynep Çelik")"
case "$out" in *"$today-zeynepcelik-99998888.md"*) pass "user name normalised (Zeynep Çelik → zeynepcelik)" ;;
  *) fail "user name normalised (Zeynep Çelik → zeynepcelik)" "[$out]" ;; esac
# hooks/user.local.txt overrides $USER.
printf 'mert\n' > "$B/hooks/user.local.txt"
case "$(stop "$B" '{"session_id":"77776666"}')" in *"$today-mert-77776666.md"*) pass "hooks/user.local.txt overrides \$USER" ;;
  *) fail "hooks/user.local.txt overrides \$USER" "not used" ;; esac

# DEFAULT_BRANCH from brain.conf.
printf 'NAME=Atlas\nORG=Acme\nDEFAULT_BRANCH=trunk\n' > "$B/brain.conf"
case "$(stop "$B" '{"session_id":"55554444"}')" in *"trunk"*) pass "DEFAULT_BRANCH from brain.conf" ;; *) fail "DEFAULT_BRANCH from brain.conf" "not used" ;; esac
rm -rf "$H"

finish
