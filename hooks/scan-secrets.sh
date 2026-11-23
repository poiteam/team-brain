#!/usr/bin/env bash
# Fail-closed secret scan.
# Usage: scan-secrets.sh <file...>  → exit 0 = clean, 1 = finding.
#
# Fail-closed means: anything the scanner cannot vouch for is a finding —
# an unreadable file, a missing file, or grep itself erroring out. A push or a
# compiler run STOPS on a finding; never mask a value and continue.
#
# Patterns are written so they do not match themselves; when adding one, scan
# this script with itself — it must report zero findings.
set -u

findings=0

grep_rx() { # pattern file — prints matches; signals fail-closed if grep ITSELF errors
  local rx="$1" f="$2" out st
  # '--' is required: patterns starting with '-' (P4) would otherwise be read as grep options (fail-open).
  out=$(grep -EioIn -- "$rx" "$f" 2>/dev/null); st=$?
  if [ "$st" -gt 1 ]; then printf '0:SCANNER-ERROR(grep exit %s)\n' "$st"; return; fi
  [ -n "$out" ] && printf '%s\n' "$out"
  return 0
}

report() { # file line pattern
  printf '%s:%s %s\n' "$1" "$2" "$3"
  findings=1
}

scan_file() {
  local f="$1"
  if [ ! -e "$f" ]; then report "$f" 0 "UNREADABLE(missing) — fail-closed finding"; return; fi
  if [ ! -r "$f" ]; then report "$f" 0 "UNREADABLE(permission) — fail-closed finding"; return; fi

  local id rx line num val
  while IFS=$'\t' read -r id rx; do
    [ -n "$id" ] || continue
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      num="${line%%:*}"
      val="${line#*:}"
      # E1 — the matched VALUE (not the line!) points at a local host: not a finding
      case "$val" in
        *localhost*|*127.0.0.1*|*0.0.0.0*) continue ;;
      esac
      # E2 — a secretref: pointer is not a raw value
      case "$val" in
        secretref:*) continue ;;
      esac
      report "$f" "$num" "$id"
    done < <(grep_rx "$rx" "$f")
  done <<'PATTERNS'
P1	[A-Za-z][A-Za-z0-9+.-]{2,15}://[^[:space:]'"/:@]+:[^[:space:]'"/@]+@[^[:space:]'"/]+
P2	ATATT3[A-Za-z0-9_=-]{20,}
P3	AccountKey=[A-Za-z0-9+/=]{20,}
P3	DefaultEndpointsProtocol=http[s]
P4	-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----
P5	AKIA[0-9A-Z]{16}
P6	(FTP|SFTP)_(PASSWORD|PASS|PWD)[[:space:]]*=[[:space:]]*[^[:space:]]+
P7	(password|passwd|secret|api[_-]?key|access[_-]?key)[[:space:]]*[:=][[:space:]]*['"]?[^[:space:]'"]{8,}
PATTERNS
}

for f in "$@"; do
  scan_file "$f"
done

if [ "$findings" -ne 0 ]; then
  echo "SCAN: findings — fail-closed, stopping." >&2
fi
exit "$findings"
