#!/usr/bin/env python3
"""kit.manifest — the list of engine files of a kit release and their hashes.

One line per file, sorted by path, `sha256sum` style: `<64 hex>  <path>`.
The release build writes it; `install.sh update` reads it to tell kit files from
the team's own files and to spot engine files someone edited by hand.

Hashes are taken over content with CRLF normalised to LF: on a Windows checkout
with core.autocrlf the same file must not look locally edited.

  python3 kit/manifest.py build --root DIR PATH...   → manifest on stdout
  python3 kit/manifest.py check --root DIR MANIFEST  → exit 0 if every file matches
"""
import argparse
import hashlib
import os
import re
import sys

_LINE = re.compile(r"^([0-9a-f]{64})  (\S.*)$")


def sha256_file(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read().replace(b"\r\n", b"\n")).hexdigest()


def parse(text):
    entries = {}
    for no, line in enumerate(text.splitlines(), 1):
        if not line.strip():
            continue
        m = _LINE.match(line)
        if not m:
            raise ValueError(f"kit.manifest line {no} is not '<sha256>  <path>': {line!r}")
        entries[m.group(2)] = m.group(1)
    return entries


def render(entries):
    return "".join(f"{entries[p]}  {p}\n" for p in sorted(entries))


def build(root, paths):
    return {p: sha256_file(os.path.join(root, p)) for p in paths}


def mismatches(root, entries):
    """Paths whose file is missing or differs from the manifest, as 'missing: p' / 'changed: p'."""
    out = []
    for p in sorted(entries):
        full = os.path.join(root, p)
        if not os.path.isfile(full):
            out.append(f"missing: {p}")
        elif sha256_file(full) != entries[p]:
            out.append(f"changed: {p}")
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build")
    b.add_argument("--root", required=True)
    b.add_argument("paths", nargs="+")
    c = sub.add_parser("check")
    c.add_argument("--root", required=True)
    c.add_argument("manifest")
    a = ap.parse_args(argv)
    if a.cmd == "build":
        sys.stdout.write(render(build(a.root, a.paths)))
        return 0
    with open(a.manifest, encoding="utf-8") as f:
        bad = mismatches(a.root, parse(f.read()))
    for line in bad:
        print(line)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
