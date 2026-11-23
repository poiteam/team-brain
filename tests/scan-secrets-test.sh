#!/usr/bin/env bash
# Tests for hooks/scan-secrets.sh (fail-closed secret scan).
# Run: bash tests/scan-secrets-test.sh   → exit 0 = all passed.
#
# Fixtures are ASSEMBLED AT RUNTIME from fragments, so the kit ships no file
# that looks like a secret — otherwise the kit's own secret scan (and every
# downstream scanner) would have to carve out an exception for its tests.
set -u

KIT="$(cd "$(dirname "$0")/.." && pwd -P)"
SCAN="$KIT/hooks/scan-secrets.sh"
fails=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s — %s\n' "$1" "$2"; fails=$((fails+1)); }

T="$(mktemp -d)"
fx() { printf '%s\n' "$2" > "$T/$1"; }   # fx <name> <content>

fx url-userinfo.md    "db: postgres""://app_user:""hunter2""@db.internal:5432/app"
fx storage-key.md     "conn: DefaultEndpoints""Protocol=https;Account""Key=""$(printf 'A%.0s' $(seq 1 40))=="
fx private-key.md     "-----BEGIN ""RSA PRIVATE"" KEY-----"
fx aws-key.md         "aws: AK""IA""ABCDEFGHIJKLMNOP"
fx ftp-password.md    "FTP_""PASSWORD = ""s3cr3t-value"
fx api-key.md         "api_""key: ""'abcdefgh12345678'"
fx atlassian-token.md "token: ATAT""T3""$(printf 'x%.0s' $(seq 1 24))"
fx clean.md           "No secrets here: the word password alone, a key without a value."
fx localhost.md       "dev: postgres""://dev:dev""@localhost:5432/app"

for f in url-userinfo storage-key private-key aws-key ftp-password api-key atlassian-token; do
  if bash "$SCAN" "$T/$f.md" >/dev/null 2>&1; then fail "$f is a finding" "exit 0"; else pass "$f is a finding"; fi
done
bash "$SCAN" "$T/clean.md" >/dev/null 2>&1 && pass "plain words are not findings" || fail "plain words are not findings" "exit 1"
bash "$SCAN" "$T/localhost.md" >/dev/null 2>&1 && pass "local-host credentials are exempt (E1)" || fail "local-host credentials are exempt (E1)" "exit 1"
if bash "$SCAN" "$T/clean.md" "$T/aws-key.md" >/dev/null 2>&1; then fail "one finding fails the whole batch" "exit 0"
else pass "one finding fails the whole batch"; fi
if bash "$SCAN" "$T/does-not-exist.md" >/dev/null 2>&1; then fail "unreadable file is a finding (fail-closed)" "exit 0"
else pass "unreadable file is a finding (fail-closed)"; fi
bash "$SCAN" "$SCAN" >/dev/null 2>&1 && pass "the scanner does not match itself" || fail "the scanner does not match itself" "self-match"

rm -rf "$T"
echo
[ "$fails" -eq 0 ] && { echo "ALL PASSED"; exit 0; }
echo "$fails failed"; exit 1
