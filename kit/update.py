#!/usr/bin/env python3
"""Replace this brain's kit (engine) files with a downloaded release.

Called by `install.sh update`, which downloads the release; this script only
compares and writes. A repo made from the template shares no git history with
the kit, so the manifests decide ownership:

  - only paths in the installed or the new kit.manifest are ever written or removed;
  - a manifest that names a team-owned path (PROTECTED) is refused outright;
  - an engine file the team edited by hand stops the update (exit 3) unless
    --force, which backs the edit up to .brain-kit/backup/<time>/ first;
  - nothing is committed — the team reviews the diff and commits.

  python3 kit/update.py --root BRAIN --source RELEASE_DIR [--force] [--yes]
Exit: 0 updated or already current · 1 error · 3 local edits (no --force) · 4 not confirmed
"""
import argparse
import os
import re
import shutil
import sys
import time
from dataclasses import dataclass, field

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import manifest  # noqa: E402

# Team-owned: a release may never write or delete these (prefixes end with "/").
PROTECTED = ("daily/", "projects/", "locked/", "incidents/", "runbooks/", "policies/", "queue/",
             ".git/", ".brain-kit/", "brain.conf", "README.md", "LICENSE", "CONTRIBUTING.md",
             "CHANGELOG.md", ".gitattributes", ".gitignore")
STATE = ".brain-kit"


@dataclass
class Plan:
    add: list = field(default_factory=list)
    change: list = field(default_factory=list)
    remove: list = field(default_factory=list)
    conflicts: list = field(default_factory=list)   # engine files edited locally (--force may overwrite)
    blocked: list = field(default_factory=list)     # TEAM files where a release adds one (never overwritten)


def _protected(path):
    return any(path.startswith(p) if p.endswith("/") else path == p for p in PROTECTED)


def bad_paths(root, paths):
    """Paths a release must not touch: absolute, escaping the root, or team-owned."""
    real_root = os.path.realpath(root)
    bad = []
    for p in paths:
        parts = p.replace("\\", "/").split("/")
        escapes = not os.path.realpath(os.path.join(root, p)).startswith(real_root + os.sep)
        if not p or os.path.isabs(p) or ".." in parts or _protected(p) or escapes:
            bad.append(p)
    return bad


def _disk(root, p):
    full = os.path.join(root, p)
    return manifest.sha256_file(full) if os.path.isfile(full) else None


def make_plan(root, old, new):
    """What the update writes/removes, and which of those paths carry local edits."""
    plan = Plan()
    for p in sorted(set(old) | set(new)):
        disk = _disk(root, p)
        if p in new and p not in old:
            if disk == new[p]:
                continue                      # already there, identical
            plan.add.append(p)
            if disk is not None:
                plan.blocked.append(p)        # a team file sits where the kit wants one
        elif p in new:
            if old[p] == new[p]:
                if disk is None:
                    plan.change.append(p)     # engine file deleted locally: restore it
                continue                      # unchanged in the release: local edits are kept
            plan.change.append(p)
            if disk is not None and disk != old[p]:
                plan.conflicts.append(p)
        else:
            if disk is None:
                continue
            plan.remove.append(p)
            if disk != old[p]:
                plan.conflicts.append(p)
    return plan


_VERSION_HEADING = re.compile(r"^## (\d+)\.(\d+)\.(\d+)\b")


def _vtuple(v):
    try:
        return tuple(int(x) for x in v.strip().split("."))
    except ValueError:
        return None


def changelog_between(text, old, new):
    """CHANGELOG sections newer than `old`, up to and including `new` (manual steps live there)."""
    lo, hi = _vtuple(old), _vtuple(new)
    out, keep = [], False
    for line in text.splitlines():
        m = _VERSION_HEADING.match(line)
        if m:
            v = tuple(int(x) for x in m.groups())
            keep = hi is not None and v <= hi and (lo is None or v > lo)
        elif line.startswith("# "):
            keep = False
        if keep:
            out.append(line)
    return "\n".join(out).strip()


def verify_source(source, new):
    """Files of the downloaded release that do not match its own manifest."""
    return manifest.mismatches(source, new)


def _remove_empty_dirs(root, path):
    d = os.path.dirname(os.path.join(root, path))
    real_root = os.path.realpath(root)
    while os.path.realpath(d) != real_root and os.path.isdir(d) and not os.listdir(d):
        os.rmdir(d)
        d = os.path.dirname(d)


def apply(root, source, plan, backup_dir):
    touched = plan.add + plan.change + plan.remove
    bad = bad_paths(root, touched)
    if bad:  # checked again here: nothing is written unless every path is allowed
        raise ValueError(f"refusing paths outside the kit: {', '.join(bad)}")
    if backup_dir:
        for p in plan.conflicts:
            src = os.path.join(root, p)
            if os.path.isfile(src):
                dst = os.path.join(backup_dir, p)
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.copy2(src, dst)
    for p in plan.add + plan.change:
        dst = os.path.join(root, p)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        tmp = dst + ".kit-tmp"
        shutil.copy2(os.path.join(source, p), tmp)   # copy2 keeps the mode (exec bit)
        os.replace(tmp, dst)
    for p in plan.remove:
        os.remove(os.path.join(root, p))
        _remove_empty_dirs(root, p)


def _read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def _write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--root", required=True)
    ap.add_argument("--source", required=True)
    ap.add_argument("--force", action="store_true", help="overwrite local edits (backed up first)")
    ap.add_argument("--yes", action="store_true", help="do not ask for confirmation")
    a = ap.parse_args(argv)
    for stream in (sys.stdout, sys.stderr):   # Windows consoles default to cp1252; we print "→"
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    root, source = a.root, a.source

    state_manifest = os.path.join(root, STATE, "manifest")
    if not os.path.isfile(state_manifest):
        print(f"no {STATE}/manifest — this brain was never initialised; run 'bash install.sh init' first",
              file=sys.stderr)
        return 1
    try:
        old = manifest.parse(_read(state_manifest))
        new_text = _read(os.path.join(source, "kit.manifest"))
        new = manifest.parse(new_text)
        new_version = _read(os.path.join(source, "kit", "VERSION")).strip()
    except (OSError, ValueError) as e:
        print(f"cannot read the release: {e}", file=sys.stderr)
        return 1
    old_version = (_read(os.path.join(root, STATE, "version")).strip()
                   if os.path.isfile(os.path.join(root, STATE, "version")) else "unknown")

    tampered = verify_source(source, new)
    if tampered:
        print("the downloaded kit does not match its own manifest — nothing changed:", file=sys.stderr)
        for t in tampered:
            print(f"  {t}", file=sys.stderr)
        return 1
    bad = bad_paths(root, sorted(set(old) | set(new)))
    if bad:
        print("a manifest names paths the kit may never touch — nothing changed:", file=sys.stderr)
        for p in bad:
            print(f"  {p}", file=sys.stderr)
        return 1

    plan = make_plan(root, old, new)
    if not (plan.add or plan.change or plan.remove):
        _write(state_manifest, new_text)
        _write(os.path.join(root, STATE, "version"), new_version + "\n")
        print(f"already at v{new_version} — nothing to change")
        return 0
    if plan.blocked:
        print("your own files sit where the new release adds kit files — nothing changed:")
        for p in plan.blocked:
            print(f"  ! {p}")
        print("move or rename them, then run the update again (--force never overwrites these)")
        return 3
    if plan.conflicts and not a.force:
        print("engine files edited locally — the update would overwrite them:")
        for p in plan.conflicts:
            print(f"  ! {p}")
        print("keep your change elsewhere, or re-run with --force (the edits are backed up first)")
        return 3

    print(f"kit update v{old_version} → v{new_version}:")
    for p in plan.add:
        print(f"  + {p}")
    for p in plan.change:
        print(f"  ~ {p}")
    for p in plan.remove:
        print(f"  - {p}")
    for p in plan.conflicts:
        print(f"  ! {p} (local edits backed up)")
    log_path = os.path.join(source, "CHANGELOG.md")
    if os.path.isfile(log_path):
        notes = changelog_between(_read(log_path), old_version, new_version)
        if notes:
            print("\nwhat changed (read any manual steps before you continue):\n")
            print(notes)
            print()
    if not a.yes:
        if not sys.stdin.isatty():
            print("no terminal to confirm on — re-run with --yes", file=sys.stderr)
            return 4
        try:
            answer = input("apply? [y/N] ")
        except EOFError:          # Ctrl-D, or Windows' NUL device posing as a tty
            answer = ""
        if answer.strip().lower() not in ("y", "yes"):
            print("\nnot applied")
            return 4

    backup = None
    if plan.conflicts:
        backup = os.path.join(root, STATE, "backup", time.strftime("%Y%m%d-%H%M%S"))
    try:
        apply(root, source, plan, backup)
    except (OSError, ValueError) as e:
        print(f"update failed: {e}", file=sys.stderr)
        return 1
    _write(os.path.join(root, "kit.manifest"), new_text)
    _write(state_manifest, new_text)
    _write(os.path.join(root, STATE, "version"), new_version + "\n")
    if backup:
        print(f"local edits backed up to {os.path.relpath(backup, root)}")
    print(f"updated v{old_version} → v{new_version}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
