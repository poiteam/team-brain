#!/usr/bin/env bash
# SessionStart hook (Claude Code / Codex) — puts the brain into the session.
# Everything printed to stdout enters the session context. Silent outside the
# brain's directories (hooks/common.sh: in_brain_dirs).
#
# Context budget: output never exceeds START_BUDGET bytes (default 8000). In the
# reference brain the output grew to 17.5 KB; Claude Code put a ~2 KB preview
# into context and saved the rest to a file — the routing index never reached
# the model. Fixed priority:
#   always:   header → identity … rule line (last)
#   budgeted: open incidents → routing summary → dailies → open compiler PR
# A budgeted section that does not fit is cut line by line and the cut is SAID.
# Full content always stays in the files: context routes, it is not the source.
set -u

[ "${BRAIN_HOOKS_OFF:-0}" = "1" ] && exit 0   # nested runs (the compiler's own claude -p calls)

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
in_brain_dirs || exit 0

NAME="$(conf NAME Brain)"
ORG="$(conf ORG "the team")"
BUDGET="${BRAIN_START_BUDGET:-$(conf START_BUDGET 8000)}"
OFFLINE="${BRAIN_OFFLINE:-0}"   # tests: no git pull, no gh
OUT=""
LEFT=0

blen() { local LC_ALL=C; BLEN=${#1}; }       # byte length → $BLEN
add() { OUT+="$1"$'\n'; }                     # unbudgeted line

# Budgeted section: stdin lines are added while they fit. $1 = title, $2 = source.
section() {
  local title="--- $1 ---" src="$2" line out=0
  blen "$title"
  if [ $((BLEN + 2)) -gt "$LEFT" ]; then
    while IFS= read -r line; do out=$((out+1)); done
    OUT+=$'\n'"(budget: '$1' truncated — $out lines left out, source: $src)"$'\n'
    return
  fi
  OUT+=$'\n'"$title"$'\n'; LEFT=$((LEFT - BLEN - 2))
  while IFS= read -r line; do
    if [ "$out" -eq 0 ]; then
      blen "$line"
      if [ $((BLEN + 1)) -le "$LEFT" ]; then
        OUT+="$line"$'\n'; LEFT=$((LEFT - BLEN - 1)); continue
      fi
    fi
    out=$((out+1))
  done
  [ "$out" -eq 0 ] || OUT+="(budget: '$1' truncated — $out lines left out, source: $src)"$'\n'
}

# INDEX table rows → "id<TAB>family<TAB>status<TAB>aliases" (no header/separator).
index_rows() {
  awk -F'|' 'NF >= 5 {
    id=$2; f=$3; s=$4; a=$5
    gsub(/^[ \t]+|[ \t]+$/, "", id); gsub(/^[ \t]+|[ \t]+$/, "", f)
    gsub(/[ \t*]/, "", s); gsub(/^[ \t]+|[ \t]+$/, "", a)
    if (id == "id" || id ~ /^-+$/) next
    print id "\t" f "\t" s "\t" a
  }' "$BRAIN/projects/INDEX.md" 2>/dev/null
}

open_incidents() { # aliases cut to 140 bytes at a word boundary (never splits a multibyte letter)
  index_rows | awk -F'\t' '$2 == "Incidents" && $3 ~ /^(open|watching)$/ {
    a=$4
    if (length(a) > 140) { a=substr(a, 1, 140); sub(/ [^ ]*$/, "", a); a=a " …" }
    print "· " $1 " — " $3 " — " a
  }'
}

# Compiler health — derived from git, because the nightly run's log lives only
# on the machine that runs it. If the oldest pending daily is ≥2 days old, the
# nightly compiler is not running. Prints nothing while healthy.
compiler_health() {
  [ -d "$BRAIN/.git" ] && [ -f "$BRAIN/compiler/new-dailies.sh" ] || return 0
  local list mark oldest threshold n
  list="$(bash "$BRAIN/compiler/new-dailies.sh" 2>/dev/null)" || return 0
  oldest="$(printf '%s\n' "$list" | sed -n 's|^daily/\([0-9]\{4\}-[0-9][0-9]-[0-9][0-9]\)-.*|\1|p' | sort | head -1)"
  [ -n "$oldest" ] || return 0
  threshold="$(date -v -2d +%F 2>/dev/null || date -d '-2 day' +%F)"
  [[ "$oldest" > "$threshold" ]] && return 0
  n="$(printf '%s\n' "$list" | grep -c '^daily/')"
  mark="$(printf '%s\n' "$list" | sed -n 's/^# watermark: \([0-9a-f]*\) \([0-9-]*\)T.*/\1 \2/p')"
  echo "· compiler — not running — $n dailies waiting, oldest $oldest (watermark: ${mark:-none}); the nightly run's log is on the machine that runs the compiler"
}

# Candidate queue health (backlog mode): candidates the size gate could not fit
# wait in queue/candidates.md and every run applies them first. A candidate
# waiting more than 7 days means the queue is not draining.
queue_health() {
  [ -f "$BRAIN/queue/candidates.md" ] && [ -f "$BRAIN/compiler/queue_candidates.py" ] || return 0
  local py o count oldest stale
  py="$(pick_python)" || return 0
  o="$("$py" "$BRAIN/compiler/queue_candidates.py" --root "$BRAIN" --summary 2>/dev/null)" || return 0
  count="${o%% candidates*}"; stale="${o##* days }"
  oldest="$(printf '%s' "$o" | sed -n 's/.*oldest \([0-9-]*\).*/\1/p')"
  [ "${stale:-0}" -gt 0 ] 2>/dev/null || return 0
  echo "· compiler queue — $stale candidates waiting more than 7 days (total $count, oldest $oldest); queue/candidates.md — the nightly run may not be draining it"
}

routing_summary() {
  echo "Full table (with aliases): projects/INDEX.md — read it FIRST to match a card."
  index_rows | awk -F'\t' '
    $2 == "Incidents" { ninc++; next }
    !($2 in ids) { order[++n]=$2; ids[$2]=$1; next }
    { ids[$2]=ids[$2] ", " $1 }
    END {
      for (i=1; i<=n; i++) print order[i] ": " ids[order[i]]
      if (ninc) print "Incidents: " ninc " cards — open ones above, all in the INDEX table"
    }'
  echo "Runbooks: runbooks/ — how-to and procedure questions go there first."
}

# Dailies of the last 7 days, one line per file: name + related cards.
recent_dailies() { # $1 = limit
  local limit="$1" found=0 shown=0 d f rel
  for i in 0 1 2 3 4 5 6; do
    d="$(date -v -"${i}"d +%F 2>/dev/null || date -d "-${i} day" +%F)"
    for f in "$BRAIN/daily/$d"-*.md; do
      [ -e "$f" ] || continue
      found=1
      if [ "$shown" -ge "$limit" ]; then echo "(… list capped at $limit files — the rest is in daily/)"; return; fi
      shown=$((shown+1))
      rel="$(awk -F': *' '/^---$/{c++; next} c==1 && $1=="related"{print $2}' "$f")"
      echo "· ${f##*/} ${rel}"
    done
  done
  [ "$found" -eq 1 ] || echo "(no dailies in the last 7 days)"
}

open_compiler_pr() {
  if [ "$OFFLINE" = "1" ]; then echo "(offline — not checked)"; return; fi
  local pr
  pr="$(cd "$BRAIN" && gh pr list --state open --search 'compiler in:title' --json number,title --jq '.[] | "#\(.number) \(.title)"' 2>/dev/null || true)"
  [ -n "$pr" ] && echo "$pr — waiting for merge" || echo "(none)"
}

# --- Always-on part ------------------------------------------------------------
add "=== $NAME — $ORG shared brain (session context) ==="
add "You are $NAME. The identity below is not a suggestion; it is who you are in this session."
add "Introduce yourself as $NAME and speak as $NAME; do not offer to be something else."

if [ "$OFFLINE" != "1" ] && ! git -C "$BRAIN" pull --ff-only -q 2>/dev/null; then
  add "[warning] Could not update the brain (network/conflict) — 'git -C $BRAIN pull' may be needed; continuing with the local copy."
fi

add ""; add "--- Identity (locked/identity.md) ---"
add "$(cat "$BRAIN/locked/identity.md" 2>/dev/null)"

RULE="Rule: at session end write your summary to daily/ (daily/TEMPLATE.md), scan it with hooks/scan-secrets.sh, commit and push. Make no claim without a source."

# Remaining budget: the always-on part + the rule line + one truncation notice per section.
blen "$OUT"; LEFT=$((BUDGET - BLEN))
blen "$RULE"; LEFT=$((LEFT - BLEN - 2 - 5 * 170))

# --- Budgeted sections, in priority order ---------------------------------------
section "Open incidents (INDEX Incidents: open/watching)" "projects/INDEX.md, incidents/" < <(compiler_health; queue_health; open_incidents)
section "Routing: card ids" "projects/INDEX.md" < <(routing_summary)
section "Dailies, last 7 days" "daily/" < <(recent_dailies 15)
section "Open compiler PR" "gh pr list" < <(open_compiler_pr)

OUT+=$'\n'"$RULE"$'\n'
printf '%s' "$OUT"
exit 0
