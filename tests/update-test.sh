#!/usr/bin/env bash
# Tests for `install.sh update` — download a tagged release and replace the engine files.
# Run: bash tests/update-test.sh   → exit 0 = all passed.
#
# A repo made from the template shares no history with the kit, so the update cannot
# be a git merge: it fetches a tag from the upstream (kit/UPSTREAM, or KIT_UPSTREAM in
# tests — a local git repo here) and lets kit/update.py swap the manifest's files.
# Safety contract: an unreachable upstream, a missing .brain-kit/ or a release whose
# version does not match its tag changes NOTHING; the update never commits.
set -u
. "$(dirname "$0")/lib.sh"

# make_upstream <dir> — a git repo holding the kit; tag_release <dir> <ver> [<file> <line>]
# commits kit/VERSION=<ver> (+ an optional appended line) with a fresh kit.manifest, tags v<ver>.
make_upstream() {
  mkdir -p "$1"
  copy_kit "$1"
  rm -f "$1/kit.manifest"
  g -C "$1" init -q
}
# The release build puts only `engine` files in kit.manifest; the kit repo's front page
# (README, LICENSE …) is never in it — update refuses a manifest that names those.
engine_files() {
  find . -type f ! -path './.git/*' ! -name kit.manifest | sed 's|^\./||' \
    | grep -vxE 'README\.md|CHANGELOG\.md|CONTRIBUTING\.md|LICENSE|\.gitattributes' | sort
}
tag_release() {
  local u="$1" ver="$2"
  printf '%s\n' "$ver" > "$u/kit/VERSION"
  [ -n "${3:-}" ] && printf '%s\n' "$4" >> "$u/$3"
  (cd "$u" && python3 kit/manifest.py build --root . $(engine_files) > kit.manifest)
  g -C "$u" add -A && g -C "$u" commit -qm "release $ver" && g -C "$u" tag "v$ver"
}
# new_brain → $H (HOME) and $B: a team repo made "from the template" at v0.1.0, initialised.
new_brain() {
  H="$(new_home)"; B="$H/brain"; mkdir -p "$B"
  (cd "$U" && git archive v0.1.0) | (cd "$B" && tar xf -)
  g -C "$B" init -q
  ( cd "$B" && HOME="$H" bash install.sh --name Atlas --org Acme ) >/dev/null 2>&1
  printf 'team daily\n' > "$B/daily/2026-11-01-zeynep-aaaa1111.md"
  printf 'Our own README\n' > "$B/README.md"
  g -C "$B" add -A && g -C "$B" commit -qm "brain"
}
upd() { ( cd "$B" && HOME="$H" KIT_UPSTREAM="$U" BRAIN_OFFLINE=1 bash install.sh update "$@" ) >"$H/update.out" 2>&1; echo $?; }
tree_hash() { (cd "$B" && find . -type f ! -path './.git/*' | sort | xargs shasum 2>/dev/null | shasum); }

UROOT="$(new_home)"; U="$UROOT/upstream"
make_upstream "$U"
tag_release "$U" 0.1.0
tag_release "$U" 0.2.0 hooks/common.sh "# v0.2.0 change"

# --- update to the latest tag
new_brain
team_before="$(cd "$B" && shasum README.md brain.conf daily/*.md projects/INDEX.md locked/*.md)"
commits_before="$(g -C "$B" rev-list --count HEAD)"
rc="$(upd --yes)"
[ "$rc" -eq 0 ] && pass "update exits 0" || fail "update exits 0" "rc=$rc $(tail -5 "$H/update.out")"
[ "$(cat "$B/.brain-kit/version")" = "0.2.0" ] && pass "update records the new version" || fail "update records the new version" "$(cat "$B/.brain-kit/version")"
grep -q "# v0.2.0 change" "$B/hooks/common.sh" && pass "update writes changed engine files" || fail "update writes changed engine files" "unchanged"
[ "$(cd "$B" && shasum README.md brain.conf daily/*.md projects/INDEX.md locked/*.md)" = "$team_before" ] \
  && pass "update leaves the team's files alone" || fail "update leaves the team's files alone" "changed"
[ "$(g -C "$B" rev-list --count HEAD)" = "$commits_before" ] && [ -n "$(g -C "$B" status --porcelain)" ] \
  && pass "update does not commit" || fail "update does not commit" "committed or no changes"
grep -q "suggested commit: kit: update v0.1.0 → v0.2.0" "$H/update.out" \
  && pass "update suggests a commit message" || fail "update suggests a commit message" "$(tail -3 "$H/update.out")"

# --- second run: already current
rc="$(upd --yes)"
[ "$rc" -eq 0 ] && grep -q "already at v0.2.0" "$H/update.out" && pass "second update: already current" || fail "second update: already current" "rc=$rc $(tail -2 "$H/update.out")"
rm -rf "$H"

# --- --version pins an older tag
tag_release "$U" 0.3.0 hooks/common.sh "# v0.3.0 change"
new_brain
rc="$(upd --yes --version v0.2.0)"
[ "$rc" -eq 0 ] && [ "$(cat "$B/.brain-kit/version")" = "0.2.0" ] && pass "--version pins a tag" || fail "--version pins a tag" "rc=$rc $(cat "$B/.brain-kit/version")"
rm -rf "$H"

# --- unreachable upstream: nothing changes
new_brain; before="$(tree_hash)"
rc="$( ( cd "$B" && HOME="$H" KIT_UPSTREAM="$UROOT/nowhere" bash install.sh update --yes ) >"$H/update.out" 2>&1; echo $?)"
[ "$rc" -ne 0 ] && [ "$(tree_hash)" = "$before" ] && pass "unreachable upstream → error, nothing changed" || fail "unreachable upstream" "rc=$rc"
rm -rf "$H"

# --- missing .brain-kit/: ask for init
new_brain; rm -rf "$B/.brain-kit"; before="$(tree_hash)"
rc="$(upd --yes)"
[ "$rc" -ne 0 ] && grep -q "install.sh init" "$H/update.out" && [ "$(tree_hash)" = "$before" ] \
  && pass "missing .brain-kit → asks for init, nothing changed" || fail "missing .brain-kit" "rc=$rc $(tail -2 "$H/update.out")"
rm -rf "$H"

# --- tags that are not plain vX.Y.Z are ignored when picking the latest
g -C "$U" tag v9.9.9-rc1 v0.3.0
new_brain
rc="$(upd --yes)"
[ "$rc" -eq 0 ] && [ "$(cat "$B/.brain-kit/version")" = "0.3.0" ] \
  && pass "latest = highest plain vX.Y.Z tag (pre-release tags ignored)" || fail "latest ignores pre-release tags" "rc=$rc $(cat "$B/.brain-kit/version")"
rm -rf "$H"

# --- a release whose kit/VERSION does not match its tag: refused
printf '0.9.0\n' > "$U/kit/VERSION"
(cd "$U" && python3 kit/manifest.py build --root . $(engine_files) > kit.manifest)
g -C "$U" add -A && g -C "$U" commit -qm "bad" && g -C "$U" tag v0.4.0
new_brain; before="$(tree_hash)"
rc="$(upd --yes)"
[ "$rc" -ne 0 ] && [ "$(tree_hash)" = "$before" ] && grep -q "0.9.0" "$H/update.out" \
  && pass "VERSION/tag mismatch → refused, nothing changed" || fail "VERSION/tag mismatch" "rc=$rc $(tail -2 "$H/update.out")"
rm -rf "$H"

# --- versions compare numerically: v0.10.0 is newer than v0.4.0 (and v0.9.x)
tag_release "$U" 0.10.0
new_brain
rc="$(upd --yes)"
[ "$rc" -eq 0 ] && [ "$(cat "$B/.brain-kit/version")" = "0.10.0" ] \
  && pass "latest compares versions numerically (v0.10.0 > v0.4.0)" || fail "numeric version order" "rc=$rc $(cat "$B/.brain-kit/version" 2>/dev/null)"
rm -rf "$H"

tag_release "$U" 2.0.0
tag_release "$U" 10.0.0
new_brain
rc="$(upd --yes)"
[ "$rc" -eq 0 ] && [ "$(cat "$B/.brain-kit/version")" = "10.0.0" ] \
  && pass "latest compares major versions numerically (v10 > v2)" || fail "numeric major order" "rc=$rc $(cat "$B/.brain-kit/version" 2>/dev/null)"
rm -rf "$H"

rm -rf "$UROOT"
finish
