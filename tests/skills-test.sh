#!/usr/bin/env bash
# Contract tests for skills/*/SKILL.md.
# Run: bash tests/skills-test.sh   → exit 0 = all passed.
#
# 1) Agent Skills format (agentskills.io/specification): name 1–64 chars of
#    [a-z0-9-], no leading/trailing/double hyphen, equal to the directory name;
#    description 1–1024 chars; body under 500 lines (~5000 tokens recommended).
# 2) brain-routing agrees with the rest of the kit: the INDEX row format the
#    session-start hook parses, and the alias note written in the same
#    CANDIDATE/TARGET/BODY shape the compiler consumes.
set -u
. "$(dirname "$0")/lib.sh"

SKILLS="${SKILLS_DIR:-$KIT/skills}"
[ -d "$SKILLS" ] && [ -n "$(ls "$SKILLS")" ] && pass "kit ships skills" || fail "kit ships skills" "no skills/ directory"

for dir in "$SKILLS"/*/; do
  [ -d "$dir" ] || continue
  s="${dir%/}"; id="${s##*/}"; f="$s/SKILL.md"
  [ -f "$f" ] || { fail "$id: has SKILL.md" "missing"; continue; }
  fm="$(awk 'NR==1 && $0!="---"{exit} /^---$/{c++; if(c==2) exit; next} c==1' "$f")"
  name="$(printf '%s\n' "$fm" | sed -n 's/^name:[[:space:]]*//p')"
  desc="$(printf '%s\n' "$fm" | sed -n 's/^description:[[:space:]]*//p')"
  if printf '%s' "$name" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$' && [ "${#name}" -le 64 ]; then pass "$id: name is valid ($name)"
  else fail "$id: name is valid" "[$name]"; fi
  [ "$name" = "$id" ] && pass "$id: name equals the directory" || fail "$id: name equals the directory" "name=$name"
  dlen="$(printf '%s' "$desc" | wc -m | tr -d ' ')"
  [ "$dlen" -ge 1 ] && [ "$dlen" -le 1024 ] && pass "$id: description 1–1024 chars ($dlen)" || fail "$id: description 1–1024 chars" "$dlen"
  lines="$(wc -l < "$f" | tr -d ' ')"
  [ "$lines" -lt 500 ] && pass "$id: body under 500 lines ($lines)" || fail "$id: body under 500 lines" "$lines"
  approx="$(( $(wc -c < "$f") / 4 ))"
  [ "$approx" -le 5000 ] && pass "$id: ~$approx tokens (≤ 5000)" || fail "$id: ~$approx tokens (≤ 5000)" "too long for one activation"
done

R="$SKILLS/brain-routing/SKILL.md"
if [ -f "$R" ]; then
  grep -qF '| id | family | status | aliases |' "$R" && grep -qF 'NF >= 5' "$KIT/hooks/session-start.sh" \
    && pass "brain-routing: INDEX row format matches what session-start parses" \
    || fail "brain-routing: INDEX row format matches what session-start parses" "drift"
  grep -qE '^CANDIDATE: alias$' "$R" && grep -qE '^TARGET: ' "$R" && grep -qE '^BODY: ' "$R" \
    && pass "brain-routing: alias note uses the compiler's CANDIDATE/TARGET/BODY shape" \
    || fail "brain-routing: alias note uses the compiler's CANDIDATE/TARGET/BODY shape" "missing"
  grep -q 'alias' "$KIT/compiler/COMPILER.md" && grep -qE '^   - `alias` →' "$KIT/compiler/COMPILER.md" \
    && pass "brain-routing: the compiler has a rule for alias candidates" \
    || fail "brain-routing: the compiler has a rule for alias candidates" "missing"
  grep -qF 'projects/INDEX.md' "$R" && pass "brain-routing: reads projects/INDEX.md first" || fail "brain-routing: reads projects/INDEX.md first" "missing"
  for c in "Clean single" "Weak single" "Multiple" "Zero"; do
    grep -qF "**$c" "$R" && pass "brain-routing: defines the '$c' class" || fail "brain-routing: defines the '$c' class" "missing"
  done
else
  fail "brain-routing exists" "missing $R"
fi

finish
