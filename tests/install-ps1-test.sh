#!/usr/bin/env bash
# Tests for install.ps1 — the Windows entry point. It finds Git Bash and a REAL
# Python 3 (the Microsoft Store 'python' stub prints no version), warns about a
# missing claude, then hands over to install.sh. It never logs in to GitHub or clones.
# Run: bash tests/install-ps1-test.sh   → exit 0 = all passed (SKIPs without pwsh).
# KIT_PYTHON_NAMES overrides the Python candidates (test seam).
set -u
. "$(dirname "$0")/lib.sh"

# README tells Windows users to run `powershell` (5.1): test with it where it exists
PWSH="$(command -v powershell || command -v pwsh || true)"
# 5.1 reads a BOM-less script as the ANSI code page: one non-ASCII byte can break parsing
nonascii="$(LC_ALL=C grep -n "$(printf '[\200-\377]')" "$KIT/install.ps1" | head -3)"
[ -z "$nonascii" ] && pass "install.ps1 is pure ASCII (Windows PowerShell 5.1 safe)" || fail "install.ps1 is pure ASCII" "$nonascii"
if [ -z "$PWSH" ]; then echo "SKIP install.ps1 tests — no pwsh on this machine"; finish; fi

ps1() { "$PWSH" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$@"; }

H="$(new_home)"; B="$H/brain"; mkdir -p "$B"
(cd "$KIT" && tar cf - --exclude='tests/__pycache__' --exclude='compiler/__pycache__' --exclude='kit/__pycache__' .) | (cd "$B" && tar xf -)
g -C "$B" init -q

out="$(HOME="$H" ps1 "$B/install.ps1" -CheckOnly 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && pass "-CheckOnly with git, bash and python → exit 0" || fail "-CheckOnly" "rc=$rc $out"
case "$out" in *"Git Bash"*) pass "-CheckOnly reports Git Bash" ;; *) fail "-CheckOnly reports Git Bash" "$out" ;; esac
[ ! -e "$B/brain.conf" ] && pass "-CheckOnly changes nothing" || fail "-CheckOnly changes nothing" "brain.conf created"

out="$(HOME="$H" KIT_PYTHON_NAMES="no-such-python" ps1 "$B/install.ps1" -CheckOnly 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && case "$out" in *Python*) true ;; *) false ;; esac \
  && pass "no Python → exit 1 and says Python" || fail "no Python" "rc=$rc $out"

out="$(HOME="$H" ps1 "$B/install.ps1" -Name Atlas -Org Acme 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && grep -qx 'NAME=Atlas' "$B/brain.conf" && grep -q "smoke test passed" <<<"$out" \
  && pass "install.ps1 runs install.sh (init + hooks) with -Name/-Org" || fail "install.ps1 runs install.sh" "rc=$rc $(printf '%s' "$out" | tail -3)"
! grep -qiE 'gh auth|git clone' "$KIT/install.ps1" && pass "install.ps1 never logs in or clones" || fail "install.ps1 never logs in or clones" "found"
rm -rf "$H"

finish
