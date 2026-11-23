#!/usr/bin/env bash
# Sets up this repo as a brain and wires it into Claude Code.
#
#   bash install.sh [init|hooks] [--name NAME] [--org ORG]
#   bash install.sh update [--version vX.Y.Z] [--force] [--yes]
#   bash install.sh doctor [--runner]
#   bash install.sh runner [--remove]
#
#   init   copy the skeleton from template/ into this repo — NEVER overwrites a file;
#          brain.conf from brain.conf.example with NAME/ORG; local files → .gitignore
#   hooks  register session-start/session-end in settings.json (CLAUDE_CONFIG_DIR or
#          ~/.claude), idempotent by command path; keep every other hook and setting;
#          back up the previous file; refuse an invalid settings.json; set
#          core.hooksPath for the pre-push scan; smoke-test the start hook
#   update fetch a release tag from kit/UPSTREAM (KIT_UPSTREAM overrides) and let
#          kit/update.py replace the engine files listed in kit.manifest; then init,
#          hooks and doctor from the NEW kit. Never commits — prints a suggested message
#   doctor check this machine's install (kit/doctor.sh)
#   runner schedule the nightly compiler on this machine (kit/runner.sh)
#   (none) init, then hooks
set -u
ROOT="$(cd "$(dirname "$0")" && pwd -P)"
cmd="all"
case "${1:-}" in init|hooks|update|doctor|runner) cmd="$1"; shift ;; esac
# doctor and runner take their own flags
case "$cmd" in
  doctor) exec bash "$ROOT/kit/doctor.sh" "$@" ;;
  runner) exec bash "$ROOT/kit/runner.sh" "$@" ;;
esac
NAME=""; ORG=""; WANT_VERSION=""; FORCE=""; YES=""
while [ $# -gt 0 ]; do
  case "$1" in
    --name) NAME="${2:-}"; shift 2 ;;
    --org)  ORG="${2:-}";  shift 2 ;;
    --version) [ "$cmd" = update ] || { echo "--version is only for update" >&2; exit 2; }; WANT_VERSION="${2:-}"; shift 2 ;;
    --force) [ "$cmd" = update ] || { echo "--force is only for update" >&2; exit 2; }; FORCE="--force"; shift ;;
    --yes)   [ "$cmd" = update ] || { echo "--yes is only for update" >&2; exit 2; }; YES="--yes"; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

. "$ROOT/hooks/common.sh"

do_init() {
  echo "── init: skeleton from template/ (existing files are kept)"
  local rel
  while IFS= read -r rel; do
    rel="${rel#./}"
    if [ -e "$ROOT/$rel" ]; then echo "  = $rel (exists, kept)"
    else mkdir -p "$(dirname "$ROOT/$rel")"; cp "$ROOT/template/$rel" "$ROOT/$rel"; echo "  ✓ $rel"; fi
  done < <(cd "$ROOT/template" && find . -type f ! -name gitignore | sort)

  if [ -e "$ROOT/brain.conf" ]; then echo "  = brain.conf (exists, kept)"
  else
    awk -v n="$NAME" -v o="$ORG" '
      /^NAME=/ && n != "" { print "NAME=" n; next }
      /^ORG=/  && o != "" { print "ORG=" o;  next }
      { print }' "$ROOT/brain.conf.example" > "$ROOT/brain.conf"
    echo "  ✓ brain.conf"
  fi

  local line added=0
  touch "$ROOT/.gitignore"
  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    grep -qxF "$line" "$ROOT/.gitignore" || { printf '%s\n' "$line" >> "$ROOT/.gitignore"; added=$((added+1)); }
  done < "$ROOT/template/gitignore"
  echo "  ✓ .gitignore (+$added lines)"

  # Installed kit version: what `update` compares against. Kept if present.
  if [ -f "$ROOT/.brain-kit/manifest" ]; then echo "  = .brain-kit/ (exists, kept)"
  elif [ -f "$ROOT/kit.manifest" ]; then
    mkdir -p "$ROOT/.brain-kit"
    cp "$ROOT/kit.manifest" "$ROOT/.brain-kit/manifest"
    tr -d '[:space:]' < "$ROOT/kit/VERSION" > "$ROOT/.brain-kit/version"; echo >> "$ROOT/.brain-kit/version"
    echo "  ✓ .brain-kit/ (kit v$(cat "$ROOT/.brain-kit/version"))"
  else
    echo "  ! no kit.manifest (development checkout) — .brain-kit/ not written; 'update' needs a release"
  fi
}

do_hooks() {
  local dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}" py win=0
  py="$(pick_python)" || { echo "hooks: no Python 3 found — cannot edit settings.json" >&2; return 1; }
  case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) win=1 ;; esac
  chmod +x "$ROOT"/hooks/*.sh "$ROOT/hooks/pre-push" "$ROOT"/compiler/*.sh 2>/dev/null || true
  echo "── hooks: $dir/settings.json"
  mkdir -p "$dir"
  "$py" - "$dir/settings.json" "$ROOT" "$win" <<'PY' || return 1
import json, os, shutil, sys, time
path, root, win = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
data = {}
if os.path.exists(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except ValueError as e:
        print(f"  ✗ {path} is not valid JSON ({e}) — refusing to touch it; fix it and re-run", file=sys.stderr)
        sys.exit(3)
    if not isinstance(data, dict):
        print(f"  ✗ {path} is not a JSON object — refusing to touch it", file=sys.stderr)
        sys.exit(3)
hooks = data.setdefault("hooks", {})
changed = False
# Prune THIS brain's entries whose script is gone (a kit update removed or renamed
# it): Claude Code would report a failing hook at every session. Others are kept.
prefix = f"{root}/hooks/"
for event in list(hooks):
    kept_groups = []
    for e in hooks[event]:
        kept = []
        for h in e.get("hooks", []):
            c = h.get("command") or ""
            i = c.find(prefix)
            if i >= 0:
                name = c[i + len(prefix):].split('"')[0].split()[0] if c[i + len(prefix):].strip() else ""
                if not name or not os.path.exists(prefix + name):
                    print(f"  ✓ {event}: removed stale entry → {prefix}{name}")
                    changed = True
                    continue
            kept.append(h)
        if kept:
            kept_groups.append(dict(e, hooks=kept))
        elif e.get("hooks"):
            changed = True
    hooks[event] = kept_groups
for event, script, timeout in (("SessionStart", "session-start.sh", 30), ("Stop", "session-end.sh", 15)):
    target = f"{root}/hooks/{script}"
    group = hooks.setdefault(event, [])
    # Idempotent by COMMAND PATH, not by a marker we wrote: an entry added by hand
    # or by an older installer carries no marker, and looking for one would duplicate it.
    if any(target in (h.get("command") or "") for e in group for h in e.get("hooks", [])):
        print(f"  = {event}: already registered")
        continue
    # quoted: the command runs through a shell, and the brain path may contain spaces
    hook = {"type": "command", "command": f'"{target}"', "timeout": timeout}
    if win:  # Git Bash cannot exec a .sh directly; pin the shell to bash
        hook.update(command=f'bash "{target}"', shell="bash")
    group.append({"hooks": [hook]})
    changed = True
    print(f"  ✓ {event}: registered")
if changed:
    if os.path.exists(path):
        backup = f"{path}.bak-{time.strftime('%Y%m%d%H%M%S')}"
        shutil.copy2(path, backup)
        print(f"  ✓ backup: {backup}")
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, path)
PY
  if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$ROOT" config core.hooksPath hooks && echo "  ✓ git core.hooksPath = hooks (pre-push secret scan)"
  else
    echo "  ! not a git repo — run 'git init' and re-run 'bash install.sh hooks' for the pre-push scan"
  fi

  local name out
  name="$(conf NAME Brain)"
  out="$(cd "$ROOT" && BRAIN_OFFLINE=1 bash hooks/session-start.sh </dev/null 2>&1)"
  case "$out" in
    "=== $name — "*) echo "  ✓ smoke test passed: session-start prints the brain's context" ;;
    *) echo "  ✗ smoke test FAILED: session-start printed:" >&2; printf '%s\n' "$out" | head -5 >&2; return 1 ;;
  esac
}

do_update() {
  local py upstream tag cur tmp rc out
  py="$(pick_python)" || { echo "update: no Python 3 found" >&2; return 1; }
  [ -f "$ROOT/.brain-kit/manifest" ] || { echo "update: no .brain-kit/ — run 'bash install.sh init' first" >&2; return 1; }
  upstream="${KIT_UPSTREAM:-$(head -1 "$ROOT/kit/UPSTREAM" 2>/dev/null)}"
  [ -n "$upstream" ] || { echo "update: no upstream (kit/UPSTREAM is missing)" >&2; return 1; }
  if [ -n "$WANT_VERSION" ]; then
    tag="v${WANT_VERSION#v}"
  else
    out="$(git ls-remote --tags --refs "$upstream" 'v*' 2>&1)" || { echo "update: cannot reach $upstream" >&2; printf '%s\n' "$out" | tail -2 >&2; return 1; }
    # only plain vX.Y.Z releases — pre-release tags are never picked automatically
    tag="$(printf '%s\n' "$out" | sed -n 's|.*refs/tags/\(v[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)$|\1|p' | sort -t. -k1.2,1n -k2,2n -k3,3n | tail -1)"
    [ -n "$tag" ] || { echo "update: no vX.Y.Z release tag at $upstream" >&2; return 1; }
  fi
  cur="v$(tr -d '[:space:]' < "$ROOT/.brain-kit/version" 2>/dev/null)"
  if [ "$cur" = "$tag" ]; then echo "already at $tag — nothing to change"; return 0; fi

  tmp="$(mktemp -d)"
  echo "── update: $cur → $tag from $upstream"
  if ! out="$(git -c advice.detachedHead=false clone -q --depth 1 --branch "$tag" "$upstream" "$tmp/kit" 2>&1)"; then
    echo "update: cannot fetch $tag from $upstream" >&2; printf '%s\n' "$out" | tail -2 >&2
    rm -rf "$tmp"; return 1
  fi
  if [ "v$(tr -d '[:space:]' < "$tmp/kit/kit/VERSION" 2>/dev/null)" != "$tag" ]; then
    echo "update: release $tag says kit/VERSION=$(cat "$tmp/kit/kit/VERSION" 2>/dev/null) — refusing a mislabelled release" >&2
    rm -rf "$tmp"; return 1
  fi
  "$py" "$ROOT/kit/update.py" --root "$ROOT" --source "$tmp/kit" $FORCE $YES
  rc=$?
  rm -rf "$tmp"
  [ "$rc" -eq 0 ] || return "$rc"
  [ "$cur" = "v$(tr -d '[:space:]' < "$ROOT/.brain-kit/version")" ] && return 0

  # the NEW kit finishes the job: new skeleton files, hook registration, health check
  bash "$ROOT/install.sh" init || return 1
  bash "$ROOT/install.sh" hooks || return 1
  if [ -f "$ROOT/kit/doctor.sh" ]; then bash "$ROOT/install.sh" doctor || echo "  ! doctor reported problems — see above"; fi
  echo
  echo "suggested commit: kit: update $cur → $tag"
  echo "  git add -A && git commit -m \"kit: update $cur → $tag\""
}

case "$cmd" in
  init)   do_init ;;
  hooks)  do_hooks ;;
  update) do_update ;;
  all)    do_init && do_hooks ;;
esac
