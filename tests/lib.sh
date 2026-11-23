#!/usr/bin/env bash
# Shared test helpers: a small but realistic sample brain built from the kit.
# Source it: . "$(dirname "$0")/lib.sh"

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fails=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s — %s\n' "$1" "$2"; fails=$((fails+1)); }
finish() { echo; [ "$fails" -eq 0 ] && { echo "ALL PASSED"; exit 0; }; echo "$fails failed"; exit 1; }

# Git for fixtures: fixed identity, no background maintenance (some git builds start
# a detached `git maintenance` after large commits and keep writing into .git,
# which makes `rm -rf` of the fixture fail with "Directory not empty").
g() { git -c user.email=t@t -c user.name=t -c maintenance.auto=false -c gc.auto=0 "$@"; }

bytes() { LC_ALL=C wc -c | tr -d ' '; }

# Byte offset of $2 inside $1, or -1.
offset() {
  local before="${1%%"$2"*}"
  [ "$before" = "$1" ] && { echo -1; return; }
  printf '%s' "$before" | bytes
}

# make_brain <dir> — sample brain: config, identity, INDEX (services, apps,
# incidents in three states), a daily template and two recent dailies.
make_brain() {
  local b="$1"
  mkdir -p "$b/hooks" "$b/compiler" "$b/locked" "$b/projects" "$b/daily" "$b/runbooks"
  cp "$KIT/hooks/"* "$b/hooks/"
  cp "$KIT/compiler/"* "$b/compiler/"
  printf 'NAME=Atlas\nORG=Acme\n' > "$b/brain.conf"
  printf '# Atlas\n\nYou are Atlas, the shared brain of Acme. Cite a source for every claim.\n' > "$b/locked/identity.md"
  cat > "$b/projects/INDEX.md" <<'EOF'
# INDEX

| id | family | status | aliases |
|---|---|---|---|
| billing-api | Services | active | billing, invoices |
| web-app | Apps | active | frontend, dashboard |
| search-worker | Services | active | indexer |

## Incidents

| index-stale-2026-09 | Incidents | open | nightly search index rebuild stalled after a schema change, so queries served day-old results while the health check only tested that the process was alive |
| cache-flap-2026-08 | Incidents | watching | cache node restarted twice |
| old-bug-2026-07 | Incidents | resolved | fixed long ago |
EOF
  printf -- '---\nauthor: <user name>\ndate: YYYY-MM-DD\n---\n' > "$b/daily/TEMPLATE.md"
  local today; today="$(date +%F)"
  printf -- '---\nauthor: zeynep\ndate: %s\nsession: aaaa1111\nrelated: [billing-api]\n---\n\n## Done\n- x\n' "$today" > "$b/daily/$today-zeynep-aaaa1111.md"
  printf -- '---\nauthor: mert\ndate: %s\nsession: bbbb2222\nrelated: [web-app, search-worker]\n---\n\n## Done\n- y\n' "$today" > "$b/daily/$today-mert-bbbb2222.md"
}

# copy_kit <dir> — the kit's files into <dir>, WITHOUT .git or caches. The kit repo
# is itself a git checkout with an origin remote (kit-ci): copying .git would hand
# every fixture brain that remote and that history.
copy_kit() {
  (cd "$KIT" && tar cf - --exclude=./.git --exclude='*/__pycache__' .) | (cd "$1" && tar xf -)
}

# new_home — a physical temp dir (macOS /var → /private/var), printed.
new_home() { local h; h="$(mktemp -d)"; (cd "$h" && pwd -P); }
